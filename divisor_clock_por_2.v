module divisor_clock_por_2(
	input clock_entrada,
	output clock_saida
);
	
  // Divisor de clock por 2
	reg clock = 1'b0;
	
  // Inverte o clock a cada borda de subida do clock de entrada
	always @(posedge clock_entrada)
	begin
		clock <= ~clock;
	end
	
	assign clock_saida = clock;



endmodule
