import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module SoftRegCombiner
(
    // User clock and reset
    input                               clk,
    input                               rst,
    // Soft register interface
    input  SoftRegReq                   softreg_req_from_aos_internal,
    input  SoftRegReq                   softreg_req_from_aos_host,
    output SoftRegReq                   softreq_req_to_app,
    input  SoftRegResp                  softreg_resp_from_app,
    output SoftRegResp                  softreq_resp_to_aos
);

// Buffer requests from each source in case they collide in the same
// cycle since there is no backpressure mechanism

    wire             reqQ_empty[1:0];
    wire             reqQ_full[1:0];
    wire             reqQ_enq[1:0];
    wire             reqQ_deq[1:0];
    SoftRegReq       reqQ_in[1:0];
    SoftRegReq       reqQ_out[1:0];

    SoftFIFO
    #(
        .WIDTH					($bits(SoftRegReq)),
        .LOG_DEPTH				(16)
    )
    softRegReqQ_from_aos_internal
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(reqQ_enq[0]),
        .data                   (reqQ_in[0]),
        .full                   (reqQ_full[0]),
        .q                      (reqQ_out[0]),
        .empty                  (reqQ_empty[0]),
        .rdreq                  (reqQ_deq[0])
    );

    SoftFIFO
    #(
        .WIDTH					($bits(SoftRegReq)),
        .LOG_DEPTH				(16)
    )
    softRegReqQ_from_aos_host
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(reqQ_enq[1]),
        .data                   (reqQ_in[1]),
        .full                   (reqQ_full[1]),
        .q                      (reqQ_out[1]),
        .empty                  (reqQ_empty[1]),
        .rdreq                  (reqQ_deq[1])
    );

    assign reqQ_in[0] = softreg_req_from_aos_internal;
    assign reqQ_in[1] = softreg_req_from_aos_host;

    assign reqQ_enq[0] = softreg_req_from_aos_internal.valid;
    assign reqQ_enq[1] = softreg_req_from_aos_host.valid;

    // Statically favor internally generated requests
    always_comb begin
        if (!reqQ_empty[0]) begin
            // Pending internal requests
            reqQ_deq[0] = 1'b1;
            softreq_req_to_app.valid   = 1'b1;
            softreq_req_to_app.isWrite = reqQ_out[0].isWrite;
            softreq_req_to_app.addr    = reqQ_out[0].addr;
            softreq_req_to_app.data    = reqQ_out[0].data;
        end else if (!reqQ_empty[1]) begin
            // Pending request from host
            reqQ_deq[1] = 1'b1;
            softreq_req_to_app.valid   = 1'b1;
            softreq_req_to_app.isWrite = reqQ_out[1].isWrite;
            softreq_req_to_app.addr    = reqQ_out[1].addr;
            softreq_req_to_app.data    = reqQ_out[1].data;
        end else begin // both empty
            reqQ_deq[0] = 1'b0;
            reqQ_deq[1] = 1'b0;
            softreq_req_to_app.valid   = 1'b0;
            // Zero out to not leak any information (does it matter per app tho? better safe than sorry)
            softreq_req_to_app.isWrite = 1'b0;
            softreq_req_to_app.addr    = 0;
            softreq_req_to_app.data    = 0;
        end
    end    
    
// Currently OS doesn't generate SoftReqResp on the app's behalf
assign softreg_resp_from_app = softreq_resp_to_aos;

endmodule
