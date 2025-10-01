module alu(
	input [2:0] opcode,
	input clock,
	input [7:0] pixel_1,
	input [7:0] pixel_2,
	input [7:0] pixel_3,
	input [7:0] pixel_4,
	output [7:0] media_pixel,
	input [7:0] pixel, // poderia aumentar
	output [31:0] pixel_processado
);

	reg pixel_processado_reg;
	
	localparam REPLICACAO_PIXEL=3'b100;
	localparam VIZINHO_MAIS_PROXIMO=3'b101;
	localparam MEDIA_DE_BLOCOS=3'b010;
	localparam VIZINHO_MAIS_PROXIMO_OUT=3'b011;
	
	wire [9:0] soma = pixel_1 + pixel_2 + pixel_3 + pixel_4;
	
	assign media_pixel = soma >> 2;

	/*
	always @(clock)
	begin
	
		pixel_processado_reg <= {pixel, pixel, pixel, pixel};
	
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
	
	
	
	end
	
	*/
	
	assign pixel_processado = opcode == VIZINHO_MAIS_PROXIMO_OUT ? {pixel, 8'd0, 8'd0, 8'd0} : {pixel, pixel, pixel, pixel};
	
endmodule