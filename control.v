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

// Endereço para a imagem com zoom
wire [16:0] zoom_ram_address;

// Endereço para a imagem original (sem zoom)
wire [16:0] original_ram_address;

// O seu código original tem um deslocamento (offset) na tela
// Para manter esse comportamento na imagem original, você deve subtrair os offsets.
assign original_ram_address = (proximo_y - 120) * 320 + (proximo_x - 158);

always @(posedge clock) begin
  clock_vga <= ~clock_vga;
end

// Instância do módulo que calcula o endereço para o zoom
pixel_replication_core zoom_core (
    .vga_x(proximo_x - 158), // Passa a coordenada com o offset já removido
    .vga_y(proximo_y - 120), // Passa a coordenada com o offset já removido
    .ram_address(zoom_ram_address)
);

// Multiplexador para selecionar o endereço de acordo com a chave
// Se input_chave for '1', usa o endereço com zoom.
// Se input_chave for '0', usa o endereço original.
always @(*) begin
    if (input_chave == 1'b1) begin
        endereco_pixel = zoom_ram_address;
    end else begin
        endereco_pixel = original_ram_address;
    end
end

// Sua instância da RAM (sem alterações)
ram_nova ram_instancia (
    .address(endereco_pixel),  
    .clock(clock_vga),
    .data(8'h00),              
    .rden(1'b1),               
    .wren(1'b0),               
    .q(pixels)                 
);

// Sua instância do módulo VGA (sem alterações)
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
    // Esta lógica de controle da cor e da área de exibição é mantida
    if (proximo_x >= 159 && proximo_x < 479 && proximo_y >= 120 && proximo_y < 360) begin
        color = pixels[7:0];
    end else begin
        color = 8'h00;
    end
end

endmodule