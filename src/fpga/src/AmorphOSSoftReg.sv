/*
	
	Top level module virtualizing the Soft Reg interface
	
	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module AmorphOSSoftReg (
    // User clock and reset
    input                               clk,
    input                               rst,
	input								app_enable[AMI_NUM_APPS-1:0],
	// Interface to Host
	input  SoftRegReq					softreg_req,
	output SoftRegResp					softreg_resp,
	// Virtualized interface each app
	output SoftRegReq					app_softreg_req[AMI_NUM_APPS-1:0],
	input  SoftRegResp					app_softreg_resp[AMI_NUM_APPS-1:0]	
);

	// Route the request to the proper app (or the OS)
	genvar app_num;
	generate
		logic valid_route[AMI_NUM_APPS-1:0];
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : app_mux_logic
			if (USING_F1 == 1) begin
				// F1 softreg address format
				// Bits 15-13 are the app select
				// Bits 12-0 are usable by the app
				// Bits 2-0 are always 0 because we're 64-bit aligned
				assign valid_route[app_num]    = (softreg_req.valid && (softreg_req.addr[15:13] == app_num[2:0])); // TODO: Modify upper bits to be the split select bit
				assign app_softreg_req[app_num].valid   = valid_route[app_num] ? 1'b1 : 1'b0;
				assign app_softreg_req[app_num].isWrite = valid_route[app_num] ? softreg_req.isWrite : 1'b0;
				assign app_softreg_req[app_num].addr    = valid_route[app_num] ? {{16'h0000},{3'b000}, softreg_req.addr[12:0]} : 0; // remove the app select
				assign app_softreg_req[app_num].data    = valid_route[app_num] ? softreg_req.data : 0;			
			end else begin
				assign valid_route[app_num]    = (softreg_req.valid && (softreg_req.addr[31:(32-VIRT_SOFTREG_RESV_BITS)] == app_num[VIRT_SOFTREG_RESV_BITS-1:0]));
				assign app_softreg_req[app_num].valid   = valid_route[app_num] ? 1'b1 : 1'b0;
				assign app_softreg_req[app_num].isWrite = valid_route[app_num] ? softreg_req.isWrite : 1'b0;
				assign app_softreg_req[app_num].addr    = valid_route[app_num] ? {{VIRT_SOFTREG_RESV_BITS{1'b0}},softreg_req.addr[31-VIRT_SOFTREG_RESV_BITS:0]} : 0;
				assign app_softreg_req[app_num].data    = valid_route[app_num] ? softreg_req.data : 0;
			end
		end
	endgenerate

	// Buffer responses from the apps and arbitrate their submission back to the host

	// Response queue
	wire             reqQ_empty[AMI_NUM_APPS-1:0];
	wire             reqQ_full[AMI_NUM_APPS-1:0];
	wire             reqQ_enq[AMI_NUM_APPS-1:0];
	wire             reqQ_deq[AMI_NUM_APPS-1:0];
	SoftRegResp      reqQ_in[AMI_NUM_APPS-1:0];
	SoftRegResp      reqQ_out[AMI_NUM_APPS-1:0];

	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : softreg_resp_queues
			if (USE_SOFT_FIFO) begin : SoftFIFOs
				SoftFIFO
				#(
					.WIDTH					($bits(SoftRegResp)),
					.LOG_DEPTH				(VIRT_SOFTREG_RESP_Q_SIZE)
				)
				softRegRespQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(reqQ_enq[app_num]),
					.data                   (reqQ_in[app_num]),
					.full                   (reqQ_full[app_num]),
					.q                      (reqQ_out[app_num]),
					.empty                  (reqQ_empty[app_num]),
					.rdreq                  (reqQ_deq[app_num])
				);
			end else begin : FIFOs
				FIFO
				#(
					.WIDTH					($bits(SoftRegResp)),
					.LOG_DEPTH				(VIRT_SOFTREG_RESP_Q_SIZE)
				)
				softRegRespQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(reqQ_enq[app_num]),
					.data                   (reqQ_in[app_num]),
					.full                   (reqQ_full[app_num]),
					.q                      (reqQ_out[app_num]),
					.empty                  (reqQ_empty[app_num]),
					.rdreq                  (reqQ_deq[app_num])
				);
			end
			// Writing into the queues
			assign reqQ_in[app_num]  =  app_softreg_resp[app_num];
			assign reqQ_enq[app_num] = (app_enable[app_num] == 1'b1) && app_softreg_resp[app_num].valid && !reqQ_full[app_num]; // potential to drop an incoming response if queue is backed up 
		end
	endgenerate

	// Arbitrate which queue we submit from
	logic[AMI_NUM_APPS-1:0] req;
	wire[AMI_NUM_APPS-1:0]  grant;
	
	RRWCArbiter 
	#(
		.N(AMI_NUM_APPS)
	)
	softreq_resp_arbiter
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req(req),
		// Grant vector
		.grant(grant)
	);

	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : softreg_resp_arb_queues
			assign req[app_num]      = reqQ_out[app_num].valid && !reqQ_empty[app_num];
			assign reqQ_deq[app_num] = grant[app_num];
		end
	endgenerate
	
	// Mux out the correct output
	SoftRegResp tmp_out_resp;
	/*OneHotMux
	#(
		.WIDTH($bits(SoftRegResp)),
		.N(AMI_NUM_APPS)
	)
	resp_select_mux
	(
		.data(reqQ_out),
		.select(grant),
		.out(tmp_out_resp)
	);*/
	localparam MUX_BITS = AMI_NUM_APPS > 1 ? $clog2(AMI_NUM_APPS) : 1;
	logic[MUX_BITS-1:0] mux_select;
	OneHotEncoder
	#(
		.ONE_HOTS(AMI_NUM_APPS),
		.MUX_SELECTS(MUX_BITS)
	)
	one_hot_encoder
	(
		.one_hots(grant),
		.mux_select(mux_select)
	);

	always_comb begin
		tmp_out_resp = reqQ_out[0];
		if (AMI_NUM_APPS == 1) begin
			tmp_out_resp = reqQ_out[0];
		end else if (AMI_NUM_APPS == 2) begin
			if (mux_select == 1'b1) begin
				tmp_out_resp = reqQ_out[1];
			end else begin 
				tmp_out_resp = reqQ_out[0];
			end
		end else if (AMI_NUM_APPS == 4) begin
			if (mux_select == 2'b11) begin
				tmp_out_resp = reqQ_out[3];
			end else if (mux_select == 2'b10) begin 
				tmp_out_resp = reqQ_out[2];
			end else if (mux_select == 2'b01) begin
				tmp_out_resp = reqQ_out[1];
			end else begin
				tmp_out_resp = reqQ_out[0];
			end
		end else if (AMI_NUM_APPS == 8) begin
			if (mux_select == 3'b111) begin
				tmp_out_resp = reqQ_out[7];
			end else if (mux_select == 3'b110) begin
				tmp_out_resp = reqQ_out[6];
			end else if (mux_select == 3'b101) begin
				tmp_out_resp = reqQ_out[5];
			end else if (mux_select == 3'b100) begin
				tmp_out_resp = reqQ_out[4];
			end else if (mux_select == 3'b011) begin
				tmp_out_resp = reqQ_out[3];
			end else if (mux_select == 3'b010) begin
				tmp_out_resp = reqQ_out[2];
			end else if (mux_select == 3'b001) begin
				tmp_out_resp = reqQ_out[1];
			end else begin // 3'b000
				tmp_out_resp = reqQ_out[0];
			end
		end
		//assign tmp_out_resp = reqQ_out[mux_select];
	end

	assign softreg_resp.valid = (|grant) && tmp_out_resp.valid;
	assign softreg_resp.data = tmp_out_resp.data;
	
endmodule