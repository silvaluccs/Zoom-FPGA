module controle_vga(
    input clock,
	 input [16:0] endereco_escrita,
	 input [7:0] byte_para_escrita,
	 input clock_b,
	 input permicao_escrita,
    output wire hsync,
    output wire vsync,    
    output [7:0] red,     
    output [7:0] green,   
    output [7:0] blue,    
    output sync,          
    output clk,           
    output blank
);

    // Contador de endereço da RAM
    reg [16:0] contador_escrita = 0;
    reg [16:0] contador_leitura = 0;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    
    // Dados vindos da RAM
    wire [7:0] dados_porta_a;
	 
	 wire [7:0] dados_porta_b;

	 
    // RAM
    ram ram_inst (
        .address_a(contador_escrita),
        .address_b(endereco_escrita),
        .clock_a(clock),
		  .clock_b(clock_b),
        .data_a(8'd0),
        .data_b(byte_para_escrita),
        .wren_a(1'b0),
        .wren_b(permicao_escrita),
        .q_a(dados_porta_a),
        .q_b(dados_porta_b)
    );

    // FIFO sinais
    reg escrita_na_fila = 1'b0;
    wire [7:0] dados_da_fila;
    wire fila_vazia;
    wire fila_cheia;

    fifo fifo_inst (
        .clock(clock),
        .data(dados_porta_a),
        .wrreq(escrita_na_fila && !fila_cheia),
        .rdreq(leitura_na_fila && !fila_vazia),
        .empty(fila_vazia),
        .full(fila_cheia),
        .q(dados_da_fila)
    );

    // Controle de região ativa (320x240 centralizado em 640x480)
    wire regiao_ativa = (pixel_x >= 160) && (pixel_x < 480) && 
                       (pixel_y >= 120) && (pixel_y < 360);
    
    // Leitura sincronizada - só lê quando está na região ativa
    wire leitura_na_fila = regiao_ativa;
    
    // Sinal de início do frame para resetar os contadores
    wire inicio_frame;
    reg vsync_anterior = 1'b0;
    
    always @(posedge clock) begin
        vsync_anterior <= vsync;
    end
    
    assign inicio_frame = vsync_anterior && !vsync; // Detecção de borda de descida do VSYNC

    // Lógica de escrita na FIFO (preenche a FIFO antes do frame)
    reg preenchimento_completo = 1'b0;
    
    always @(posedge clock) begin
        if (inicio_frame) begin
            // Reset no início de cada frame
            contador_escrita <= 0;
            contador_leitura <= 0;
            preenchimento_completo <= 1'b0;
        end else begin
            // Preenche a FIFO com pelo menos 320 pixels (uma linha) antes de começar
            if (!preenchimento_completo && !fila_cheia && contador_escrita < 17'd320) begin
                contador_escrita <= contador_escrita + 1;
                escrita_na_fila <= 1'b1;
                if (contador_escrita == 17'd319) begin
                    preenchimento_completo <= 1'b1;
                end
            end 
            // Durante a região ativa, mantém a FIFO alimentada
            else if (preenchimento_completo && regiao_ativa && !fila_cheia && contador_escrita < 17'd76800) begin
                contador_escrita <= contador_escrita + 1;
                escrita_na_fila <= 1'b1;
            end else begin
                escrita_na_fila <= 1'b0;
            end
        end
    end

    // Contador de leitura baseado nas coordenadas VGA
    always @(posedge clock) begin
        if (inicio_frame) begin
            contador_leitura <= 0;
        end else if (leitura_na_fila && !fila_vazia) begin
            // Avança o contador de leitura apenas quando um pixel é consumido
            contador_leitura <= contador_leitura + 1;
        end
    end

    // Buffer de saída para sincronização
    reg [7:0] pixel_sincronizado;
    reg leitura_valida = 1'b0;
    
    always @(posedge clock) begin
        leitura_valida <= leitura_na_fila && !fila_vazia;
        
        if (leitura_valida) begin
            pixel_sincronizado <= dados_da_fila;
        end else begin
            pixel_sincronizado <= 8'h00; // Preto fora da região ativa
        end
    end

    vga_module vga(
        .clock(clock),
        .reset(1'b0),
        .color_in(pixel_sincronizado),
        .next_x(pixel_x),
        .next_y(pixel_y),
        .hsync(hsync),
        .vsync(vsync),
        .red(red),
        .green(green),
        .blue(blue),
        .sync(sync),
        .clk(clk),
        .blank(blank)
    );

endmodule