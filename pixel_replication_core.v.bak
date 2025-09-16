module pixel_replication_core (
    input [9:0] vga_x,
    input [8:0] vga_y,
    output reg [16:0] ram_address
);

    // As dimensões da imagem de entrada são 320x240
    localparam IMAGE_WIDTH = 320;
    localparam ZOOM_FACTOR = 2;

    // Cálculo do offset para centralizar o zoom 2x
    localparam X_OFFSET = (IMAGE_WIDTH / ZOOM_FACTOR) / 2; // (320 / 2) / 2 = 80
    localparam Y_OFFSET = (240 / ZOOM_FACTOR) / 2; // (240 / 2) / 2 = 60
    
    // Este bloco combina a lógica para calcular o endereço
    always @(*) begin
        reg [9:0] mapped_x;
        reg [8:0] mapped_y;
        
        // Aplica a replicação de pixel (divisão por 2)
        mapped_x = (vga_x >> 1);
        mapped_y = (vga_y >> 1);
        
        // Adiciona o offset para centralizar o zoom
        mapped_x = mapped_x + X_OFFSET;
        mapped_y = mapped_y + Y_OFFSET;
        
        // Converte as coordenadas 2D para um endereço linear 1D
        ram_address = (mapped_y * IMAGE_WIDTH) + mapped_x;
    end

endmodule