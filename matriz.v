
// Módulo matriz corrigido
module matriz(
    input clock,
    input [7:0] linha,
    input [8:0] coluna,
    input escrever_na_matriz,
    input [7:0] byte_entrada,
    output [7:0] byte
);
    
    // Cálculo correto do endereço linear
    wire [16:0] endereco_pixel = {linha, 8'd0} + {linha, 6'd0} + coluna; // linha * 320 + coluna
    
    // Ou usando multiplicação (se sua ferramenta suportar)
    // wire [16:0] endereco_pixel = linha * 9'd320 + coluna;
    
    ram_nova ram1 (
         .address(endereco_pixel),  
         .clock(clock),
         .data(byte_entrada),              
         .rden(~escrever_na_matriz),               
         .wren(escrever_na_matriz),               
         .q(byte)                 
    );

endmodule
