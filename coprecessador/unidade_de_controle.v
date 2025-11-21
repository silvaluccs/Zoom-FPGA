//=============================================================================
// Módulo: unidade_de_controle
// Descrição: Controlador principal para processamento de imagem com operações
//            de zoom in/out usando diferentes algoritmos de interpolação.
//            Gerencia a máquina de estados para leitura, processamento e 
//            escrita de pixels na memória de vídeo.
//=============================================================================
module unidade_de_controle(
    // Entradas de clock e controle
    input clock_50Mhz,           // Clock principal de 50MHz
  
    // Interface de instruções
    input [31:0] instrucoes,     // Barramento de instruções
    input enable_read,           // Habilita leitura de nova instrução
    
    // Saídas VGA
    output wire hsync,           // Sincronismo horizontal VGA
    output wire vsync,           // Sincronismo vertical VGA
    output [7:0] red,            // Canal vermelho (8 bits)
    output [7:0] green,          // Canal verde (8 bits)
    output [7:0] blue,           // Canal azul (8 bits)
    output sync,                 // Sinal de sincronismo composto
    output clk,                  // Clock de saída VGA
    output blank                 // Sinal de blanking
);

    //=========================================================================
    // Sinais do Decodificador de Instruções
    //=========================================================================
    wire [2:0] opcode_instrucao;  // Opcode decodificado da instrução
    wire escrita_sinal;           // Sinal de escrita do decodificador
    wire [7:0] pixel_escrever;    // Pixel a ser escrito (modo direto)
    wire [16:0] endereco_escrv;   // Endereço de escrita (modo direto)

    //=========================================================================
    // Sincronizador de Domínio de Clock (50MHz -> 25MHz)
    // Gera pulso de um ciclo quando nova instrução está disponível
    //=========================================================================
    reg sync1 = 1'b0;
    reg sync2 = 1'b0;

    always @(posedge clock) begin
        sync1 <= enable_read;
        sync2 <= sync1;
    end

    // Detector de borda de subida para nova instrução
    wire new_data_pulse_25 = sync1 & ~sync2;

    //=========================================================================
    // Instanciação do Decodificador de Instruções
    //=========================================================================
    decodificador deco(
        .clock(new_data_pulse_25),
        .instrucoes(instrucoes),
        .opcode(opcode_instrucao),
        .zoom_in(zoom_in_s),
        .zoom_out(zoom_out_s),
        .escrita(escrita_sinal),
        .pixel(pixel_escrever),
        .endereco(endereco_escrv)
    );

    //=========================================================================
    // Sinais de Clock
    //=========================================================================
    wire clock;          // Clock de 25MHz (dividido)
    wire clock_75_mhz;   // Clock de 75MHz (para VGA)

    
    //=========================================================================
    // Divisor de Clock: 50MHz -> 25MHz
    //=========================================================================
    divisor_clock_por_2 divisor_clock_50MHZ(
        .clock_entrada(clock_50Mhz),
        .clock_saida(clock)
    );

    //=========================================================================
    // Definição dos Estados da Máquina de Estados
    //=========================================================================
    parameter IDLE            = 0;  // Aguardando instrução
    parameter LOAD_OP         = 1;  // Carregando operação
    parameter READ_PIXEL      = 2;  // Lendo pixel da memória
    parameter EXECUTE         = 3;  // Executando algoritmo
    parameter WRITE           = 4;  // Escrevendo pixel processado
    parameter NEXT_PIXEL      = 5;  // Avançando para próximo pixel
    parameter END_INSTRUCTION = 6;  // Finalizando instrução
    parameter WAIT_READ       = 7;  // Aguardando leitura (média de blocos)
    parameter WRITE_IMAGEM    = 8;  // Escrita direta de imagem

    //=========================================================================
    // Definição dos Índices para Salvamento de Pixels
    //=========================================================================
    parameter ENDERECO_1 = 0;
    parameter ENDERECO_2 = 1;
    parameter ENDERECO_3 = 2;
    parameter ENDERECO_4 = 3;
    parameter ENDERECO_5 = 4;

    //=========================================================================
    // Definição dos Opcodes de Operação
    //=========================================================================
    localparam REPLICACAO_PIXEL       = 3'b100;  // Zoom in: replicação simples
    localparam VIZINHO_MAIS_PROXIMO   = 3'b101;  // Zoom in: vizinho mais próximo
    localparam MEDIA_DE_BLOCOS        = 3'b010;  // Zoom out: média de blocos 2x2
    localparam VIZINHO_MAIS_PROXIMO_OUT = 3'b011; // Zoom out: vizinho mais próximo
    localparam RESET_IMAGEM           = 3'b111;  // Reset da imagem

    //=========================================================================
    // Endereço Base para Algoritmos de Zoom In
    // Corresponde à posição (120, 160) na imagem 320x240
    //=========================================================================
    parameter ENDERECO_BASE = 17'd38560;

    //=========================================================================
    // Registradores de Estado e Controle
    //=========================================================================
    reg [3:0] estado_atual, proximo_estado;
    reg [16:0] endereco_memoria, endereco_memoria_next;
    reg [16:0] endereco_escrita, endereco_escrita_next;
    reg escrita_dados, escrita_dados_next;
   
    reg [7:0] pixel_para_processar_reg;
    reg [7:0] pixel_para_salvar, pixel_para_salvar_next;
    reg [2:0] salvar_pixels, salvar_pixels_next;
    reg dados_prontos, dados_prontos_next;
    reg [2:0] opcode, opcode_next;
    
    // Fios para dados de pixel
    wire [7:0] pixel_para_processar;
    wire [31:0] pixels_processados;

    //=========================================================================
    // Registradores de Posição (linha/coluna)
    //=========================================================================
    reg [8:0] linha;
    reg [8:0] coluna;
    reg [16:0] endereco_base_para_escrita;
    reg [16:0] endereco_base_para_escrita_next;
    
    // Contadores auxiliares para zoom out
    reg [8:0] linha_aux;
    reg [8:0] coluna_aux;

    //=========================================================================
    // Registradores para Média de Blocos (4 pixels vizinhos)
    //=========================================================================
    reg [7:0] pixel_m_1, pixel_m_1_next;
    reg [7:0] pixel_m_2, pixel_m_2_next;
    reg [7:0] pixel_m_3, pixel_m_3_next;
    reg [7:0] pixel_m_4, pixel_m_4_next;
    wire [7:0] pixel_media_p;

    //=========================================================================
    // Bloco Sequencial - Atualização de Registradores
    //=========================================================================
    always @(posedge clock) begin
        estado_atual <= proximo_estado;
        
        // Reset de variáveis auxiliares no estado IDLE ou WRITE_IMAGEM
        if (estado_atual == IDLE || estado_atual == WRITE_IMAGEM) begin
            linha_aux <= 9'd60;   // Início da região central (linha)
            coluna_aux <= 9'd80;  // Início da região central (coluna)
        end 
        else begin
            // Atualização de contadores durante zoom out (vizinho mais próximo)
            if (estado_atual == WRITE && 
                opcode == VIZINHO_MAIS_PROXIMO_OUT && 
                salvar_pixels == ENDERECO_1) begin
                
                if ((linha % 2 == 0) && (coluna % 2 != 0)) begin
                    if (coluna_aux == 9'd239) begin
                        linha_aux <= linha_aux + 1'b1;
                        coluna_aux <= 9'd80;
                    end 
                    else begin
                        coluna_aux <= coluna_aux + 1'b1;
                    end
                end
            end

            // Atualização de contadores durante zoom out (média de blocos)
            if (estado_atual == WRITE && 
                opcode == MEDIA_DE_BLOCOS && 
                salvar_pixels == ENDERECO_1) begin
                
                if ((linha % 2 == 0) && (coluna % 2 != 0)) begin
                    if (coluna_aux == 9'd239) begin
                        linha_aux <= linha_aux + 1'b1;
                        coluna_aux <= 9'd80;
                    end 
                    else begin
                        coluna_aux <= coluna_aux + 1'b1;
                    end
                end
            end
        end
        
        // Atualização dos demais registradores
        endereco_memoria <= endereco_memoria_next;
        endereco_escrita <= endereco_escrita_next;
        escrita_dados <= escrita_dados_next;
        pixel_para_salvar <= pixel_para_salvar_next;
        salvar_pixels <= salvar_pixels_next;
        dados_prontos <= dados_prontos_next;
        opcode <= opcode_next;
        pixel_para_processar_reg <= pixel_para_processar;
        endereco_base_para_escrita <= endereco_base_para_escrita_next;
        pixel_m_1 <= pixel_m_1_next;
        pixel_m_2 <= pixel_m_2_next;
        pixel_m_3 <= pixel_m_3_next;
        pixel_m_4 <= pixel_m_4_next;
    end

    //=========================================================================
    // Bloco Combinacional - Lógica da Máquina de Estados
    //=========================================================================
    always @(*) begin
        // Valores padrão para evitar latches
        proximo_estado = estado_atual;
        endereco_memoria_next = endereco_memoria;
        endereco_escrita_next = endereco_escrita;
        escrita_dados_next = escrita_dados;
        pixel_para_salvar_next = pixel_para_salvar;
        salvar_pixels_next = salvar_pixels;
        dados_prontos_next = dados_prontos;
        opcode_next = opcode;
        endereco_base_para_escrita_next = endereco_base_para_escrita;
        pixel_m_1_next = pixel_m_1;
        pixel_m_2_next = pixel_m_2;
        pixel_m_3_next = pixel_m_3;
        pixel_m_4_next = pixel_m_4;

        case (estado_atual)
            //=================================================================
            // IDLE: Aguardando nova instrução
            //=================================================================
            IDLE: begin
                escrita_dados_next = 1'b0;
                endereco_memoria_next = ENDERECO_BASE;
                dados_prontos_next = 1'b0;
                
                if (new_data_pulse_25) begin
                    proximo_estado = LOAD_OP;
                end 
                else begin
                    proximo_estado = IDLE;
                end
            end

            //=================================================================
            // LOAD_OP: Decodifica e carrega a operação
            //=================================================================
            LOAD_OP: begin
                case (opcode_instrucao) 
                    // Zoom In (replicação ou vizinho mais próximo)
                    3'b011, 3'b100: begin
                        // Se estava em zoom out, primeiro reseta a imagem
                        if (opcode == VIZINHO_MAIS_PROXIMO_OUT || 
                            opcode == MEDIA_DE_BLOCOS) begin
                            opcode_next = RESET_IMAGEM;
                            endereco_memoria_next = 17'd0;
                        end 
                        else begin
                            opcode_next = (opcode_instrucao == 3'b011) ? 
                                          VIZINHO_MAIS_PROXIMO : REPLICACAO_PIXEL;
                            endereco_memoria_next = ENDERECO_BASE;
                        end
                        proximo_estado = READ_PIXEL;
                    end
                    
                    // Zoom Out (vizinho mais próximo ou média)
                    3'b101, 3'b110: begin
                        // Se estava em zoom in, primeiro reseta a imagem
                        if (opcode == VIZINHO_MAIS_PROXIMO || 
                            opcode == REPLICACAO_PIXEL) begin
                            opcode_next = RESET_IMAGEM;
                            endereco_memoria_next = 17'd0;
                        end 
                        else begin
                            opcode_next = (opcode_instrucao == 3'b101) ? 
                                          VIZINHO_MAIS_PROXIMO_OUT : MEDIA_DE_BLOCOS;
                            endereco_memoria_next = 17'd0;
                        end
                        proximo_estado = READ_PIXEL;
                    end
                    
                    // Escrita direta de pixel
                    3'b111: begin
                        endereco_escrita_next = endereco_escrv;
                        pixel_para_salvar_next = pixel_escrever;
                        escrita_dados_next = 1'b1;
                        proximo_estado = WRITE_IMAGEM;
                    end
                    
                    default: begin
                        proximo_estado = IDLE;
                    end
                endcase
            end

            //=================================================================
            // WRITE_IMAGEM: Escrita direta concluída
            //=================================================================
            WRITE_IMAGEM: begin
                escrita_dados_next = 1'b0;
                opcode_next = 3'b000;  // Limpa opcode
                proximo_estado = IDLE;
            end

            //=================================================================
            // READ_PIXEL: Lê pixel da memória
            //=================================================================
            READ_PIXEL: begin
                escrita_dados_next = 1'b0;
                
                // Média de blocos precisa ler 4 pixels
                if (opcode_next == MEDIA_DE_BLOCOS) begin
                    proximo_estado = WAIT_READ;
                    endereco_base_para_escrita_next = endereco_memoria_next;
                    salvar_pixels_next = ENDERECO_1;
                end 
                else begin
                    proximo_estado = EXECUTE;
                end
            end

            //=================================================================
            // WAIT_READ: Leitura sequencial dos 4 pixels para média
            //=================================================================
            WAIT_READ: begin
                case (salvar_pixels) 
                    ENDERECO_1: begin
                        endereco_memoria_next = endereco_base_para_escrita_next;
                        salvar_pixels_next = ENDERECO_2;
                    end 
                    ENDERECO_2: begin
                        pixel_m_1_next = pixel_para_processar;
                        endereco_memoria_next = endereco_base_para_escrita_next + 17'd1;
                        salvar_pixels_next = ENDERECO_3;
                    end
                    ENDERECO_3: begin
                        pixel_m_2_next = pixel_para_processar;
                        endereco_memoria_next = endereco_base_para_escrita_next + 17'd320;
                        salvar_pixels_next = ENDERECO_4;
                    end
                    ENDERECO_4: begin
                        pixel_m_3_next = pixel_para_processar;
                        endereco_memoria_next = endereco_base_para_escrita_next + 17'd321;
                        salvar_pixels_next = ENDERECO_5;
                    end
                    ENDERECO_5: begin
                        pixel_m_4_next = pixel_para_processar;
                        endereco_memoria_next = endereco_base_para_escrita_next;
                        proximo_estado = EXECUTE;
                    end
                    default: begin
                        proximo_estado = EXECUTE;
                    end
                endcase
            end

            //=================================================================
            // EXECUTE: Prepara para escrita
            //=================================================================
            EXECUTE: begin
                salvar_pixels_next = ENDERECO_1;
                proximo_estado = WRITE;
            end

            //=================================================================
            // WRITE: Escreve pixels processados na memória
            //=================================================================
            WRITE: begin
                escrita_dados_next = 1'b1;
                
                case (opcode_next)
                    //=========================================================
                    // Zoom Out - Média de Blocos
                    //=========================================================
                    MEDIA_DE_BLOCOS: begin
                        coluna = (endereco_memoria % 17'd320);
                        linha = (endereco_memoria / 17'd320);
                        
                        case (salvar_pixels)
                            ENDERECO_1: begin
                                // Verifica linha PAR e coluna ÍMPAR
                                if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
                                    // Escreve no centro da imagem
                                    endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
                                    salvar_pixels_next = ENDERECO_3;
                                    proximo_estado = WRITE;
                                    pixel_para_salvar_next = pixel_media_p;
                                end 
                                else begin
                                    // Bordas: preenche com preto
                                    if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                        (linha < 9'd60) || (linha >= 9'd180)) begin
                                        escrita_dados_next = 1'b1;
                                        endereco_escrita_next = endereco_memoria;
                                        pixel_para_salvar_next = 8'd0;
                                    end 
                                    else begin
                                        escrita_dados_next = 1'b0;
                                        endereco_escrita_next = endereco_memoria;
                                        pixel_para_salvar_next = 8'd0;
                                    end
                                    endereco_memoria_next = endereco_memoria + 1'b1;
                                    proximo_estado = NEXT_PIXEL;
                                end
                            end
                            
                            ENDERECO_3: begin
                                endereco_escrita_next = endereco_memoria;
                                if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                    (linha < 9'd60) || (linha >= 9'd180)) begin
                                    escrita_dados_next = 1'b1;
                                    pixel_para_salvar_next = 8'd0;
                                end 
                                else begin
                                    escrita_dados_next = 1'b0;
                                    pixel_para_salvar_next = 8'd0;
                                end
                                proximo_estado = NEXT_PIXEL;
                                endereco_memoria_next = endereco_memoria + 1'b1;
                            end
                            
                            default: begin
                                proximo_estado = END_INSTRUCTION;
                            end
                        endcase

                        // Verifica fim da memória
                        if (endereco_memoria_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end
                    end

                    //=========================================================
                    // Reset da Imagem
                    //=========================================================
                    RESET_IMAGEM: begin
                        endereco_escrita_next = endereco_memoria_next;
                        endereco_memoria_next = endereco_memoria + 1'b1;
                        pixel_para_salvar_next = pixels_processados[7:0];
                        escrita_dados_next = 1'b1;

                        if (endereco_memoria_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end 
                        else begin
                            escrita_dados_next = 1'b1;
                            proximo_estado = NEXT_PIXEL;
                        end
                    end

                    //=========================================================
                    // Zoom Out - Vizinho Mais Próximo
                    //=========================================================
                    VIZINHO_MAIS_PROXIMO_OUT: begin
                        coluna = (endereco_memoria % 17'd320);
                        linha = (endereco_memoria / 17'd320);
                        
                        case (salvar_pixels)
                            ENDERECO_1: begin
                                if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
                                    endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
                                    salvar_pixels_next = ENDERECO_3;
                                    proximo_estado = WRITE;
                                    pixel_para_salvar_next = pixels_processados[31:24];
                                end 
                                else begin
                                    if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                        (linha < 9'd60) || (linha >= 9'd180)) begin
                                        escrita_dados_next = 1'b1;
                                        endereco_escrita_next = endereco_memoria;
                                        pixel_para_salvar_next = 8'd0;
                                    end 
                                    else begin
                                        escrita_dados_next = 1'b0;
                                        endereco_escrita_next = endereco_memoria;
                                        pixel_para_salvar_next = 8'd0;
                                    end
                                    endereco_memoria_next = endereco_memoria + 1'b1;
                                    proximo_estado = NEXT_PIXEL;
                                end
                            end
                            
                            ENDERECO_3: begin
                                endereco_escrita_next = endereco_memoria;
                                if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                    (linha < 9'd60) || (linha >= 9'd180)) begin
                                    escrita_dados_next = 1'b1;
                                    pixel_para_salvar_next = 8'd0;
                                end 
                                else begin
                                    escrita_dados_next = 1'b0;
                                    pixel_para_salvar_next = 8'd0;
                                end
                                proximo_estado = NEXT_PIXEL;
                                endereco_memoria_next = endereco_memoria + 1'b1;
                            end
                            
                            default: begin
                                proximo_estado = END_INSTRUCTION;
                            end
                        endcase

                        if (endereco_memoria_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end
                    end

                    //=========================================================
                    // Zoom In - Replicação/Vizinho Mais Próximo (default)
                    //=========================================================
                    default: begin
                        // Calcula posição relativa ao centro
                        coluna = (endereco_memoria % 17'd320) - 17'd160;
                        linha = (endereco_memoria / 17'd320) - 17'd120;
                        
                        case (salvar_pixels)
                            ENDERECO_1: begin
                                endereco_escrita_next = (linha * 2) * 9'd320 + (coluna * 2);
                                pixel_para_salvar_next = pixels_processados[7:0];
                                salvar_pixels_next = ENDERECO_2;
                                proximo_estado = WRITE;
                            end
                            ENDERECO_2: begin
                                endereco_escrita_next = (linha * 2) * 9'd320 + (coluna * 2 + 1);
                                pixel_para_salvar_next = pixels_processados[15:8];
                                salvar_pixels_next = ENDERECO_3;
                                proximo_estado = WRITE;
                            end
                            ENDERECO_3: begin
                                endereco_escrita_next = (linha * 2 + 1) * 9'd320 + (coluna * 2);
                                pixel_para_salvar_next = pixels_processados[23:16];
                                salvar_pixels_next = ENDERECO_4;
                                proximo_estado = WRITE;
                            end
                            ENDERECO_4: begin
                                endereco_escrita_next = (linha * 2 + 1) * 9'd320 + (coluna * 2 + 1);
                                pixel_para_salvar_next = pixels_processados[31:24];
                                escrita_dados_next = 1'b1;
                                salvar_pixels_next = ENDERECO_1;
                                endereco_memoria_next = endereco_memoria + 1'b1;
                            end
                            default: begin
                                proximo_estado = IDLE;
                            end
                        endcase
                        
                        if (endereco_escrita_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end 
                        else begin
                            if (salvar_pixels == ENDERECO_4) begin
                                proximo_estado = NEXT_PIXEL;
                            end 
                            else begin 
                                proximo_estado = WRITE;
                            end
                        end
                    end
                endcase
            end

            //=================================================================
            // NEXT_PIXEL: Avança para próximo pixel
            //=================================================================
            NEXT_PIXEL: begin
                escrita_dados_next = 1'b0;
                
                if (endereco_memoria_next >= 17'd76800) begin
                    proximo_estado = END_INSTRUCTION;
                end 
                else begin
                    proximo_estado = READ_PIXEL;
                end
            end

            //=================================================================
            // END_INSTRUCTION: Finaliza processamento
            //=================================================================
            END_INSTRUCTION: begin
                escrita_dados_next = 1'b0;
                dados_prontos_next = 1'b1;
                proximo_estado = IDLE;
            end

            //=================================================================
            // Default: Retorna ao IDLE
            //=================================================================
            default: begin
                escrita_dados_next = 1'b0;
                proximo_estado = IDLE;
            end
        endcase
    end

    //=========================================================================
    // Instanciação da ALU (Unidade Lógico-Aritmética)
    // Processa pixels conforme o algoritmo selecionado
    //=========================================================================
    alu alu_inst(
        .pixel_1(pixel_m_1),
        .pixel_2(pixel_m_2),
        .pixel_3(pixel_m_3),
        .pixel_4(pixel_m_4),
        .media_pixel(pixel_media_p),
        .opcode(opcode),
        .clock(clock),
        .pixel(pixel_para_processar_reg), 
        .pixel_processado(pixels_processados)
    );

    //=========================================================================
    // PLL para Geração de Clock 75MHz (VGA)
    //=========================================================================
    clock_75mhz clock_75(
        .refclk(clock_50Mhz),   
        .rst(1'b0),      
        .outclk_0(clock_75_mhz), 
        .locked()    
    );

    //=========================================================================
    // Sinal de Escrita na Memória Principal
    //=========================================================================
    wire escrever_memoria_principal = (opcode_instrucao == 3'b111) && escrita_dados_next;

    //=========================================================================
    // Gerenciador de Memória RAM
    //=========================================================================
    gerenciar_memoria_ram gm_ram(
        .clock_a(clock),
        .clock_b(clock),
        .endereco_escrita(endereco_escrita_next),
        .endereco_leitura(endereco_memoria),
        .dado_escrita(pixel_para_salvar_next),
        .habilita_escrita(escrever_memoria_principal),
        .dado_leitura(pixel_para_processar)
    );

    //=========================================================================
    // Controlador VGA
    //=========================================================================
    controle_vga controle_saida(
        .clock(clock),
        .endereco_escrita(endereco_escrita_next),
        .byte_para_escrita(pixel_para_salvar_next),
        .clock_b(clock_50Mhz),
        .permicao_escrita(escrita_dados_next),
        .hsync(hsync),
        .vsync(vsync),    
        .red(red),     
        .green(green),   
        .blue(blue),    
        .sync(sync),          
        .clk(clk),           
        .blank(blank),
        .dados_porta_b()
    );

endmodule