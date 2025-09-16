module control (
  input clock,
  input input_chave,      // Nova entrada para a chave
  output wire hsync,    
  output wire vsync,    
  output [7:0] red,     
  output [7:0] green,   
  output [7:0] blue,    
  output sync,          
  output clk,           
  output blank          
);

reg  [16:0] endereco_pixel;  
wire [7:0] pixels;           
wire [9:0] proximo_x;        
wire [9:0] proximo_y;        
reg clock_vga;              
reg [7:0] color;             

// Coordenadas dentro da área de display
wire [9:0] display_x = proximo_x - 158;
wire [8:0] display_y = proximo_y - 119;

// Instância do módulo que calcula o endereço para o zoom
wire [7:0] zoom_linha;
wire [8:0] zoom_coluna;

pixel_replication_core zoom_core (
    .vga_x(display_x),
    .vga_y(display_y),
    .linha(zoom_linha),
    .coluna(zoom_coluna)
);

// Multiplexador para selecionar o endereço de acordo com a chave
reg [7:0] linha_sel;
reg [8:0] coluna_sel;

always @(*) begin
    if (input_chave) begin
        // Modo zoom 2x
        linha_sel  = zoom_linha;
        coluna_sel = zoom_coluna;
    end else begin
        // Modo normal
        linha_sel  = display_y[7:0];   // Y -> linha (0-239)
        coluna_sel = display_x[8:0];   // X -> coluna (0-319)
    end
end

// Verificação de limites
wire coordenada_valida = (linha_sel < 240) && (coluna_sel < 320);

matriz framebuffer (
    .clock(clock_vga),
    .linha(linha_sel),
    .coluna(coluna_sel),
    .escrever_na_matriz(1'b0),  
    .byte_entrada(8'h00),
    .byte(pixels)
);

vga_module vga_module_inst (
    .clock(~clock_vga),
    .reset(1'b0),
    .color_in(color),
    .next_x(proximo_x),
    .next_y(proximo_y),
    .hsync(hsync),
    .vsync(vsync),
    .red(red),
    .green(green),
    .blue(blue),
    .sync(sync),
    .clk(clk),
    .blank(blank)
);

always @(*) begin
    // Verifica se está dentro da área de display E se as coordenadas são válidas
    if ((proximo_x >= 159 && proximo_x < 479) && 
        (proximo_y >= 120 && proximo_y < 360) &&
        coordenada_valida) begin
        color = pixels[7:0];
    end else begin
        color = 8'h00;
    end
end

always @(posedge clock) begin
  clock_vga <= ~clock_vga;
end

endmodule
