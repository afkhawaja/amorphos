
module FourHotToMux
(
	input[3:0] in,
	output logic[1:0] out
);
	always_comb begin
		case (in)
			4'b0000: out = 2'b00;
			4'b0001: out = 2'b00;
			4'b0010: out = 2'b01;
			4'b0100: out = 2'b10;
			4'b1000: out = 2'b11;
			default: out = 2'b00;
		endcase
	end
endmodule

module EightHotToMux
(
	input[7:0] in,
	output logic[2:0] out
);
	always_comb begin
		case (in)
			8'b00_00_00_01: out = 3'b0_0_0;
			8'b00_00_00_10: out = 3'b0_0_1;
			8'b00_00_01_00: out = 3'b0_1_0;
			8'b00_00_10_00: out = 3'b0_1_1;
			8'b00_01_00_00: out = 3'b1_0_0;
			8'b00_10_00_00: out = 3'b1_0_1;
			8'b01_00_00_00: out = 3'b1_1_0;
			8'b10_00_00_00: out = 3'b1_1_1;
			default: out = 3'b0_0_0;
		endcase
	end
endmodule


module OneHotMux #(parameter WIDTH = 64, N = 2)
(
	input[WIDTH-1:0] data[7:0],
	input[N-1:0] select,
	output logic[WIDTH-1:0] out
);

	generate
		if (N == 8) begin: using_8_mux
			wire[2:0] mux_sel;
			EightHotToMux  
			eight_hot_mux
			(
				.in(select),
				.out(mux_sel)
			);
			EightInputMux
			#(
				.WIDTH(WIDTH)
			)
			eight_input_mux
			(
				.data(data),
				.select(mux_sel),
				.out(out)
			);
		end else if (N == 4) begin : using_4_mux
			wire[1:0] mux_sel;
			FourHotToMux  
			four_hot_mux
			(
				.in(select),
				.out(mux_sel)
			);
			FourInputMux
			#(
				.WIDTH(WIDTH)
			)
			four_input_mux
			(
				.data(data),
				.select(mux_sel),
				.out(out)
			);
		end else if (N == 2) begin : using_2_mux
			logic select_tmp;
			assign select_tmp = (select == 2'b10 ? 1'b1 : 1'b0);
			TwoInputMux 
			#(
			.WIDTH(WIDTH)
			)
			single_2in_mux
			(
				.data0(data[0]),
				.data1(data[1]),
				.select(select_tmp),
				.out(out)
			);
			//assign out = data[select_tmp];	
		end else begin : using_no_mux // N must be 1
			assign out = data[0];
		end
	endgenerate

endmodule
