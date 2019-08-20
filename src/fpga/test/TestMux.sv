// testbench for the FIFO
`timescale 1 ns / 1 ns
module onehotmux_test();

	reg clk;
	reg rst;
	reg[32-1:0]  data[4-1:0];
	reg[2-1:0]   select;
	wire[32-1:0] out;
	
OneHotMux 
#
(
.WIDTH(32), 
.N(2)
)
one_hot_mux
(
	.data(data[1:0]),
	.select(select),
	.out(out)
);

always #1 clk = !clk;

initial begin
	data[0] = 32'haaaa_aaaa;
	data[1] = 32'hbbbb_bbbb;
	data[2] = 32'hcccc_cccc;
	data[3] = 32'hdddd_dddd;
	
	$display("Starting up here!\n");
	clk = 1'b1;
	rst = 1'b1;
	#2
	rst = 1'b0;
	select = 4'b0_0_0_1;
	#2
	$display("Select: %b Out: %h ", select, out);
	select = 4'b0_0_1_0;
	#2
	$display("Select: %b Out: %h ", select, out);
	select = 4'b0_1_0_0;
	#2
	$display("Select: %b Out: %h ", select, out);
	select = 4'b1_0_0_0;
	#2
	$display("Select: %b Out: %h ", select, out);
end
	
	
endmodule