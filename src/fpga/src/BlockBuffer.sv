import ShellTypes::*;
import AMITypes::*;

module BlockSector
#(
	parameter integer WIDTH = 64
)
(
	input			 clk,
	input 			 rst,
	input[WIDTH-1:0] wrInput,
	input[WIDTH-1:0] rdInput,
	input            inMuxSel,
	input 			 sector_we,
	output logic[WIDTH-1:0] dataout
);

	reg[WIDTH-1:0]  data_reg;
	wire[WIDTH-1:0] new_data;
	
	always@(posedge clk) begin
		if (rst) begin
			data_reg <= 0;
		end else begin
			if (sector_we) begin
				data_reg <= new_data;
			end
		end
	end

	assign dataout  = data_reg;
	assign new_data = (inMuxSel == 1'b1) ? wrInput : rdInput;
	
endmodule

module we_decoder(
	input we_all,
	input we_specific,
	input[2:0]  index,
	output logic[7:0] we_out
);

	always_comb begin
		we_out =  8'b0000_0000;
		if (we_all) begin
			we_out = 8'b1111_1111;
		end else begin
			if (we_specific) begin
				we_out[index] = 1'b1;
			end
		end
	end
	
endmodule

module block_rotate
#(
	parameter integer WIDTH = 64,
	parameter integer NUM_SECTORS = 8
)
(
	input[2:0] rotate_amount,
	input[WIDTH-1:0]  inData[NUM_SECTORS-1:0],
	output logic[WIDTH-1:0] outData[NUM_SECTORS-1:0]
);

	always_comb begin
		outData = inData;
		if (rotate_amount == 0) begin
			outData = inData;
		end else if (rotate_amount == 1) begin 
			outData[0] = inData[1];
			outData[1] = inData[2];
			outData[2] = inData[3];
			outData[3] = inData[4];
			outData[4] = inData[5];
			outData[5] = inData[6];
			outData[6] = inData[7];
			outData[7] = inData[0];
		end else if (rotate_amount == 2) begin 
			outData[0] = inData[2];
			outData[1] = inData[3];
			outData[2] = inData[4];
			outData[3] = inData[5];
			outData[4] = inData[6];
			outData[5] = inData[7];
			outData[6] = inData[0];
			outData[7] = inData[1];
		end else if (rotate_amount == 3) begin 
			outData[0] = inData[3];
			outData[1] = inData[4];
			outData[2] = inData[5];
			outData[3] = inData[6];
			outData[4] = inData[7];
			outData[5] = inData[0];
			outData[6] = inData[1];
			outData[7] = inData[2];
		end else if (rotate_amount == 4) begin 
			outData[0] = inData[4];
			outData[1] = inData[5];
			outData[2] = inData[6];
			outData[3] = inData[7];
			outData[4] = inData[0];
			outData[5] = inData[1];
			outData[6] = inData[2];
			outData[7] = inData[3];
		end else if (rotate_amount == 5) begin 
			outData[0] = inData[5];
			outData[1] = inData[6];
			outData[2] = inData[7];
			outData[3] = inData[0];
			outData[4] = inData[1];
			outData[5] = inData[2];
			outData[6] = inData[3];
			outData[7] = inData[4];
		end else if (rotate_amount == 6) begin 
			outData[0] = inData[6];
			outData[1] = inData[7];
			outData[2] = inData[0];
			outData[3] = inData[1];
			outData[4] = inData[2];
			outData[5] = inData[3];
			outData[6] = inData[4];
			outData[7] = inData[5];
		end else if (rotate_amount == 7) begin 
			outData[0] = inData[7];
			outData[1] = inData[0];
			outData[2] = inData[1];
			outData[3] = inData[2];
			outData[4] = inData[3];
			outData[5] = inData[4];
			outData[6] = inData[5];
			outData[7] = inData[6];
		end
	end

endmodule

