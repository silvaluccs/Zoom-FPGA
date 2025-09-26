	module unidade_de_controle(
		input clock_50Mhz,
		input botao_zoom_in,
		input botao_zoom_out,
		input seletor_algoritmo,
		output wire hsync,
		output wire vsync,    
		output [7:0] red,     
		output [7:0] green,   
		output [7:0] blue,    
		output sync,          
		output clk,           
		output blank
	);

		wire clock;
		 
		wire clock_75_mhz;

		 
		 divisor_clock_por_2 divisor_clock_50MHZ(
			.clock_entrada(clock_50Mhz),
			.clock_saida(clock)
		 );


		 reg [2:0] estado_atual, proximo_estado;
		 reg [16:0] endereco_memoria, endereco_memoria_next;
		 reg [16:0] endereco_escrita, endereco_escrita_next;
		 reg escrita_dados, escrita_dados_next;
		 reg botao_zoom_in_reg, botao_zoom_out_reg, seletor_algoritmo_reg;
		 reg [7:0] pixel_para_processar_reg;
		 reg [31:0] pixels_processados_reg;
		 reg [7:0] pixel_para_salvar, pixel_para_salvar_next;
		 reg [1:0] salvar_pixels, salvar_pixels_next;
		 reg dados_prontos, dados_prontos_next;
		 reg [2:0] opcode, opcode_next;
		 wire [7:0] pixel_para_processar;
		 wire [31:0] pixels_processados;
		
		parameter ENDERECO_BASE = 17'd38560;
		
		parameter IDLE=0,LOAD_OP=1,READ_PIXEL=2, EXECUTE=3, WRITE=4, NEXT_PIXEL=5, END_INSTRUCTION=6;
		
		parameter ENDERECO_1=0,ENDERECO_2=1, ENDERECO_3=2,ENDERECO_4=3;
		
		always @(posedge clock) begin
        estado_atual <= proximo_estado;
		  
		  
		  if (estado_atual == IDLE) begin
			  botao_zoom_in_reg <= ~botao_zoom_in;
			  botao_zoom_out_reg <= ~botao_zoom_out;
			  seletor_algoritmo_reg <= seletor_algoritmo;
		  end else begin
			  botao_zoom_in_reg <= botao_zoom_in_reg;
			  botao_zoom_out_reg <= botao_zoom_out_reg;
			  seletor_algoritmo_reg <= seletor_algoritmo_reg;
		  end
        
        // Registrar próximos valores
        endereco_memoria <= endereco_memoria_next;
        endereco_escrita <= endereco_escrita_next;
        escrita_dados <= escrita_dados_next;
        pixel_para_salvar <= pixel_para_salvar_next;
        salvar_pixels <= salvar_pixels_next;
        dados_prontos <= dados_prontos_next;
        opcode <= opcode_next;
        pixels_processados_reg <= pixels_processados; // Registrar saída da ALU
        pixel_para_processar_reg <= pixel_para_processar; // Registrar leitura RAM
    end

    // BLOCO COMBINACIONAL - apenas atribuições com =
    always @(*) begin
        // Valores padrão (evitar latches)
        proximo_estado = estado_atual;
        endereco_memoria_next = endereco_memoria;
        endereco_escrita_next = endereco_escrita;
        escrita_dados_next = escrita_dados;
        pixel_para_salvar_next = pixel_para_salvar;
        salvar_pixels_next = salvar_pixels;
        dados_prontos_next = dados_prontos;
        opcode_next = opcode;

        case (estado_atual)
            IDLE: begin
                escrita_dados_next = 1'b0;
                endereco_memoria_next = ENDERECO_BASE;
                dados_prontos_next = 1'b0;
                
                if (botao_zoom_in_reg || botao_zoom_out_reg) begin
                    proximo_estado = LOAD_OP;
                end else begin
                    proximo_estado = IDLE;
                end
            end
            
            LOAD_OP: begin
                opcode_next = {botao_zoom_in_reg, botao_zoom_out_reg, seletor_algoritmo_reg};
                proximo_estado = READ_PIXEL;
            end
            
            READ_PIXEL: begin
                // pixel_para_processar_reg é registrado no bloco sequencial
                proximo_estado = EXECUTE;
            end
            
            EXECUTE: begin
                salvar_pixels_next = ENDERECO_1;
                proximo_estado = WRITE;
            end
            
            WRITE: begin
                escrita_dados_next = 1'b1;
                
                case (salvar_pixels)
                    ENDERECO_1: begin
                        endereco_escrita_next = endereco_memoria - ENDERECO_BASE;
                        pixel_para_salvar_next = pixels_processados[7:0]; // Usar saída direta da ALU
                        salvar_pixels_next = ENDERECO_2;
                        proximo_estado = WRITE;
                    end
                    ENDERECO_2: begin
                        endereco_escrita_next = (endereco_memoria + 1'b1) - ENDERECO_BASE;
                        pixel_para_salvar_next = pixels_processados[15:8];
                        salvar_pixels_next = ENDERECO_3;
                        proximo_estado = WRITE;
                    end
                    ENDERECO_3: begin
                        endereco_escrita_next = (endereco_memoria + 9'd320) - ENDERECO_BASE;
                        pixel_para_salvar_next = pixels_processados[23:16];
                        salvar_pixels_next = ENDERECO_4;
                        proximo_estado = WRITE;
                    end
                    ENDERECO_4: begin
                        endereco_escrita_next = (endereco_memoria + 9'd321) - ENDERECO_BASE;
                        pixel_para_salvar_next = pixels_processados[31:24];
                        escrita_dados_next = 1'b0;
                        salvar_pixels_next = ENDERECO_1;
                        
                        if (endereco_escrita_next >= 17'd76800) begin
                            proximo_estado = END_INSTRUCTION;
                        end else begin
                            proximo_estado = NEXT_PIXEL;
                        end
                    end
                    default: begin
                        proximo_estado = IDLE;
                    end
                endcase
            end
            
            NEXT_PIXEL: begin
                endereco_memoria_next = endereco_memoria + 1'b1;
                
                if (endereco_memoria_next >= 17'd76800) begin
                    proximo_estado = END_INSTRUCTION;
                end else begin
                    proximo_estado = LOAD_OP;
                end
            end
            
            END_INSTRUCTION: begin
                dados_prontos_next = 1'b1;
                proximo_estado = IDLE;
            end
            
            default: begin
                proximo_estado = IDLE;
            end
        endcase
    end
		
		
		/*
		always @(posedge clock)
		 begin
					estado_atual <= proximo_estado;
		 end
		 
		 always @(estado_atual or botao_zoom_in or botao_zoom_out or seletor_algoritmo)
		  begin
				case (estado_atual)
					
					IDLE: begin
					
						if (~botao_zoom_in | ~botao_zoom_out) begin // caso um botao seja precionado
							
							botao_zoom_in_reg <= ~botao_zoom_in;
							botao_zoom_out_reg <= ~botao_zoom_out;
							seletor_algoritmo_reg <= seletor_algoritmo;
							
							proximo_estado <= LOAD_OP;
						end else begin
							proximo_estado <= IDLE;
						end
						
							escrita_dados <= 1'b0;
							endereco_memoria <= ENDERECO_BASE;
						
					end
					
					LOAD_OP: begin
						opcode <= {botao_zoom_in_reg, botao_zoom_out_reg, seletor_algoritmo_reg};
						proximo_estado <= READ_PIXEL;
					end
					
					READ_PIXEL: begin
						pixel_para_processar_reg <= pixel_para_processar;
						proximo_estado <= EXECUTE;
					end
					
					EXECUTE: begin
						salvar_pixels <= 2'd0;
					end
					
					WRITE: begin
						pixels_processados_reg <= pixels_processados;
						escrita_dados <= 1'b1;
						
						case (salvar_pixels)
						
							ENDERECO_1: begin
								endereco_escrita <= endereco_memoria - ENDERECO_BASE;
								pixel_para_salvar <= pixels_processados_reg[7:0];
								salvar_pixels <= 2'b01;
							end
							ENDERECO_2: begin
								endereco_escrita <= (endereco_memoria + 1'b1) - ENDERECO_BASE;
								pixel_para_salvar <= pixels_processados_reg[15:8];
								salvar_pixels <= 2'b10;
							end 
							ENDERECO_3: begin
								endereco_escrita <= (endereco_memoria + 9'd320) - ENDERECO_BASE;
								pixel_para_salvar <= pixels_processados_reg[23:16];
								salvar_pixels <= 2'b11;
							end 
							ENDERECO_4: begin
								endereco_escrita <= (endereco_memoria + 9'd321) - ENDERECO_BASE;
								pixel_para_salvar <= pixels_processados_reg[31:24];
								proximo_estado <= NEXT_PIXEL;
							end
							default: begin
							
								proximo_estado <= IDLE;
							end
						endcase
						
						if (endereco_escrita >= 17'd76800)
							proximo_estado <= END_INSTRUCTION;
						else
							proximo_estado <= proximo_estado;
						
					end
					NEXT_PIXEL: begin
						
						escrita_dados <= 1'b0;
						endereco_memoria <= endereco_memoria + 1'b1;
						
						if (endereco_memoria == 17'd76800) begin
							proximo_estado <= END_INSTRUCTION;
						end else begin
							proximo_estado <= LOAD_OP;
						end	
					end
					
					END_INSTRUCTION: begin
						
						dados_prontos <= 1'b1;
						proximo_estado <= IDLE;
					
					end
					
					default: begin
						
						proximo_estado <= IDLE;
					
					end
				
				endcase	  
		  end
*/

	ram_primaria ram_leitura(
		.address(endereco_memoria),
		.clock(clock),
		.data(8'd0),
		.rden(1'b1),
		.wren(1'b0),
		.q(pixel_para_processar));
		  

	alu alu (
		.opcode(opcode),
		.clock(clock),
		.pixel(pixel_para_processar_reg), // poderia aumentar
		.pixel_processado(pixels_processados)
	);


	clock_75mhz clock_75(
			.refclk(clock_50Mhz),   
			.rst(1'b0),      //   reset.reset
			.outclk_0(clock_75_mhz), // outclk0.clk
			.locked()    //  locked.export
		);
		
		
	controle_vga controle_saida(
		 .clock(clock),
		 .endereco_escrita(endereco_escrita),
		 .byte_para_escrita(pixel_para_salvar),
		 .clock_b(clock_75_mhz),
		 .permicao_escrita(escrita_dados),
		 .hsync(hsync),
		 .vsync(vsync),    
		 .red(red),     
		 .green(green),   
		 .blue(blue),    
		 .sync(sync),          
		 .clk(clk),           
		 .blank(blank)
	);


	endmodule