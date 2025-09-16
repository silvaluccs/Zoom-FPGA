module replicacao_pixel(
	input clock,
	input reg memoria_a,
	input executar,
);
	reg executar_reg;
	reg [8:0] i;
	reg [7:0] j;
	
	reg [8:0] i_temp;
	reg [7:0] j_temp;
	
	reg [16:0] endereco_leitura;
	reg [16:0] endereco_escrita;
	reg [7:0] pixel_entrada;
	reg [7:0] pixel_saida_leitura;
	reg [7:0] pixel_saida_escrita;

	
	wire leitura_memoria_a;
	wire escrita_memoria_b;
	
	reg [7:0] pixel_atual;
	wire [1:0] estado;

	assign leitura_memoria_a = executar && memoria_a;
	assign escrita_memoria_a = executar && ~memoria_a;

	ram_processamento memoria_a(
		.address(leitura_memoria_a ? endereco_leitura : endereco_escrita),
		.clock(clock),
		.data(pixel_saida_leitura),
		.rden(leitura_memoria_a),
		.wren(escrita_memoria_a),
		.q(leitura_memoria_a ? pixel_saida_leitura : pixel_saida_escrita));
	
	wire leitura_memoria_b;
	wire escrita_memoria_b;
	
	assign leitura_memoria_b = escrita_memoria_a;
	assign escrita_memoria_b = leitura_memoria_a;
	
	ram_img_processada memoria_b(
		.address(leitura_memoria_b ? endereco_leitura : endereco_escrita),
		.clock(clock),
		.data(pixel_saida_leitura),
		.rden(leitura_memoria_b),
		.wren(escrita_memoria_b),
		.q(leitura_memoria_b ? pixel_saida_leitura : pixel_saida_escrita));
	
	always @(posedge executar) begin
		executar_reg <= 1'b1;
	end
	
	
	always @(*) begin
	
		if (executar_reg && i > 319 && j > 239) begin
			executar_reg <= 1'b0;
			estado <= 3'000;
			i <= 0;
			j <= 0;
			memoria_a <= ~memoria_a;
		end
	
		if (executar_reg) begin
		
			if (estado == 3'b000) begin
			
				pixel_atual <= pixel_saida_leitura;
				
				i_temp <= i * 2;
				j_temp <= j * 2;
				estado <= 3'b001;
			end else if (estado == 3'b001) begin
				i_temp <= i * 2;
				j_temp <= (j * 2) + 1;
				estado <= 3'b010;
			end else if (estado == 3'b010) begin
			
				i_temp <= (i * 2) + 1;
				j_temp <= j * 2;
				estado <= 3'b011;
			end else begin
				i_temp <= (i * 2) + 1;
				j_temp <= (j * 2) + 1;
				estado <= 3'b000;
				i <= i + 1;
				j <= j + 1;
			end
			
			endereco_escrita <= i * 240 + j;
		
		end
	end
		
	
endmodule