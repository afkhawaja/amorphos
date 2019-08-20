

module Two2OneEncoder(
input[1:0]  one_hots,
output logic mux_select
);

always_comb begin
	if (one_hots[1] == 1'b1) begin
		mux_select = 1'b1;
	end else begin
		mux_select = 1'b0;
	end
end

endmodule

module Four2OneEncoder(
input[3:0]  one_hots,
output logic[1:0] mux_select
);

always_comb begin
	if (one_hots[3] == 1'b1) begin
		mux_select = 2'b11;
	end else if (one_hots[2] == 1'b1) begin
		mux_select = 2'b10;
	end else if (one_hots[1] == 1'b1) begin
		mux_select = 2'b01;
	end else begin
		mux_select = 2'b00;
	end
end

endmodule

module Eight2OneEncoder(
input[7:0]  one_hots,
output logic[2:0] mux_select
);

always_comb begin
	if (one_hots[7] == 1'b1) begin
		mux_select = 3'b111;
	end else if (one_hots[6] == 1'b1) begin
		mux_select = 3'b110;
	end else if (one_hots[5] == 1'b1) begin
		mux_select = 3'b101;
	end else if (one_hots[4] == 1'b1) begin
		mux_select = 3'b100;
	end else if (one_hots[3] == 1'b1) begin
		mux_select = 3'b011;
	end else if (one_hots[2] == 1'b1) begin
		mux_select = 3'b010;
	end else if (one_hots[1] == 1'b1) begin
		mux_select = 3'b001;
	end else begin
		mux_select = 3'b000;
	end
end

endmodule

module OneHotEncoder #(parameter ONE_HOTS = 2, MUX_SELECTS = 1)
(
	input[ONE_HOTS-1:0] one_hots,
	output logic[MUX_SELECTS-1:0] mux_select
);

	generate 
		if (ONE_HOTS == 1) begin : config_one
			assign mux_select = 1'b0;
		end else if (ONE_HOTS == 2) begin : config_two
			Two2OneEncoder
			two2one_inst(
				.one_hots(one_hots),
				.mux_select(mux_select)
			);
		end else if (ONE_HOTS == 4) begin : config_four
			Four2OneEncoder
			four2one_inst(
				.one_hots(one_hots),
				.mux_select(mux_select)
			);		
		end else if (ONE_HOTS == 8) begin : config_eight
			Eight2OneEncoder
			eight2one_inst(
				.one_hots(one_hots),
				.mux_select(mux_select)
			);
		end
	endgenerate

endmodule
