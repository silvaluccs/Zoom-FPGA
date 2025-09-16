
// Módulo pixel_replication_core corrigido
module pixel_replication_core (
    input [9:0] vga_x,    // 0-319 (após subtrair offset)
    input [8:0] vga_y,    // 0-239 (após subtrair offset)
    output reg [7:0] linha,
    output reg [8:0] coluna
);

    // Fator de zoom
    localparam ZOOM_FACTOR = 2;
    
    // Offset para centralizar (para zoom 2x, mostramos apenas o centro)
    localparam X_OFFSET = 80;  // (320 - 320/2)/2
    localparam Y_OFFSET = 60;  // (240 - 240/2)/2

    always @(*) begin
        // Aplica zoom (divisão) e offset
        coluna = (vga_x >> (ZOOM_FACTOR-1)) + X_OFFSET;
        linha  = (vga_y >> (ZOOM_FACTOR-1)) + Y_OFFSET;
        
        // Garante que não ultrapasse os limites
        if (coluna >= 320) coluna = 319;
        if (linha >= 240) linha = 239;
    end

endmodule