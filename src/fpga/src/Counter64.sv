
module Counter64
(
    input                               clk,
    input                               rst, 
	input								increment,
	output[63:0]						count

);

	reg[31:0]  lower;
	reg[31:0]  upper;
	logic[31:0] new_lower;
	logic[31:0] new_upper;

	assign count = {upper,lower};
	
	always@(posedge clk) begin : counter64_update
		if (rst) begin
			lower <= 32'h0000_0000;
			upper <= 32'h0000_0000;
		end else begin
			lower <= new_lower;
			upper <= new_upper;
		end
	end

	always_comb begin : counter64_update_logic

		new_lower = lower;
		new_upper = upper;

		if (increment) begin
			// check if overflow will occur
			if (lower == 32'hFFFF_FFFF) begin
				new_upper = upper + 32'h1;
				new_lower = 32'h0;
			end else begin
				new_lower = lower + 32'h1;
			end
		end

	end

endmodule
