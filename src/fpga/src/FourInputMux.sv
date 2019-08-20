module FourInputMux #(parameter WIDTH = 64)
(
	input[WIDTH-1:0] data[3:0],
	input[1:0] select,
	output logic[WIDTH-1:0] out
);

	always_comb begin
		case(select) 
			2'b00 : out = data[0];
			2'b01 : out = data[1];
			2'b10 : out = data[2];
			2'b11 : out = data[3];
		endcase
	end

endmodule
