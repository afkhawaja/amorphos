

module TwoInputMux #(parameter WIDTH = 64)
(
	input[WIDTH-1:0] data0,
	input[WIDTH-1:0] data1,
	input select,
	output logic[WIDTH-1:0] out
);

	always_comb begin
		if (select == 1'b1) begin
			out = data1;
		end else begin
			out = data0;
		end	
	end

endmodule
