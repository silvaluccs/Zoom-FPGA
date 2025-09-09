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

reg  [16:0] endereco_pixel;  
wire [7:0] pixels;           
wire [9:0] proximo_x;        
wire [9:0] proximo_y;        
reg clock_vga;              
reg [7:0] color;             


always @(posedge clock) begin
  clock_vga <= ~clock_vga;
end


ram_nova ram_instancia (
    .address(endereco_pixel),  
    .clock(clock_vga),
    .data(8'h00),              
    .rden(1'b1),               
    .wren(1'b0),               
    .q(pixels)                 
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
    if (proximo_x >= 159 && proximo_x < 479 && proximo_y >= 120 && proximo_y < 360) begin
        
        endereco_pixel <= (proximo_y - 120) * 320 + (proximo_x - 158);  
        
        color <= pixels[7:0];  
    end else begin
        color <= 8'h00;
    end
    
end

endmodule
