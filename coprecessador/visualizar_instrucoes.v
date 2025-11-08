module visualizar_instrucoes(
	input [31:0] inst,
	input clock,
	input clock_in,
	input seletor,
	output [6:0] HEX0,
	output [6:0] HEX1,
	output [6:0] HEX2,
	output [6:0] HEX3
	);
	
	reg [31:0] instrucao;
	
	wire [3:0] valor1, valor2, valor3, valor4;
		
	always @(posedge clock) begin
		instrucao <= inst;
		
	end
		
	assign	valor4 = seletor ? instrucao[31:28] : instrucao[15:12];
	assign 	valor3 = seletor ? instrucao[27:24] : instrucao[11:8];
	assign 	valor2 = seletor ? instrucao[23:20] : instrucao[7:4];
	assign 	valor1 = seletor ? instrucao[19:16] : instrucao[3:0];
	
decodificar_segmentos d1(
    .valor(valor4),    
    .clock(clock_in),          
    .saida(HEX3) 
);


decodificar_segmentos d2(
    .valor(valor3),    
    .clock(clock_in),          
    .saida(HEX2) 
);


decodificar_segmentos d3(
    .valor(valor2),    
    .clock(clock_in),          
    .saida(HEX1) 
);


decodificar_segmentos d4(
    .valor(valor1),    
    .clock(clock_in),          
    .saida(HEX0) 
);

	
	
endmodule