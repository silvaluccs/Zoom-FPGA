module delayed_clock_generator(
    input wire clk,        // Clock principal (da FPGA ou HPS)
    input wire enable,     // Sinal de enable (controle externo)
    output reg delayed_clk // Clock com a borda de subida após 1 ciclo de enable
);

    reg enable_d; // Registrador para armazenar o valor anterior do enable

    always @(posedge clk) begin
        enable_d <= enable;  // Armazena o valor do enable no ciclo anterior
    end

    always @(posedge clk) begin
        if (enable_d == 1 && enable == 0) begin
            delayed_clk <= 1;  // Gera a borda de subida um ciclo após o enable
        end else begin
            delayed_clk <= 0;  // Mantém o sinal de clock baixo caso contrário
        end
    end
	 
	 

endmodule
