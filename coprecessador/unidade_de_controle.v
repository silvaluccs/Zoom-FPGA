module unidade_de_controle(
					input clock_50Mhz,
					input botao_zoom_in_input,
					input botao_zoom_out_input,
					input seletor_algoritmo,
					input reset_input,
					output wire hsync,
					output wire vsync,    
					output [7:0] red,     
					output [7:0] green,   
					output [7:0] blue,    
					output sync,          
					output clk,           
					output blank
);
				
          // fio para os botões com debounce
					wire botao_zoom_in, botao_zoom_out, reset;
					
          // Instanciação do módulo de debounce para os botões
					debounce_bt debouce_zoom_in(botao_zoom_in_input,clock, botao_zoom_in);
					debounce_bt debouce_zoom_out(botao_zoom_out_input,clock, botao_zoom_out);
					debounce_bt debouce_reset(reset_input,clock, reset);

          // fios para os clocks
					wire clock;
					 
					wire clock_75_mhz;
					
					 
          // divisor de clock por 2
					 divisor_clock_por_2 divisor_clock_50MHZ(
						.clock_entrada(clock_50Mhz),
						.clock_saida(clock)
					 );


           // registradores e fios internos
					 reg [2:0] estado_atual, proximo_estado;
					 reg [16:0] endereco_memoria, endereco_memoria_next;
					 reg [16:0] endereco_escrita, endereco_escrita_next;
					 reg escrita_dados, escrita_dados_next;
					 reg botao_zoom_in_reg, botao_zoom_out_reg, seletor_algoritmo_reg;
					 reg reset_reg;
					 reg [7:0] pixel_para_processar_reg;
					 reg [7:0] pixel_para_salvar, pixel_para_salvar_next;
					 reg [2:0] salvar_pixels, salvar_pixels_next;
					 reg dados_prontos, dados_prontos_next;
					 reg [2:0] opcode, opcode_next;
					 wire [7:0] pixel_para_processar;
					 wire [31:0] pixels_processados;

					 reg [8:0] linha;
					 reg [8:0] coluna;
					 reg [16:0] endereco_base_para_escrita;
					 reg [16:0] endereco_base_para_escrita_next;
					 
					 
           // registradores para armazenar os 4 pixels para a média
					 reg [7:0] pixel_m_1;
					 reg [7:0] pixel_m_2;
					 reg [7:0] pixel_m_3;
					 reg [7:0] pixel_m_4;
					 wire [7:0] pixel_media_p;
					 reg [7:0] pixel_m_1_next;
					 reg [7:0] pixel_m_2_next;
					 reg [7:0] pixel_m_3_next;
					 reg [7:0] pixel_m_4_next;
					

           // endereco base para os algoritmos de zoom in
					parameter ENDERECO_BASE = 17'd38560; // i=120 j=160
					
          // definição dos estados
					parameter IDLE=0,LOAD_OP=1,READ_PIXEL=2, EXECUTE=3, WRITE=4, NEXT_PIXEL=5, END_INSTRUCTION=6, WAIT_READ=7;
					
          // definição dos endereços para salvar os pixels
					parameter ENDERECO_1=0,ENDERECO_2=1, ENDERECO_3=2,ENDERECO_4=3, ENDERECO_5=4;
					
          // definição dos opcodes
					localparam REPLICACAO_PIXEL=3'b100;
					localparam VIZINHO_MAIS_PROXIMO=3'b101;
					localparam MEDIA_DE_BLOCOS=3'b010;
					localparam VIZINHO_MAIS_PROXIMO_OUT=3'b011;
					localparam RESET_IMAGEM=3'b111;

				// No início do módulo, ajuste as declarações:
				reg [8:0] linha_aux;
				reg [8:0] coluna_aux;

				// Dentro do always @(posedge clock), adicione reset das variáveis auxiliares:
				always @(posedge clock) begin
					 estado_atual <= proximo_estado;
					 
					 if (estado_atual == IDLE) begin
						  reset_reg <= reset;
						  botao_zoom_in_reg <= botao_zoom_in;
						  botao_zoom_out_reg <= botao_zoom_out;
						  seletor_algoritmo_reg <= seletor_algoritmo;
						  linha_aux <= 9'd60;  // Reset para início da região central
						  coluna_aux <= 9'd80; // Reset para início da região central
					 end else begin
						  botao_zoom_in_reg <= botao_zoom_in_reg;
						  botao_zoom_out_reg <= botao_zoom_out_reg;
						  seletor_algoritmo_reg <= seletor_algoritmo_reg;
						  
						  // Atualizar linha_aux e coluna_aux durante processamento
						  if (estado_atual == WRITE && opcode == VIZINHO_MAIS_PROXIMO_OUT && salvar_pixels == ENDERECO_1) begin
								if ((linha % 2 == 0) && (coluna % 2 != 0)) begin
									 if (coluna_aux == 9'd239) begin
										  linha_aux <= linha_aux + 1'b1;
										  coluna_aux <= 9'd80;
										  
									 end else begin
										  coluna_aux <= coluna_aux + 1'b1;
									 end
								end
						  end
					 
					 
						 if (estado_atual == WRITE && opcode == MEDIA_DE_BLOCOS && salvar_pixels == ENDERECO_1) begin
									if ((linha % 2 == 0) && (coluna % 2 != 0)) begin
										 if (coluna_aux == 9'd239) begin
											  linha_aux <= linha_aux + 1'b1;
											  coluna_aux <= 9'd80;
											  
										 end else begin
											  coluna_aux <= coluna_aux + 1'b1;
										 end
									end
							  end
						 end
					 
					 // Restante do código...
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
           endereco_base_para_escrita_next = endereco_base_para_escrita;
           
           pixel_m_1_next = pixel_m_1;
           pixel_m_2_next = pixel_m_2;
           pixel_m_3_next = pixel_m_3;
           pixel_m_4_next = pixel_m_4;
           case (estado_atual)
         IDLE: begin
              escrita_dados_next = 1'b0;
              endereco_memoria_next = ENDERECO_BASE;
              dados_prontos_next = 1'b0;
             
              if (botao_zoom_in_reg || botao_zoom_out_reg || reset_reg) begin
                   proximo_estado = LOAD_OP;
              end else begin
                   proximo_estado = IDLE;
              end
         end
         LOAD_OP: begin
             if (reset_reg) begin
                 opcode_next = RESET_IMAGEM;
             end else if (botao_zoom_in_reg) begin
                 // Se o seletor for 1, VIZINHO_MAIS_PROXIMO, senão REPLICACAO_PIXEL
					  
                 // caso o algoritmo atual seja de zoom out, ao pressionar zoom in, reseta a imagem
						if (opcode_next == VIZINHO_MAIS_PROXIMO_OUT || opcode_next == MEDIA_DE_BLOCOS) begin
							opcode_next = RESET_IMAGEM;
						end else begin
							opcode_next = seletor_algoritmo_reg ? VIZINHO_MAIS_PROXIMO : REPLICACAO_PIXEL;
						end
                  
					  endereco_memoria_next = ENDERECO_BASE;

             end else if (botao_zoom_out_reg) begin
				 
                 // caso o algoritmo atual seja de zoom in, ao pressionar zoom out, reseta a imagem
					if (opcode_next == VIZINHO_MAIS_PROXIMO || opcode_next == REPLICACAO_PIXEL) begin
							opcode_next = RESET_IMAGEM;
						end else begin
							opcode_next = seletor_algoritmo_reg ? VIZINHO_MAIS_PROXIMO_OUT : MEDIA_DE_BLOCOS;
						end
                 
             end

             proximo_estado = READ_PIXEL;
             
             // Lógica para definir o endereço inicial de leitura
             if (opcode_next == VIZINHO_MAIS_PROXIMO_OUT || opcode_next == MEDIA_DE_BLOCOS || opcode_next == RESET_IMAGEM) begin
                    endereco_memoria_next = 17'd0;
             end else begin
                    endereco_memoria_next = opcode_next == REPLICACAO_PIXEL ? ENDERECO_BASE : (((endereco_memoria / 17'd320) - 17'd120) / 17'd2) * 17'd320 + (((endereco_memoria % 17'd320) - 17'd160) / 17'd2);;
             end
         end
							
							READ_PIXEL: begin
						
							if (opcode_next == MEDIA_DE_BLOCOS) begin
							
								proximo_estado = WAIT_READ;
								endereco_base_para_escrita_next = endereco_memoria_next;
								salvar_pixels_next = ENDERECO_1;
							
							end else begin
							
							proximo_estado = EXECUTE;
							
							end
							end
							
							WAIT_READ: begin // esperando um ciclo para a leitura
							
								 case (salvar_pixels) 
								 
									ENDERECO_1: begin
										endereco_memoria_next = endereco_base_para_escrita_next;
										salvar_pixels_next = ENDERECO_2;
									end 
									ENDERECO_2: begin
										pixel_m_1_next = pixel_para_processar;
										endereco_memoria_next = endereco_base_para_escrita_next  + 17'd1;
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
							
							EXECUTE: begin
								 salvar_pixels_next = ENDERECO_1;
								 proximo_estado = WRITE;
								 
							end
							
							WRITE: begin
								 escrita_dados_next = 1'b1;
								 
								  
								 case (opcode_next)
								 
								  MEDIA_DE_BLOCOS: begin
    
									 coluna = (endereco_memoria % 17'd320);
									 linha = (endereco_memoria / 17'd320);
									 
									 case (salvar_pixels)
										  
										  ENDERECO_1: begin
										  
												// Verifica se é linha PAR e coluna ÍMPAR
												if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
													 // Escreve no centro da imagem
													 endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
													 salvar_pixels_next = ENDERECO_3;
													 proximo_estado = WRITE;
													 pixel_para_salvar_next = pixel_media_p;
													 
												end else begin
													 // Preenche bordas com preto ou pula pixels que não atendem critério
													 // Bordas: coluna < 80 || coluna >= 240 || linha < 60 || linha >= 180
													 if ((coluna < 9'd80) || (coluna >= 9'd240) || (linha < 9'd60) || (linha >= 9'd180)) begin
														  escrita_dados_next = 1'b1;
														  endereco_escrita_next = endereco_memoria;
														  pixel_para_salvar_next = 8'd0; // Preto
													 end else begin
														  escrita_dados_next = 1'b0; // Não escreve no centro se não atende critério
														  endereco_escrita_next = endereco_memoria;
														  pixel_para_salvar_next = 8'd0;
													 end
													 
													 endereco_memoria_next = endereco_memoria + 1'b1;
													 proximo_estado = NEXT_PIXEL;
												end
												
										  end
										  
										  ENDERECO_3: begin
												// Escreve pixel atual (avança para próximo)
												endereco_escrita_next = endereco_memoria;
												
												// Verifica se está nas bordas para escrever preto
												if ((coluna < 9'd80) || (coluna >= 9'd240) || (linha < 9'd60) || (linha >= 9'd180)) begin
													 escrita_dados_next = 1'b1;
													 pixel_para_salvar_next = 8'd0;
												end else begin
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

								 
								 RESET_IMAGEM: begin
								 
									endereco_escrita_next = endereco_memoria_next;
									endereco_memoria_next = endereco_memoria + 1'b1;
									pixel_para_salvar_next = pixels_processados[7:0];
									escrita_dados_next = 1'b1;
					
										if (endereco_memoria_next >= 17'd76800) begin
											escrita_dados_next = 1'b0;
											proximo_estado = END_INSTRUCTION;
										end else begin
											escrita_dados_next = 1'b1;
											proximo_estado = NEXT_PIXEL;
										end
								 
								 end
								 
							
									 VIZINHO_MAIS_PROXIMO_OUT: begin
    
									 coluna = (endereco_memoria % 17'd320);
									 linha = (endereco_memoria / 17'd320);
									 
									 case (salvar_pixels)
										  
										  ENDERECO_1: begin
										  
												// Verifica se é linha PAR e coluna ÍMPAR
												if ((linha[0] == 1'b0) && (coluna[0] == 1'b1)) begin
													 // Escreve no centro da imagem
													 endereco_escrita_next = linha_aux * 9'd320 + coluna_aux;
													 salvar_pixels_next = ENDERECO_3;
													 proximo_estado = WRITE;
													 pixel_para_salvar_next = pixels_processados[31:24];
													 
												end else begin
													 // Preenche bordas com preto ou pula pixels que não atendem critério
													 // Bordas: coluna < 80 || coluna >= 240 || linha < 60 || linha >= 180
													 if ((coluna < 9'd80) || (coluna >= 9'd240) || (linha < 9'd60) || (linha >= 9'd180)) begin
														  escrita_dados_next = 1'b1;
														  endereco_escrita_next = endereco_memoria;
														  pixel_para_salvar_next = 8'd0; // Preto
													 end else begin
														  escrita_dados_next = 1'b0; // Não escreve no centro se não atende critério
														  endereco_escrita_next = endereco_memoria;
														  pixel_para_salvar_next = 8'd0;
													 end
													 
													 endereco_memoria_next = endereco_memoria + 1'b1;
													 proximo_estado = NEXT_PIXEL;
												end
												
										  end
										  
										  ENDERECO_3: begin
												// Escreve pixel atual (avança para próximo)
												endereco_escrita_next = endereco_memoria;
												
												// Verifica se está nas bordas para escrever preto
												if ((coluna < 9'd80) || (coluna >= 9'd240) || (linha < 9'd60) || (linha >= 9'd180)) begin
													 escrita_dados_next = 1'b1;
													 pixel_para_salvar_next = 8'd0;
												end else begin
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
										
									 default: begin
										 
										 coluna = (endereco_memoria % 17'd320) - 17'd160;
										 linha = (endereco_memoria / 17'd320) - 17'd120;					
										 
										 
										 case (salvar_pixels)
											  ENDERECO_1: begin
													endereco_escrita_next = (linha * 2) * 9'd320 + (coluna * 2);
													pixel_para_salvar_next = pixels_processados[7:0]; // Usar saída direta da ALU
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
													endereco_escrita_next =	(linha * 2 + 1) * 9'd320 + (coluna * 2 + 1);
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
										 end else begin
									  
											  if (salvar_pixels == ENDERECO_4) begin
													proximo_estado = NEXT_PIXEL;
											  end else begin 
													proximo_estado = WRITE;
											  end
										 end
									end
								
								endcase
								 
								 
							end
							
							NEXT_PIXEL: begin
								 escrita_dados_next = 1'b0;

								 
								 if (endereco_memoria_next >= 17'd76800) begin
									  proximo_estado = END_INSTRUCTION;
								 end else begin
									  proximo_estado = READ_PIXEL;
								 end
							end
							
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
				
				ram_primaria ram_leitura(
					.address(endereco_memoria),
					.clock(clock),
					.data(8'd0),
					.rden(1'b1),
					.wren(1'b0),
					.q(pixel_para_processar));
					  

				alu alu (
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

			
				clock_75mhz clock_75(
						.refclk(clock_50Mhz),   
						.rst(1'b0),      
						.outclk_0(clock_75_mhz), 
						.locked()    
					);
					
					
				controle_vga controle_saida(
					 .clock(clock),
					 .endereco_escrita(endereco_escrita_next),
					 .byte_para_escrita(pixel_para_salvar_next),
					 .clock_b(clock_75_mhz),
					 .permicao_escrita(escrita_dados_next),
					 .hsync(hsync),
					 .vsync(vsync),    
					 .red(red),     
					 .green(green),   
					 .blue(blue),    
					 .sync(sync),          
					 .clk(clk),           
					 .blank(blank),
					 .dados_porta_b(dados_porta_b)
				);
				

				endmodule