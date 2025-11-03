module pulse_generator_ff(
    input wire clock,        // ✅ Clock adicionado
    input wire enable,
    output reg pulse
);
    reg enable_prev;
    
    // Detecção de borda de subida sincronizada com clock
    always @(posedge clock) begin
        enable_prev <= enable;
        
        // Gera pulso de 1 ciclo na transição 0->1
        if (enable && !enable_prev) begin
            pulse <= 1'b1;
        end else begin
            pulse <= 1'b0;
        end
    end
    
endmodule