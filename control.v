module control (
  input clock,
  output wire hsync,    
  output wire vsync,    
  output [7:0] red,     
  output [7:0] green,   
  output [7:0] blue,    
  output sync,          
  output clk,           
  output blank      
);

reg  [15:0] endereco_pixel;
wire [15:0] pixels;
wire [9:0] proximo_x, proximo_y; // vêm do VGA
reg clock_vga;
reg enviar_alto;
reg [7:0] color;

initial begin
    clock_vga = 0;
    endereco_pixel = 16'h0000;
    enviar_alto = 0;
end

ram ram_instancia (
    .address(endereco_pixel),
    .clock(clock),
	 .data(16'h0000),
	 .rden(1'b1),
	 .wren(1'b0),
	 .q(pixels)
);

always @(posedge clock) begin
    clock_vga <= ~clock_vga;
    enviar_alto <= ~enviar_alto;

    if (proximo_x >= 160 && proximo_x < 480 &&
        proximo_y >= 120 && proximo_y < 360) begin
        if (enviar_alto) begin
            color <= pixels[15:8];
        end else begin
            color <= pixels[7:0];
            endereco_pixel <= endereco_pixel + 1;
        end
    end else begin
        color <= 8'h00;
    end
end

vga_module vga_module_inst (
    .clock(clock_vga),
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

endmodule