module BlockBuffer
(
	// General signals
	input			   clk,
	input 			   rst,
	input 			   flush_buffer,
	// Interface to App
	input AMIRequest   reqIn,
	output logic       reqIn_grant,
	output AMIResponse respOut,
	input 			   respOut_grant,
	// Interface to Memory system, 2 ports enables simulatentous eviction and request of a new block
	output AMIRequest  reqOut[AMI_NUM_PORTS-1:0], // port 0 is the rd port, port 1 is the wr port
	input 			   reqOut_grant[AMI_NUM_PORTS-1:0],
	input AMIResponse  respIn[AMI_NUM_PORTS-1:0],
	output logic       respIn_grant[AMI_NUM_PORTS-1:0]
	
);

	// Params
	localparam NUM_SECTORS  = 8;
	localparam SECTOR_WIDTH = 64;
	
	// Sectors
	wire[SECTOR_WIDTH-1:0] wrInput[NUM_SECTORS-1:0];
	wire[SECTOR_WIDTH-1:0] rdInput[NUM_SECTORS-1:0];
	wire[SECTOR_WIDTH-1:0] dataout[NUM_SECTORS-1:0];
	wire[(NUM_SECTORS*SECTOR_WIDTH)-1:0] wr_output;
	wire[NUM_SECTORS-1:0] sector_we;
	
	// Queue for incoming AMIRequests
	wire             reqInQ_empty;
	wire             reqInQ_full;
	logic            reqInQ_enq;
	logic            reqInQ_deq;
	AMIRequest       reqInQ_in;
	AMIRequest       reqInQ_out;
	
	// Following signals will be controlled by the FSM
	logic inMuxSel; // 0 for RdInput, 1 for WrInput

	genvar sector_num;
	generate 
		for (sector_num = 0; sector_num < NUM_SECTORS; sector_num = sector_num + 1) begin : sector_inst
			BlockSector
			#(
				.WIDTH(SECTOR_WIDTH)
			)
			block_sector
			(
				.clk (clk),
				.rst (rst),
				.wrInput(wrInput[sector_num]),
				.rdInput(rdInput[sector_num]),
				.inMuxSel(inMuxSel),
				.sector_we(sector_we[sector_num]),
				.dataout(dataout[sector_num])
			);
			
			assign wrInput[sector_num] = reqInQ_out.data[SECTOR_WIDTH-1:0];
			assign rdInput[sector_num] = respIn[0].data[((sector_num+1)*SECTOR_WIDTH)-1:(sector_num*SECTOR_WIDTH)];
			assign wr_output[((sector_num+1)*SECTOR_WIDTH)-1:(sector_num*SECTOR_WIDTH)] = dataout[sector_num];
		end
	endgenerate

	// Read data out of the block
	logic[SECTOR_WIDTH-1:0] rd_output;
	logic[$clog2(NUM_SECTORS)-1:0] rd_mux_sel; // controlled by the FSM

	assign rd_output = dataout[rd_mux_sel];

	// Write enables per sector

	// FSM signals
	logic wr_all_sectors;
	logic wr_specific_sector;
	logic[$clog2(NUM_SECTORS)-1:0] wr_sector_index;
	
	we_decoder
	writes_decoder
	(
		.we_all      (wr_all_sectors),
		.we_specific (wr_specific_sector),
		.index       (wr_sector_index),
		.we_out      (sector_we)
	);

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_reqIn_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(BLOCK_BUFFER_REQ_IN_Q_DEPTH)
			)
			reqIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqInQ_enq),
				.data                   (reqInQ_in),
				.full                   (reqInQ_full),
				.q                      (reqInQ_out),
				.empty                  (reqInQ_empty),
				.rdreq                  (reqInQ_deq)
			);
		end else begin : FIFO_reqIn_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(BLOCK_BUFFER_REQ_IN_Q_DEPTH)
			)
			reqIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqInQ_enq),
				.data                   (reqInQ_in),
				.full                   (reqInQ_full),
				.q                      (reqInQ_out),
				.empty                  (reqInQ_empty),
				.rdreq                  (reqInQ_deq)
			);
		end
	endgenerate		

	assign reqInQ_in   = reqIn;
	assign reqInQ_enq  = reqIn.valid && !reqInQ_full;
	assign reqIn_grant = reqInQ_enq;

	// Queue for outgoing AMIResponses
	wire             respOutQ_empty;
	wire             respOutQ_full;
	logic            respOutQ_enq;
	logic            respOutQ_deq;
	AMIResponse      respOutQ_in;
	AMIResponse      respOutQ_out;	

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_respOut_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(BLOCK_BUFFER_RESP_OUT_Q_DEPTH)
			)
			respOut_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respOutQ_enq),
				.data                   (respOutQ_in),
				.full                   (respOutQ_full),
				.q                      (respOutQ_out),
				.empty                  (respOutQ_empty),
				.rdreq                  (respOutQ_deq)
			);
		end else begin : FIFO_respOut_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(BLOCK_BUFFER_RESP_OUT_Q_DEPTH)
			)
			respOut_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respOutQ_enq),
				.data                   (respOutQ_in),
				.full                   (respOutQ_full),
				.q                      (respOutQ_out),
				.empty                  (respOutQ_empty),
				.rdreq                  (respOutQ_deq)
			);
		end
	endgenerate
	
	assign respOut = '{valid: (!respOutQ_empty && respOutQ_out.valid), data: respOutQ_out.data, size: respOutQ_out.size};
	assign respOutQ_deq = respOut_grant;
	
	/////////////////////
	// FSM
	/////////////////////

	// FSM States
	parameter INVALID     = 3'b000;
	parameter PENDING     = 3'b001;
	parameter CLEAN       = 3'b010;
	parameter MODIFIED    = 3'b011;

	// FSM registers
	reg[2:0]   current_state;
	logic[2:0] next_state;

	// FSM reset/update
	always@(posedge clk) begin : fsm_update
		if (rst) begin
			current_state <= INVALID;
		end else begin
			current_state <= next_state;
		end
	end
	
	// Current request info
	reg[AMI_ADDR_WIDTH-6:0]   current_block_index;
	logic[AMI_ADDR_WIDTH-6:0] new_block_index;
	logic                     block_index_we;

	always@(posedge clk) begin : current_block_update
		if (rst) begin
			current_block_index <= 0;
		end else begin
			if (block_index_we) begin
				current_block_index <= new_block_index;
			end
		end
	end
	// FSM state transitions
	// FSM controlled signals
	// inMuxSel 0 for RdInput, 1 for WrInput
	// wr_all_sectors
	// wr_specific_sector
	// wr_sector_index
	// rd_mux_sel
	// reqOut[0] for issuing reads
	// reqOut[1] for issuing writes
	// respIn_grant[0] , read port
	// respIn_grant[1] , no responses should come back on the write port
	// reqIn_grant
	// respOut
	// block_index_we
	// new_block_index
	// reqInQ_deq
	// respOutQ_enq
	// respOutQ_in

	always_comb begin
		// Signals controlling writing into the block
		inMuxSel           = 1'b0;
		wr_all_sectors     = 1'b0;
		wr_specific_sector = 1'b0;
		wr_sector_index    = reqInQ_out.addr[5:3]; // assume bits 2-0 are 0, 8 byte alignment
		// mux out correct sector
		rd_mux_sel         = reqInQ_out.addr[5:3]; // assume bits 2-0 are 0, 8 byte alignment
		// block index
		new_block_index = current_block_index;
		block_index_we  = 1'b0;
		// requests to the memory system
		reqOut[0] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64}; // read port
		reqOut[1] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64}; // write port
		// response from memory system
		respIn_grant[0] = 1'b0;
		respIn_grant[1] = 1'b0;
		// control the queues to 
		reqInQ_deq   = 1'b0;
		respOutQ_enq = 1'b0;
		respOutQ_in  = '{valid: 0, data: 512'b0, size: 64}; 
		// state control
		next_state = current_state;

		case (current_state)
			INVALID : begin
				// valid  request waiting to be serviced, but no valid block in the buffer
				if (!reqInQ_empty && reqInQ_out.valid)  begin
					reqOut[0] = '{valid: 1, isWrite: 1'b0, addr: {reqInQ_out.addr[63:6],6'b00_0000} , data: 512'b0, size: 64}; // read port
					if (reqOut_grant[0] == 1'b1) begin
						// block is being read
						new_block_index = reqInQ_out.addr[63:6];
						block_index_we  = 1'b1;
						// go to pending state
						next_state = PENDING;
					end
				end
			end
			PENDING : begin
				// waiting for a block to be read from memory and into the block buffer
				if (respIn[0].valid) begin
					inMuxSel = 1'b0; //rdInput
					wr_all_sectors  = 1'b1; // write every sector
					respIn_grant[0] = 1'b1; // accept the response
					next_state = CLEAN;
				end
			end
			CLEAN : begin
				// we have a valid block, can service a request if the block index matches
				if (!reqInQ_empty && reqInQ_out.valid) begin
					// go ahead and service the request from the local block buffer
					if (reqInQ_out.addr[63:6] == current_block_index) begin
						// service a write operation
						if (reqInQ_out.isWrite) begin
							inMuxSel = 1'b1; // wrInput
							wr_specific_sector = 1'b1;
							reqInQ_deq = 1'b1;
							next_state = MODIFIED;
						// service a read operation
						end else begin
							reqInQ_deq   = 1'b1;
							respOutQ_enq = 1'b1;
							respOutQ_in  = '{valid: 1, data: {448'b0,rd_output}, size: 8}; 
						end
					// a new block must be fetched, but this one does not need to be written back since it is CLEAN
					end else begin
						// fetch a different block
						reqOut[0] = '{valid: 1, isWrite: 1'b0, addr: {reqInQ_out.addr[63:6],6'b00_0000} , data: 512'b0, size: 64}; // read port
						if (reqOut_grant[0] == 1'b1) begin
							// block is being read
							new_block_index = reqInQ_out.addr[63:6];
							block_index_we  = 1'b1;
							// go to pending state
							next_state = PENDING;
						end
					end
				end
				// otherwise sit idle and wait for a request
			end
			MODIFIED : begin
				// we have a valid block, can service a request if the block index matches
				if (!reqInQ_empty && reqInQ_out.valid) begin
					// go ahead and service the request from the local block buffer
					if (reqInQ_out.addr[63:6] == current_block_index) begin
						// service a write operation
						if (reqInQ_out.isWrite) begin
							inMuxSel = 1'b1; // wrInput
							wr_specific_sector = 1'b1;
							reqInQ_deq = 1'b1;
						// service a read operation
						end else begin
							reqInQ_deq   = 1'b1;
							respOutQ_enq = 1'b1;
							respOutQ_in  = '{valid: 1, data: {448'b0,rd_output}, size: 8}; 
						end
					// a new block must be fetched, but this one is DIRTY, so it must be written back first
					end else begin
						// issue a write and go to CLEAN state
						reqOut[1] = '{valid: 1, isWrite: 1'b1, addr: {current_block_index,6'b00_0000} , data: wr_output, size: 64}; // write port
						if (reqOut_grant[1] == 1'b1) begin
							next_state = CLEAN;
						end
					end
				end
			end
			default : begin
				// should never be here
			end
		endcase
	end // FSM state transitions
	
endmodule
