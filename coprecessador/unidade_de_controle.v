module unidade_de_controle(
    // CLOCK E CONTROLE
    input clock_50Mhz,                  // Clock 50MHz do sistema
    // SAÍDAS VGA
    output wire hsync, vsync,           // Sincronismos VGA
    output [7:0] red, green, blue,      // Canais RGB (8 bits cada)
    output sync, clk, blank,            // Controles VGA
    
    // INTERFACE DE INSTRUÇÕES (32 bits)
    input [31:0] instrucoes,            // Barramento de instruções
    input enable_read,                  // Sinal de nova instrução (50MHz)
    
    // SAÍDA DE PIXEL (NOVA FUNCIONALIDADE)
    output wire [7:0] pixel_saida       // Pixel lido (operação ENVIAR_PIXEL)
);

    //=========================================================================
    // SINAIS DO DECODIFICADOR
    //=========================================================================
    wire [2:0] opcode_instrucao;        // Opcode (3 bits)
    wire escrita_sinal;                 // Enable escrita (não usado)
    wire [7:0] pixel_escrever;          // Pixel para escrita direta
    wire [16:0] endereco_escrv;         // Endereço para operação direta

    
    // NOVOS SINAIS (diferença principal da versão 1)
    wire seletor_memoria;               // 0=RAM principal, 1=RAM auxiliar
    wire [8:0] x_base;                  // Coordenada X do ROI (0-319)
    wire [8:0] y_base;                  // Coordenada Y do ROI (0-239)
    wire controle_imagem;               // Liga/desliga display VGA

    //=========================================================================
    // SINCRONIZADOR 50MHz -> 25MHz
    // Gera pulso de 1 ciclo quando nova instrução está disponível
    //=========================================================================
    reg sync1 = 1'b0, sync2 = 1'b0;
    
    always @(posedge clock) begin
        sync1 <= enable_read;
        sync2 <= sync1;
    end
    
    wire new_data_pulse_25 = sync1 & ~sync2;  // Detector de borda

    //=========================================================================
    // DECODIFICADOR DE INSTRUÇÕES
    //=========================================================================
    decodificador deco(
        .clock(new_data_pulse_25),
        .instrucoes(instrucoes),
        .opcode(opcode_instrucao),
        .escrita(escrita_sinal),
        .pixel(pixel_escrever),
        .endereco(endereco_escrv),
        .seletor_memoria(seletor_memoria),      // NOVO
        .x_base(x_base),                        // NOVO
        .y_base(y_base),                        // NOVO
        .controle_imagem(controle_imagem)       // NOVO
    );

    //=========================================================================
    // CLOCKS
    //=========================================================================
    wire clock;                         // 25MHz (processamento)
    wire clock_75_mhz;                  // 75MHz (VGA - não usado)
    
    divisor_clock_por_2 divisor_clock_50MHZ(
        .clock_entrada(clock_50Mhz),
        .clock_saida(clock)
    );

    //=========================================================================
    // ESTADOS DA FSM
    //=========================================================================
    parameter IDLE=0, LOAD_OP=1, READ_PIXEL=2, EXECUTE=3;
    parameter WRITE=4, NEXT_PIXEL=5, END_INSTRUCTION=6;
    parameter WAIT_READ=7, WRITE_IMAGEM=8;
    
    // ÍNDICES PARA SALVAMENTO SEQUENCIAL
    parameter ENDERECO_1=0, ENDERECO_2=1, ENDERECO_3=2;
    parameter ENDERECO_4=3, ENDERECO_5=4;
    
    // OPCODES
    localparam ENVIAR_PIXEL           = 3'b001;  // NOVO - Lê e retorna pixel
    localparam MEDIA_DE_BLOCOS        = 3'b010;  // Zoom out: média 2x2
    localparam VIZINHO_MAIS_PROXIMO_OUT = 3'b011; // Zoom out: nearest neighbor
    localparam REPLICACAO_PIXEL       = 3'b100;  // Zoom in: replicação
    localparam VIZINHO_MAIS_PROXIMO   = 3'b101;  // Zoom in: nearest neighbor
    localparam RESET_IMAGEM           = 3'b111;  // Reset para original

    parameter ENDERECO_BASE = 17'd0;

    //=========================================================================
    // REGISTRADORES PRINCIPAIS
    //=========================================================================
    reg [3:0] estado_atual, proximo_estado;
    reg [16:0] endereco_memoria, endereco_memoria_next;
    reg [16:0] endereco_escrita, endereco_escrita_next;
    reg escrita_dados, escrita_dados_next;
    reg [7:0] pixel_para_salvar, pixel_para_salvar_next;
    reg [2:0] salvar_pixels, salvar_pixels_next;
    reg dados_prontos, dados_prontos_next;
    reg [2:0] opcode, opcode_next;
    
    reg [7:0] pixel_para_processar_reg;
    wire [7:0] pixel_para_processar;    // Lido da RAM
    wire [31:0] pixels_processados;     // 4 pixels da ALU

    //=========================================================================
    // REGISTRADORES PARA CÁLCULO DE POSIÇÃO
    //=========================================================================
    reg [8:0] linha, coluna;            // Posição atual na imagem
    reg [16:0] endereco_base_para_escrita, endereco_base_para_escrita_next;
    
    // ZOOM OUT: Contadores para região central (80-239, 60-179)
    reg [8:0] linha_aux, coluna_aux;

    //=========================================================================
    // NOVOS REGISTRADORES PARA ZOOM IN COM ROI DINÂMICO
    //=========================================================================
    reg [16:0] contador_pixel, contador_pixel_next;  // 0-19199 (160x120)
    reg [8:0] linha_entrada, coluna_entrada;         // Posição no bloco
    reg [16:0] endereco_base_saida;                  // Base escrita 2x2

    //=========================================================================
    // MÉDIA DE BLOCOS: 4 pixels do bloco 2x2
    //=========================================================================
    reg [7:0] pixel_m_1, pixel_m_1_next;    // Superior esquerdo
    reg [7:0] pixel_m_2, pixel_m_2_next;    // Superior direito
    reg [7:0] pixel_m_3, pixel_m_3_next;    // Inferior esquerdo
    reg [7:0] pixel_m_4, pixel_m_4_next;    // Inferior direito
    wire [7:0] pixel_media_p;               // Média calculada

    //=========================================================================
    // CONTROLE DE EXIBIÇÃO E SAÍDA
    //=========================================================================
    reg switch_imagem, switch_imagem_next;      // NOVO - Liga/desliga VGA
    reg [7:0] pixel_saida_reg, pixel_saida_next; // NOVO - Buffer saída


    //=========================================================================
    // BLOCO SEQUENCIAL
    //=========================================================================
    always @(posedge clock) begin
        estado_atual <= proximo_estado;
        
        // Reset dos contadores auxiliares
        if (estado_atual == IDLE || estado_atual == WRITE_IMAGEM) begin
            linha_aux <= 9'd60;   // Região central começa em linha 60
            coluna_aux <= 9'd80;  // Região central começa em coluna 80
        end 
        else begin
            // Atualiza contadores durante ZOOM OUT
            if (estado_atual == WRITE && 
                (opcode == VIZINHO_MAIS_PROXIMO_OUT || opcode == MEDIA_DE_BLOCOS) && 
                salvar_pixels == ENDERECO_1) begin
                
                // Amostragem: linhas pares, colunas ímpares
                if ((linha % 2 == 0) && (coluna % 2 != 0)) begin
                    if (coluna_aux == 9'd239) begin  // Fim da linha
                        linha_aux <= linha_aux + 1'b1;
                        coluna_aux <= 9'd80;
                    end 
                    else begin
                        coluna_aux <= coluna_aux + 1'b1;
                    end
                end
            end
        end
        
        // Atualiza todos os registradores
        endereco_memoria <= endereco_memoria_next;
        endereco_escrita <= endereco_escrita_next;
        escrita_dados <= escrita_dados_next;
        pixel_para_salvar <= pixel_para_salvar_next;
        salvar_pixels <= salvar_pixels_next;
        dados_prontos <= dados_prontos_next;
        pixel_saida_reg <= pixel_saida_next;          // NOVO
        opcode <= opcode_next;
        pixel_para_processar_reg <= pixel_para_processar;
        endereco_base_para_escrita <= endereco_base_para_escrita_next;
        pixel_m_1 <= pixel_m_1_next;
        pixel_m_2 <= pixel_m_2_next;
        pixel_m_3 <= pixel_m_3_next;
        pixel_m_4 <= pixel_m_4_next;
        contador_pixel <= contador_pixel_next;        // NOVO
        switch_imagem <= switch_imagem_next;          // NOVO
    end

    //=========================================================================
    // BLOCO COMBINACIONAL - FSM
    //=========================================================================
    always @(*) begin
        // Valores padrão
        pixel_saida_next = pixel_saida_reg;
        proximo_estado = estado_atual;
        endereco_memoria_next = endereco_memoria;
        endereco_escrita_next = endereco_escrita;
        escrita_dados_next = escrita_dados;
        pixel_para_salvar_next = pixel_para_salvar;
        salvar_pixels_next = salvar_pixels;
        dados_prontos_next = dados_prontos;
        opcode_next = opcode;
        endereco_base_para_escrita_next = endereco_base_para_escrita;
        contador_pixel_next = contador_pixel;
        switch_imagem_next = switch_imagem;
        pixel_m_1_next = pixel_m_1;
        pixel_m_2_next = pixel_m_2;
        pixel_m_3_next = pixel_m_3;
        pixel_m_4_next = pixel_m_4;
        
        case (estado_atual)
            //=================================================================
            // IDLE: Aguarda instrução
            //=================================================================
            IDLE: begin
                escrita_dados_next = 1'b0;
                endereco_memoria_next = ENDERECO_BASE;
                dados_prontos_next = 1'b0;
                contador_pixel_next = 17'd0;          // NOVO - Reset contador
                
                if (new_data_pulse_25) proximo_estado = LOAD_OP;
                else proximo_estado = IDLE;
            end
            
            //=================================================================
            // LOAD_OP: Decodifica operação
            //=================================================================
            LOAD_OP: begin
                case (opcode_instrucao) 
                    // ZOOM IN
                    3'b011, 3'b100: begin
                        if (opcode == VIZINHO_MAIS_PROXIMO_OUT || opcode == MEDIA_DE_BLOCOS) begin
                            opcode_next = RESET_IMAGEM;
                            endereco_memoria_next = 17'd0;
                        end 
                        else begin
                            opcode_next = (opcode_instrucao == 3'b011) ? 
                                          VIZINHO_MAIS_PROXIMO : REPLICACAO_PIXEL;
                            endereco_memoria_next = ENDERECO_BASE;
                            contador_pixel_next = 17'd0;  // NOVO
                        end
                        proximo_estado = READ_PIXEL;
                    end
                    
                    // ZOOM OUT
                    3'b101, 3'b110: begin
                        if (opcode == VIZINHO_MAIS_PROXIMO || opcode == REPLICACAO_PIXEL) begin
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
                    
                    // ESCRITA PIXEL
                    3'b111: begin
                        endereco_escrita_next = endereco_escrv;
                        pixel_para_salvar_next = pixel_escrever;
                        escrita_dados_next = 1'b1;
                        proximo_estado = WRITE_IMAGEM;
                    end
                    
                    // NOVO - ENVIAR_PIXEL (leitura de pixel)
                    3'b001: begin
                        opcode_next = ENVIAR_PIXEL;
                        proximo_estado = READ_PIXEL;
                    end
                    
                    // NOVO - CONTROLE DE EXIBIÇÃO
                    3'b010: begin
                        switch_imagem_next = controle_imagem;
                        proximo_estado = END_INSTRUCTION;
                    end
                    
                    default: proximo_estado = IDLE;
                endcase
            end
            
            //=================================================================
            // WRITE_IMAGEM: Finaliza escrita/configuração
            //=================================================================
            WRITE_IMAGEM: begin
                escrita_dados_next = 1'b0;
                opcode_next = 3'b000;
                proximo_estado = IDLE;
            end
            
            //=================================================================
            // READ_PIXEL: Lê pixel(s) da memória
            //=================================================================
            READ_PIXEL: begin
                escrita_dados_next = 1'b0;
                
                // NOVO - ZOOM IN com ROI dinâmico
                if (opcode_next == REPLICACAO_PIXEL || opcode_next == VIZINHO_MAIS_PROXIMO) begin
                    // Posição no bloco 160x120
                    linha_entrada = contador_pixel / 9'd160;
                    coluna_entrada = contador_pixel % 9'd160;
                    
                    // Endereço absoluto: ROI base + offset
                    endereco_memoria_next = (y_base + linha_entrada) * 17'd320 + 
                                           (x_base + coluna_entrada);
                    
                    // Endereço de escrita: bloco 2x2
                    endereco_base_saida = (linha_entrada * 2) * 17'd320 + 
                                         (coluna_entrada * 2);
                    
                    proximo_estado = EXECUTE;
                end
                // NOVO - ENVIAR_PIXEL
                else if (opcode_next == ENVIAR_PIXEL) begin
                    endereco_memoria_next = endereco_escrv;
                    endereco_escrita_next = endereco_escrv;
                    salvar_pixels_next = ENDERECO_1;
                    proximo_estado = WAIT_READ;
                end
                // MÉDIA DE BLOCOS
                else if (opcode_next == MEDIA_DE_BLOCOS) begin
                    proximo_estado = WAIT_READ;
                    endereco_base_para_escrita_next = endereco_memoria_next;
                    salvar_pixels_next = ENDERECO_1;
                end 
                else begin
                    proximo_estado = EXECUTE;
                end
            end
            
            //=================================================================
            // WAIT_READ: Aguarda leitura
            //=================================================================
            WAIT_READ: begin
                // NOVO - ENVIAR_PIXEL: espera 1 ciclo
                if (opcode_next == ENVIAR_PIXEL) begin
                    proximo_estado = EXECUTE;
                end
                // MÉDIA: lê 4 pixels sequencialmente
                else begin
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
                        default: proximo_estado = EXECUTE;
                    endcase
                end
            end
            
            //=================================================================
            // EXECUTE: Prepara escrita
            //=================================================================
            EXECUTE: begin
                salvar_pixels_next = ENDERECO_1;
                proximo_estado = WRITE;
            end
            
            //=================================================================
            // WRITE: Escreve pixel(s)
            //=================================================================
            WRITE: begin
                escrita_dados_next = 1'b1;
                
                case (opcode_next)
                    // NOVO - ENVIAR_PIXEL: retorna pixel sem escrever
                    ENVIAR_PIXEL: begin
                        escrita_dados_next = 1'b0;
                        dados_prontos_next = 1'b1;
                        
                        // Seleciona memória
                        if (seletor_memoria) 
                            pixel_saida_next = dados_porta_b;  // RAM auxiliar
                        else 
                            pixel_saida_next = pixel_para_processar; // RAM principal
                        
                        proximo_estado = END_INSTRUCTION;
                    end
                    
                    // ZOOM OUT - MÉDIA DE BLOCOS
                    MEDIA_DE_BLOCOS: begin
                        coluna = (endereco_memoria % 17'd320);
                        linha = (endereco_memoria / 17'd320);
                        
                        case (salvar_pixels)
                            ENDERECO_1: begin
                                // Linha PAR, Coluna ÍMPAR
                                if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
                                    endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
                                    salvar_pixels_next = ENDERECO_3;
                                    proximo_estado = WRITE;
                                    pixel_para_salvar_next = pixel_media_p;
                                end 
                                else begin
                                    // Bordas = preto
                                    if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                        (linha < 9'd60) || (linha >= 9'd180)) begin
                                        escrita_dados_next = 1'b1;
                                        endereco_escrita_next = endereco_memoria;
                                        pixel_para_salvar_next = 8'd0;
                                    end 
                                    else begin
                                        escrita_dados_next = 1'b0;
                                    end
                                    endereco_memoria_next = endereco_memoria + 1'b1;
                                    proximo_estado = NEXT_PIXEL;
                                end
                            end
                            
                            ENDERECO_3: begin
                                endereco_escrita_next = endereco_memoria;
                                if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                    (linha < 9'd60) || (linha >= 9'd180)) begin
                                    pixel_para_salvar_next = 8'd0;
                                end
                                proximo_estado = NEXT_PIXEL;
                                endereco_memoria_next = endereco_memoria + 1'b1;
                            end
                        endcase
                        
                        if (endereco_memoria_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end
                    end
                    
                    // RESET_IMAGEM
                    RESET_IMAGEM: begin
                        endereco_escrita_next = endereco_memoria_next;
                        endereco_memoria_next = endereco_memoria + 1'b1;
                        pixel_para_salvar_next = pixels_processados[7:0];
                        
                        if (endereco_memoria_next >= 17'd76800) begin
                            escrita_dados_next = 1'b0;
                            proximo_estado = END_INSTRUCTION;
                        end 
                        else begin
                            proximo_estado = NEXT_PIXEL;
                        end
                    end
                    
                    // ZOOM OUT - VIZINHO MAIS PRÓXIMO
                    VIZINHO_MAIS_PROXIMO_OUT: begin
                        // Lógica similar à MEDIA_DE_BLOCOS
                        // mas usa pixels_processados[31:24] ao invés de média
                        coluna = (endereco_memoria % 17'd320);
                        linha = (endereco_memoria / 17'd320);
                        
                        case (salvar_pixels)
                            ENDERECO_1: begin
                                if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
                                    endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
                                    pixel_para_salvar_next = pixels_processados[31:24];
                                    salvar_pixels_next = ENDERECO_3;
                                end 
                                else begin
                                    if ((coluna < 9'd80) || (coluna >= 9'd240) || 
                                        (linha < 9'd60) || (linha >= 9'd180)) begin
                                        pixel_para_salvar_next = 8'd0;
                                    end
                                    endereco_memoria_next = endereco_memoria + 1'b1;
                                    proximo_estado = NEXT_PIXEL;
                                end
                            end
                            
                            ENDERECO_3: begin
                                endereco_memoria_next = endereco_memoria + 1'b1;
                                proximo_estado = NEXT_PIXEL;
                            end
                        endcase
                        
                        if (endereco_memoria_next >= 17'd76800) begin
                            proximo_estado = END_INSTRUCTION;
                        end
                    end
                    
                    // ZOOM IN - REPLICAÇÃO/VIZINHO MAIS PRÓXIMO
                    default: begin
                        case (salvar_pixels)
                            ENDERECO_1: begin  // Superior esquerdo
                                endereco_escrita_next = endereco_base_saida;
                                pixel_para_salvar_next = pixels_processados[7:0];
                                salvar_pixels_next = ENDERECO_2;
                            end
                            ENDERECO_2: begin  // Superior direito
                                endereco_escrita_next = endereco_base_saida + 17'd1;
                                pixel_para_salvar_next = pixels_processados[15:8];
                                salvar_pixels_next = ENDERECO_3;
                            end
                            ENDERECO_3: begin  // Inferior esquerdo
                                endereco_escrita_next = endereco_base_saida + 17'd320;
                                pixel_para_salvar_next = pixels_processados[23:16];
                                salvar_pixels_next = ENDERECO_4;
                            end
                            ENDERECO_4: begin  // Inferior direito
                                endereco_escrita_next = endereco_base_saida + 17'd321;
                                pixel_para_salvar_next = pixels_processados[31:24];
                                contador_pixel_next = contador_pixel + 1'b1;
                                
                                // Verifica fim: 160x120 = 19200 pixels
                                if (contador_pixel_next >= 17'd19200) begin
                                    proximo_estado = END_INSTRUCTION;
                                end 
                                else begin
                                    proximo_estado = NEXT_PIXEL;
                                end
                            end
                        endcase
                    end
                endcase
            end
            
            //=================================================================
            // NEXT_PIXEL: Avança pixel
            //=================================================================
            NEXT_PIXEL: begin
                escrita_dados_next = 1'b0;
                
                case (opcode_next)
                    REPLICACAO_PIXEL, VIZINHO_MAIS_PROXIMO: begin
                        // Zoom IN continua até 19200
                        proximo_estado = READ_PIXEL;
                    end
                    
                    default: begin
                        // Zoom OUT/RESET até 76800
                        if (endereco_memoria_next >= 17'd76800) 
                            proximo_estado = END_INSTRUCTION;
                        else 
                            proximo_estado = READ_PIXEL;
                    end
                endcase
            end
            
            //=================================================================
            // END_INSTRUCTION: Finaliza
            //=================================================================
            END_INSTRUCTION: begin
                escrita_dados_next = 1'b0;
                dados_prontos_next = 1'b1;
                proximo_estado = IDLE;
            end
            
            default: begin
                escrita_dados_next = 1'b0;
                proximo_estado = IDLE;
            end
        endcase
    end

    //=========================================================================
    // ALU - Processa pixels
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
    // PLL 75MHz
    //=========================================================================
    clock_75mhz clock_75(
        .refclk(clock_50Mhz),   
        .rst(1'b0),      
        .outclk_0(clock_75_mhz), 
        .locked()    
    );

    //=========================================================================
    // GERENCIADOR DE MEMÓRIA RAM
    //=========================================================================
    wire escrever_memoria_principal = (opcode_instrucao == 3'b111) && escrita_dados_next;
    
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
    // CONTROLADOR VGA
    //=========================================================================
    wire [7:0] dados_porta_b;  // Porta B da RAM dual-port

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
				.dados_porta_b(dados_porta_b),
				.desligar_imagem(switch_imagem_next)
  );
				
    //=========================================================================
    // SAÍDA DE PIXEL
    //=========================================================================
   assign pixel_saida = pixel_saida_reg;

endmodule
