//=============================================================================
// Módulo: IR (Receptor Infravermelho)
// Descrição: Decodificador de sinais infravermelhos no protocolo NEC.
//            Recebe sinais de controle remoto IR e decodifica comandos
//            de 32 bits, gerando um pulso quando novos dados são recebidos.
//
// Protocolo NEC:
//   - Leader: 9ms LOW + 4.5ms HIGH
//   - Bit 0: 562.5µs LOW + 562.5µs HIGH
//   - Bit 1: 562.5µs LOW + 1.6875ms HIGH
//   - Total: 32 bits (8 endereço + 8 ~endereço + 8 comando + 8 ~comando)
//=============================================================================
module IR(
    input         clk,            // Clock do sistema
    input         rst_n,          // Reset ativo em nível baixo
    input         IR,             // Sinal do receptor IR
    output [31:0] data_out,       // Dados decodificados (32 bits)
    output        new_data_pulse  // Pulso de 1 ciclo quando dados novos chegam
);

    //=========================================================================
    // Registradores de Saída
    //=========================================================================
    reg [31:0] data_out;
    reg new_data_pulse;

    //=========================================================================
    // Registradores Internos para Armazenamento de Bytes
    //=========================================================================
    reg [7:0] led1;        // Byte 0: Endereço
    reg [7:0] led2;        // Byte 1: Endereço invertido (usado para comando)
    reg [7:0] led3;        // Byte 2: Comando
    reg [7:0] led4;        // Byte 3: Comando invertido

    //=========================================================================
    // Registradores de Controle da Máquina de Estados
    //=========================================================================
    reg [15:0] irda_data;  // Buffer de dados IRDA (não utilizado diretamente)
    reg [31:0] get_data;   // Registrador de deslocamento para captura dos 32 bits
    reg [5:0]  data_cnt;   // Contador de bits recebidos (0-32)
    reg [2:0]  cs, ns;     // Estado atual e próximo estado
    reg error_flag;        // Flag de erro de temporização
    reg data_ready;        // Flag indicando que 32 bits foram recebidos

    //=========================================================================
    // Sincronização do Sinal IR (Prevenção de Metaestabilidade)
    // Utiliza registradores em cascata para sincronizar o sinal assíncrono
    //=========================================================================
    reg irda_reg0;  // Primeiro estágio de sincronização
    reg irda_reg1;  // Segundo estágio de sincronização
    reg irda_reg2;  // Terceiro estágio (para detecção de borda)

    // Sinais de detecção de borda
    wire irda_neg_pulse;  // Pulso na borda de descida
    wire irda_pos_pulse;  // Pulso na borda de subida
    wire irda_chang;      // Qualquer mudança no sinal

    // Sincronizador de 3 estágios
    always @(posedge clk) begin
        if (!rst_n) begin
            irda_reg0 <= 1'b0;
            irda_reg1 <= 1'b0;
            irda_reg2 <= 1'b0;
        end
        else begin
            irda_reg0 <= IR;         // Captura sinal externo
            irda_reg1 <= irda_reg0;  // Primeiro registro sincronizado
            irda_reg2 <= irda_reg1;  // Segundo registro para detecção de borda
        end
    end

    // Detecção de bordas comparando registradores consecutivos
    assign irda_chang = irda_neg_pulse | irda_pos_pulse;
    assign irda_neg_pulse = irda_reg2 & (~irda_reg1);   // Borda de descida
    assign irda_pos_pulse = (~irda_reg2) & irda_reg1;   // Borda de subida

    //=========================================================================
    // Contadores de Temporização
    // Medem a duração dos pulsos para identificar o protocolo NEC
    //=========================================================================
    reg [10:0] counter;   // Contador rápido (ciclos de clock)
    reg [8:0]  counter2;  // Contador de períodos (unidades de ~1750 ciclos)

    // Flags de verificação de temporização
    wire check_9ms;  // Verifica pulso leader de 9ms
    wire check_4ms;  // Verifica pulso leader de 4.5ms
    wire low;        // Verifica pulso curto (bit 0 ou início de bit)
    wire high;       // Verifica pulso longo (bit 1)

    // Contador principal - conta até 1750 ciclos, depois incrementa counter2
    always @(posedge clk) begin
        if (!rst_n)
            counter <= 11'd0;
        else if (irda_chang)
            counter <= 11'd0;              // Reset ao detectar mudança no sinal
        else if (counter == 11'd1750)
            counter <= 11'd0;              // Overflow - reinicia
        else
            counter <= counter + 1'b1;     // Incrementa
    end

    // Contador secundário - conta quantos períodos de 1750 ciclos passaram
    always @(posedge clk) begin
        if (!rst_n)
            counter2 <= 9'd0;
        else if (irda_chang)
            counter2 <= 9'd0;              // Reset ao detectar mudança
        else if (counter == 11'd1750)
            counter2 <= counter2 + 1'b1;   // Incrementa a cada 1750 ciclos
    end

    // Verificações de temporização baseadas no protocolo NEC
    // Os valores são calibrados para o clock do sistema
    assign check_9ms = ((217 < counter2) & (counter2 < 297));  // ~9ms (leader start)
    assign check_4ms = ((88 < counter2) & (counter2 < 168));   // ~4.5ms (leader space)
    assign low  = ((6 < counter2) & (counter2 < 26));          // ~562µs (bit space curto)
    assign high = ((38 < counter2) & (counter2 < 58));         // ~1.6ms (bit space longo)

    //=========================================================================
    // Definição dos Estados da Máquina de Estados
    //=========================================================================
    parameter IDLE       = 3'b000;  // Aguardando início de transmissão
    parameter LEADER_9   = 3'b001;  // Recebendo pulso leader de 9ms (LOW)
    parameter LEADER_4   = 3'b010;  // Recebendo pulso leader de 4.5ms (HIGH)
    parameter DATA_STATE = 3'b100;  // Recebendo os 32 bits de dados

    //=========================================================================
    // Lógica Sequencial - Atualização do Estado Atual
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            cs <= IDLE;
        else
            cs <= ns;
    end

    //=========================================================================
    // Lógica Combinacional - Cálculo do Próximo Estado
    //=========================================================================
    always @(*) begin
        case (cs)
            // IDLE: Aguarda início de transmissão (sinal vai para LOW)
            IDLE: begin
                if (~irda_reg1)
                    ns = LEADER_9;     // Detectou início do leader
                else
                    ns = IDLE;
            end

            // LEADER_9: Aguarda fim do pulso de 9ms e valida temporização
            LEADER_9: begin
                if (irda_pos_pulse) begin
                    if (check_9ms)
                        ns = LEADER_4;  // Temporização correta, avança
                    else
                        ns = IDLE;      // Temporização incorreta, reinicia
                end
                else
                    ns = LEADER_9;      // Continua aguardando
            end

            // LEADER_4: Aguarda fim do pulso de 4.5ms e valida temporização
            LEADER_4: begin
                if (irda_neg_pulse) begin
                    if (check_4ms)
                        ns = DATA_STATE; // Temporização correta, inicia dados
                    else
                        ns = IDLE;       // Temporização incorreta, reinicia
                end
                else
                    ns = LEADER_4;       // Continua aguardando
            end

            // DATA_STATE: Recebe os 32 bits de dados
            DATA_STATE: begin
                if ((data_cnt == 6'd32) & irda_reg2 & irda_reg1)
                    ns = IDLE;           // Todos os bits recebidos, finaliza
                else if (error_flag)
                    ns = IDLE;           // Erro detectado, reinicia
                else
                    ns = DATA_STATE;     // Continua recebendo dados
            end

            default:
                ns = IDLE;
        endcase
    end

    //=========================================================================
    // Lógica de Captura de Dados
    // Implementa registrador de deslocamento para capturar os 32 bits
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            data_cnt   <= 6'd0;
            get_data   <= 32'd0;
            error_flag <= 1'b0;
            data_ready <= 1'b0;
        end
        else if (cs == IDLE) begin
            // Reset dos contadores ao entrar em IDLE
            data_cnt   <= 6'd0;
            get_data   <= 32'd0;
            error_flag <= 1'b0;
            data_ready <= 1'b0;
        end
        else if (cs == DATA_STATE) begin
            // Borda de subida: verifica se o pulso LOW está correto
            if (irda_pos_pulse) begin
                if (!low)
                    error_flag <= 1'b1;  // Pulso LOW com duração incorreta
            end
            // Borda de descida: captura o bit baseado na duração do HIGH
            else if (irda_neg_pulse) begin
                if (low)
                    get_data[0] <= 1'b0;      // Pulso curto = bit 0
                else if (high)
                    get_data[0] <= 1'b1;      // Pulso longo = bit 1
                else
                    error_flag <= 1'b1;       // Duração inválida

                // Desloca os bits para a esquerda (LSB first no protocolo NEC)
                get_data[31:1] <= get_data[30:0];
                data_cnt <= data_cnt + 1'b1;

                // Sinaliza dados prontos ao completar 32 bits
                if (data_cnt == 6'd31)
                    data_ready <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Geração do Pulso de Novos Dados
    // Gera pulso de 1 ciclo de clock na borda de subida de data_ready
    //=========================================================================
    reg data_ready_prev;  // Registrador para detecção de borda

    always @(posedge clk) begin
        if (!rst_n)
            data_ready_prev <= 1'b0;
        else
            data_ready_prev <= data_ready;
    end

    // Pulso na transição 0->1 de data_ready
    always @(posedge clk) begin
        if (!rst_n)
            new_data_pulse <= 1'b0;
        else
            new_data_pulse <= data_ready & ~data_ready_prev;
    end

    //=========================================================================
    // Extração dos Bytes Recebidos
    // Separa os 32 bits em 4 bytes após recepção completa
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            led1 <= 8'd0;
            led2 <= 8'd0;
            led3 <= 8'd0;
            led4 <= 8'd0;
        end
        else if ((data_cnt == 6'd32) & irda_reg1) begin
            led1 <= get_data[7:0];    // Byte 0: Endereço do dispositivo
            led2 <= get_data[15:8];   // Byte 1: Endereço invertido / ID comando
            led3 <= get_data[23:16];  // Byte 2: Código do comando
            led4 <= get_data[31:24];  // Byte 3: Comando invertido (verificação)
        end
    end

    //=========================================================================
    // Decodificação dos Comandos do Controle Remoto
    // Mapeia os códigos recebidos para comandos de 32 bits do sistema
    //
    // Mapeamento:
    //   Botão 0 (0x68) -> 0x80000000 (comando 0)
    //   Botão 1 (0x30) -> 0x60000000 (comando 1)
    //   Botão 2 (0x18) -> 0xA0000000 (comando 2)
    //   Botão 3 (0x7A) -> 0xC0000000 (comando 3)
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            data_out <= 32'd0;
        else if (new_data_pulse) begin
            case (led2)
                8'b01101000:  // 0x68 - Botão 0 do controle remoto
                    data_out <= 32'h80000000;

                8'b00110000:  // 0x30 - Botão 1 do controle remoto
                    data_out <= 32'h60000000;

                8'b00011000:  // 0x18 - Botão 2 do controle remoto
                    data_out <= 32'hA0000000;

                8'b01111010:  // 0x7A - Botão 3 do controle remoto
                    data_out <= 32'hC0000000;

                default:
                    data_out <= data_out;  // Mantém valor para comandos desconhecidos
            endcase
        end
    end

endmodule