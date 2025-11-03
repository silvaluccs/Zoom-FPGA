	module decodificador(
		input clock,
		input sinal_escrita,
		input [31:0] instrucao,
		output [2:0] opcode_out,
		output zoom_in,
		output zoom_out,
		output reg escrita,
		output [7:0] pixel_dados,
		output [16:0] endereco_escrita
		);
		
		reg [31:0] instrucao_atual;
		
		reg [2:0] opcode;
		
		
		// para copiar imagem
		reg [7:0] pixel;
		reg [16:0] endereco_para_escrita;
		reg fim_dados, inicio_dados;
		
		wire sinal_nova_instrucao;
		wire zoom_in_s, zoom_out_s;
		
		assign zoom_in = opcode == ZOOM_IN;
		assign zoom_out = opcode == ZOOM_OUT;
		
		localparam COPIAR_IMAGEM=3'b000, ZOOM_IN=3'b001, ZOOM_OUT=3'b010, VIZINHO_MAIS_PROXIMO=3'b011, REPLICACAO_PIXEL=3'b100, DECIMACAO=3'b101, MEDIA_DE_BLOCOS=3'b110;
		
		
		
		delayed_clock_generator gerador_de_sinal (
		 clock,
		 sinal_escrita,
		 sinal_nova_instrucao
	);


		always @(posedge sinal_nova_instrucao) begin
			instrucao_atual <= instrucao;
		end
		
			always @(*) begin
				opcode = instrucao_atual[31:29];
				
				case (opcode) 
					COPIAR_IMAGEM: begin
						escrita <= 1'b1;
						endereco_para_escrita = instrucao_atual[28:12];
						pixel = instrucao_atual[11:4];
						
					end
						default: begin
							escrita <= 1'b0;
							pixel = 8'd0;
							endereco_para_escrita = 17'd0;
						end
			
			endcase
			
			
		end
		
		assign endereco_escrita = endereco_para_escrita;
		assign pixel_dados = pixel;
		assign opcode_out = opcode;


	endmodule