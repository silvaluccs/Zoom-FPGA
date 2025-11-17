module gerador_de_sinal(
	input clk_50,
	input reset_n,
	input chipselect,
	input write_n,
	input [1:0] address,
	output reg new_data_50
);


always @(posedge clk_50 or negedge reset_n) begin
    if (!reset_n)
        new_data_50 <= 0;
    else
        new_data_50 <= chipselect && ~write_n && (address == 0);
end


endmodule