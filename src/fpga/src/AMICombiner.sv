/*

    The role of this module is to mux requests from AOS and the application itself to the memory system
    Written by Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module AMICombiner
(
    // User clock and reset
    input                               clk,
    input                               rst, 

    input AMIRequest                    mem_reqs_aos_internal,
    output                              mem_req_grants_internal,
    output AMIResponse                  mem_resps_internal,
    input                               mem_resp_grants_internal,

    input AMIRequest                    mem_reqs_aos_app,
    output                              mem_req_grants_app,
    output AMIResponse                  mem_resps_app,
    input                               mem_resp_grants_app,

    output AMIRequest                   mem_reqs_aos,
    input                               mem_req_grants,
    input AMIResponse                   mem_resps,
    output                              mem_resp_grants

);

    wire             reqQ_empty[1:0];
    wire             reqQ_full[1:0];
    wire             reqQ_enq[1:0];
    wire             reqQ_deq[1:0];
    AMIRequest       reqQ_in[1:0];
    AMIRequest       reqQ_out[1:0];

    SoftFIFO
    #(
        .WIDTH					($bits(AMIRequest)),
        .LOG_DEPTH				(16)
    )
    amiRequestReqQ_from_internal
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
        .WIDTH					($bits(AMIRequest)),
        .LOG_DEPTH				(16)
    )
    amiRequestReqQ_from_app
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

    assign reqQ_in[0] = mem_reqs_aos_internal;
    assign reqQ_in[1] = mem_reqs_aos_app;

    // Writing into the Requests queues
    always_comb begin

        reqQ_enq[0] = 1'b0;
        reqQ_enq[1] = 1'b0;

        mem_req_grants_internal = 1'b0;
        mem_req_grants_app      = 1'b0;

        if (mem_reqs_aos_internal.valid && !reqQ_full[0]) begin
            reqQ_enq[0] = 1'b1;
            mem_req_grants_internal = 1'b1;
        end

        if (mem_reqs_aos_app.valid && !reqQ_full[1]) begin
            reqQ_enq[1] = 1'b1;
            mem_req_grants_app = 1'b1;
        end

        
        
    end

    // Output of the request queues
    always_comb begin

        reqQ_deq[0] = 1'b0;
        reqQ_deq[1] = 1'b0;

        mem_reqs_aos = 0;

        // Favor the internal queue
        if (!reqQ_empty[0] && reqQ_out[0].valid) begin
            mem_reqs_aos = reqQ_out[0];
            if (mem_req_grants) begin
                reqQ_deq[0] = 1'b1;
            end
        end else if (!reqQ_empty[1] && reqQ_out[1].valid) begin
            mem_reqs_aos = reqQ_out[1];
            if (mem_req_grants) begin
                reqQ_deq[1] = 1'b1;
            end
        end

    end

    // Currently don't handle internal reads, just pass through
    assign mem_resps_app   = mem_resps;
    assign mem_resp_grants = mem_resp_grants_app;

endmodule
