// testbench for the FIFO
`timescale 1 ns / 1 ns
module fifo_test();

	reg clk;
	reg rst;
	
	wire             reqQ_empty;
	wire             reqQ_full;
	reg             reqQ_enq;
	reg             reqQ_deq;
	reg[15:0]       reqQ_in;
	wire[15:0]       reqQ_out;

    FIFO
	#(
		.WIDTH					(16),
		.LOG_DEPTH				(4)
	)
	testFIFO
	(
		.clock					(clk),
		.reset_n				(~rst),
		.wrreq					(reqQ_enq),
		.data                   (reqQ_in),
		.full                   (reqQ_full),
		.q                      (reqQ_out),
		.empty                  (reqQ_empty),
		.rdreq                  (reqQ_deq)
	);	

initial begin
	$display("Starting up here!\n");
	reqQ_enq = 1'b0;
	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;
	for (int i = 0; i < 25; i = i + 1) begin
		#2
		while (reqQ_full) begin
			#2
			$display("Queue is full!");
		end
		$display("Enqueued %d", i);
		reqQ_in  = i;
		reqQ_enq = 1'b1;
	end
	#2
	reqQ_enq = 1'b0;
end

int j;

initial begin
	reqQ_deq = 1'b0;
	#2
	#40
	j = 0;
	while (j < 25) begin
		#2
		if (!reqQ_empty) begin
			j = j + 1;
			reqQ_deq = 1'b1;
			$display("Dequeued: %d", reqQ_out);
		end else begin
			reqQ_deq = 1'b0;
		end
	end
	$stop;
end

always #1 clk = !clk;

endmodule