module alu(
	input [2:0] opcode,
	input clock,
	input [7:0] pixel, // poderia aumentar
	output [31:0] pixel_processado
);

	reg pixel_processado_reg;
	
	localparam REPLICACAO_PIXEL=3'b100;
	localparam VIZINHO_MAIS_PROXIMO=3'b101;
	localparam MEDIA_DE_BLOCOS=3'b010;
	localparam VIZINHO_MAIS_PROXIMO_OUT=3'b011;

	always @(clock)
	begin
	
		pixel_processado_reg <= {pixel, pixel, pixel, pixel};
	
	/*
		quando criar todos os algoritmos vai fazer a selecao aqui
		case (opcode)
		
			REPLICACAO_PIXEL: begin
			
			end 
			
			VIZINHO_MAIS_PROXIMO: begin
			
			end 
			
			MEDIA_DE_BLOCOS: begin
			
			end 
			
			VIZINHO_MAIS_PROXIMO_OUT: begin
			
			end 
			
			default: begin
			
			end

		
		endcase
	
	*/
	
	end
	
	assign pixel_processado = pixel_processado_reg;
	
endmodule