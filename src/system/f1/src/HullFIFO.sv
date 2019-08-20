/*

    Author: Ahmed Khawaja
    
    This module abstracts the different types of FIFOs that can be used in the system
    
    TypeNum  Type
    0        SoftFIFO (in pure verilog)
    1        Catapult Hardened FIFO
    2        F1 Shifting flop FIFO
	3        F1 BRAM FIFO (unimplemented)

*/

module HullFIFO #(parameter TYPE = 0, WIDTH = 32, LOG_DEPTH = 2)
(
    // General signals
    input  clock,
    input  reset_n,
    // Data in and write enable
    input             wrreq, //enq
    input[WIDTH-1:0]  data,// data in
    output            full,
    output[WIDTH-1:0] q, // data out
    output logic      empty,
    input             rdreq // deq
);

	wire half_full;
	wire data_valid;
	
    generate
        if (TYPE == 0) begin : Hull_SoftFIFO
            SoftFIFO
            #(
                .WIDTH                  (WIDTH),
                .LOG_DEPTH              (LOG_DEPTH)
            )
            softfifo_inst
            (
                .clock                  (clock),
                .reset_n                (reset_n),
                .wrreq                  (wrreq),
                .data                   (data),
                .full                   (full),
                .q                      (q),
                .empty                  (empty),
                .rdreq                  (rdreq)
            );
        end else if (TYPE == 1) begin : Hull_CatapultFIFO
            FIFO
            #(
                .WIDTH                  (WIDTH),
                .LOG_DEPTH              (LOG_DEPTH)
            )
            catapultfifo_inst
            (
                .clock                  (clock),
                .reset_n                (reset_n),
                .wrreq                  (wrreq),
                .data                   (data),
                .full                   (full),
                .q                      (q),
                .empty                  (empty),
                .rdreq                  (rdreq)
            );
        end else if (TYPE == 2) begin : Hull_F1_FlopFIFO
			flop_fifo
			#(
				.WIDTH(WIDTH),
				.DEPTH((1 << LOG_DEPTH)) // convert log dpeth 
			)
			f1_flopfifo_inst
			(
				// Inputs
				.clk(clock), 
				.rst_n(reset_n), 
				.sync_rst_n(1'b1), // active low secondary reset, disable for now
				.cfg_watermark((1 << LOG_DEPTH) - 1), // when the full signal is asserted
				.push(wrreq),
				.push_data(data), 
				.pop(rdreq),
				// Outputs
				.pop_data(q), 
				.half_full(half_full), 
				.watermark(full),
				.data_valid(data_valid)
			);
			assign empty = !data_valid;
        end else if (TYPE == 3) begin : Hull_F1_BRAM_FIFO
			// use the bram_2rw module in shell/design/lib/bram_2rw.sv
		end
    endgenerate

endmodule
