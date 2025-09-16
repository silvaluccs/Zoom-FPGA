module replicacao_pixels(
	input [16:0] endereco;
	input clock;
);


	wire [7:0] pixel;
	reg leitura;
	reg escrita;
	
	initial begin
		leitura = 1'b1;
		escrita = 1'b0;
	end
	
	
ram_nova memoria_ram (
    .address(endereco),  
    .clock(clock),
    .data(8'h00),              
    .rden(1'b1),               
    .wren(1'b0),               
    .q(pixels)                 
);


	always @(*) begin
	
		
	
	end
	
endmodule
	