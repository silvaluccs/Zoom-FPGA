	module decodificador(
		input sinal_escrita,
		input [31:0] instrucao,
		output [2:0] opcode_out,
		output reg escrita,
		output [7:0] pixel_dados,
		output [16:0] endereco_escrita,
		output wire seletor_memoria,
      output wire [8:0]  x_base,
      output  wire [7:0] y_base,
		output wire controle_imagem
		);
		
		reg [31:0] instrucao_atual;
		
		reg [2:0] opcode;
		
		assign controle_imagem = instrucao_atual[0];
		assign seletor_memoria = instrucao_atual[11];
		// para copiar imagem
		reg [7:0] pixel;
		reg [16:0] endereco_para_escrita;
		reg fim_dados, inicio_dados;
		
		wire sinal_nova_instrucao;
		wire zoom_in_s, zoom_out_s;
		
		localparam COPIAR_IMAGEM=3'b111, LOAD=3'b001, SWITCH_IMAGEM=3'b010, VIZINHO_MAIS_PROXIMO=3'b011, REPLICACAO_PIXEL=3'b100, DECIMACAO=3'b101, MEDIA_DE_BLOCOS=3'b110;


		always @(posedge sinal_escrita) begin
			instrucao_atual <= instrucao;
		end
		
			always @(*) begin
				opcode = instrucao_atual[31:29];
				
				case (opcode) 
					COPIAR_IMAGEM: begin
						escrita = 1'b1;
						endereco_para_escrita = instrucao_atual[28:12];
						pixel = instrucao_atual[11:4];
						
					end
					LOAD: begin
						escrita = 1'b0;
						endereco_para_escrita = instrucao_atual[28:12];
						pixel = 8'd0;
						
					end
						default: begin
							escrita = 1'b0;
							pixel = 8'd0;
							endereco_para_escrita = 17'd0;
						end
			
			endcase
			
			
		end
		
		assign endereco_escrita = endereco_para_escrita;
		assign pixel_dados = pixel;
		assign opcode_out = opcode;

      assign x_base = instrucao_atual[28:20];
      assign y_base = instrucao_atual[19:12];


	endmodule
