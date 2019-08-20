module EightInputMux #(parameter WIDTH = 64)
(
	input[WIDTH-1:0] data[7:0],
	input[2:0] select,
	output logic[WIDTH-1:0] out
);

	always_comb begin
		case(select) 
			3'b000 : out = data[0];
			3'b001 : out = data[1];
			3'b010 : out = data[2];
			3'b011 : out = data[3];
			3'b100 : out = data[4];
			3'b101 : out = data[5];
			3'b110 : out = data[6];
			3'b111 : out = data[7];
		endcase
	end

endmodule
