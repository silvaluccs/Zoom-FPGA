module control(
    input clock_50Mhz,
    output [7:0] dados_porta_a_saida,
    output [7:0] dados_fila_saida,
	 output [16:0] contador_endereco_saida,
	 output wire [9:0] proximo_x_vga,
	 output wire [9:0] proximo_y_vga,
	 output wire hsync,
	 output wire vsync,    
    output [7:0] red,     
    output [7:0] green,   
    output [7:0] blue,    
    output sync,          
    output clk,           
    output blank,          
	 output leitura_fila_saida
	 );

    // Contador de endereço da RAM
    reg [16:0] contador_endereco = 0;

    // Dados vindos da RAM
    wire [7:0] dados_porta_a;
	 wire [7:0] dados_porta_b;

	 wire clock;
	 reg [1:0] clock_div = 0;

	always @(posedge clock_50Mhz) begin
		 clock_div <= clock_div + 1;
	end

	assign clock = clocreg [1:0] clock_div = 0;

always @(posedge clock_50Mhz) begin
    clock_div <= clock_div + 1;
end

assign clock = clock_div[1];  // 25MHz com 50% duty cyclek_div[1];  // 25MHz com 50% duty cycle
	 
    // RAM
    ram ram_inst (
        .address_a(contador_endereco),
        .address_b(17'd0),
        .clock(clock),
        .data_a(8'd0),
        .data_b(8'd0),
        .wren_a(1'b0),
        .wren_b(1'b0),
        .q_a(dados_porta_a),
        .q_b(dados_porta_b)
    );

    // FIFO sinais
    reg escrita_na_fila;
    wire leitura_na_fila; // VGA ou outro módulo sempre lê
    wire [7:0] dados_da_fila;
    wire fila_vazia;
	 wire fila_cheia;
	 wire [7:0] dados_para_fila;

    fifo fifo_inst (
        .clock(clock),
        .data(dados_para_fila),      // enviando data_end para a FIFO
        .wrreq(escrita_na_fila),
        .rdreq(leitura_na_fila),
        .empty(fila_vazia),
        .full(fila_cheia),
        .q(dados_da_fila)
    );

	 // flag para ativar a leitura somente quando 480 bytes tiverem na fila
	 reg ativar_leitura_da_fila = 1'b0;
	 
    // Lógica do contador
    always @(posedge clock) begin // caso tenha chegado no endereco maximo
        if (contador_endereco == 17'd76599) begin
            contador_endereco <= 0;
		  end
        else begin // caso a fila esteja cheia, nao avança o endereco
            contador_endereco <= fila_cheia ? contador_endereco : contador_endereco + 1;
		  end
		  
		  if (contador_endereco == 17'd479 && ~ativar_leitura_da_fila) begin
				ativar_leitura_da_fila <= 1'b1;
		  end 
    end
	 
	 wire buscar_pixel_na_fila = (proximo_x_vga >= 160) && (proximo_x_vga < 480) && (proximo_y_vga >= 120) && (proximo_y_vga < 360);
	 
	 assign leitura_na_fila = ativar_leitura_da_fila && buscar_pixel_na_fila;
	 
	 assign leitura_fila_saida = ativar_leitura_da_fila;

    // FIFO write: só escreve quando não estiver cheia
    always @(posedge clock) begin
        escrita_na_fila <= !fila_cheia;
    end

    // Registradores de pipeline para data_first
    reg [7:0] dados_fila_reg;
    always @(posedge clock) begin
        dados_fila_reg <= dados_porta_a;   // atrasa 1 ciclo
    end
	 
	 assign dados_para_fila = dados_fila_reg;

    // Saídas
    assign dados_porta_a_saida = dados_porta_a; // dado atrasado 1 ciclo
    assign dados_fila_saida  = dados_da_fila;     // dado vindo da FIFO
	 assign contador_endereco_saida = contador_endereco;

	 wire	[7:0] byte_para_vga = buscar_pixel_na_fila ? dados_da_fila : 8'h00;
	
	vga_module vga(
		 .clock(clock),     // 25 MHz
		 .reset(~ativar_leitura_da_fila),     // Active high
		 .color_in(byte_para_vga), // Pixel color data (RRRGGGBB)
		 .next_x(proximo_x_vga),  // x-coordinate of NEXT pixel that will be drawn
		 .next_y(proximo_y_vga),  // y-coordinate of NEXT pixel that will be drawn
		 .hsync(hsync),    // HSYNC (to VGA connector)
		 .vsync(vsync),    // VSYNC (to VGA connctor)
		 .red(red),     // RED (to resistor DAC VGA connector)
		 .green(green),   // GREEN (to resistor DAC to VGA connector)
		 .blue(blue),    // BLUE (to resistor DAC to VGA connector)
		 .sync(syncs),          // SYNC to VGA connector
		 .clk(syncs),           // CLK to VGA connector
		 .blank(blank)          // BLANK to VGA connector
	);
	
	 
endmodule
