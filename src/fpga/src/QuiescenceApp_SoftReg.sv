import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module QuiescenceApp_SoftReg
(
    // User clock and reset
    input                               clk,
    input                               rst, 

    input [AMI_APP_BITS-1:0]            srcApp,

    // Soft register interface
    input  SoftRegReq                   softreg_req,
    output SoftRegResp                  softreg_resp,

    // Connections to other apps
    output QuiescenceReq                slot0_quiescence_req,
    input  QuiescenceResp               slot0_quiescence_resp,
    output QuiescenceReq                slot1_quiescence_req,
    input  QuiescenceResp               slot1_quiescence_resp,
    output QuiescenceReq                slot2_quiescence_req,
    input  QuiescenceResp               slot2_quiescence_resp,
    output QuiescenceReq                slot3_quiescence_req,
    input  QuiescenceResp               slot3_quiescence_resp,
    output QuiescenceReq                slot4_quiescence_req,
    input  QuiescenceResp               slot4_quiescence_resp,
    output QuiescenceReq                slot5_quiescence_req,
    input  QuiescenceResp               slot5_quiescence_resp,
    output QuiescenceReq                slot6_quiescence_req,
    input  QuiescenceResp               slot6_quiescence_resp,
    output QuiescenceReq                slot7_quiescence_req,
    input  QuiescenceResp               slot7_quiescence_resp    
);
    
    // clk and debug counter
    wire[63:0] clk_counter;

    // Input queue for SoftReg
    wire             sr_inQ_empty;
    wire             sr_inQ_full;
    logic            sr_inQ_enq;
    logic            sr_inQ_deq;
    SoftRegReq       sr_inQ_in;
    SoftRegReq       sr_inQ_out;

    HullFIFO
    #(
        .TYPE                   (QUIESCENCE_SOFTREG_FIFO_Type),
        .WIDTH                  ($bits(SoftRegReq)),
        .LOG_DEPTH              (QUIESCENCE_SOFTREG_FIFO_Depth)
    )
    softReg_InQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (sr_inQ_enq),
        .data                   (sr_inQ_in),
        .full                   (sr_inQ_full),
        .q                      (sr_inQ_out),
        .empty                  (sr_inQ_empty),
        .rdreq                  (sr_inQ_deq)
    );    

    // Connections to softreg input interface
    assign sr_inQ_in   = softreg_req;
    assign sr_inQ_enq  = softreg_req.valid && !sr_inQ_full;
        
    Counter64 
    clk_counter64
    (
        .clk             (clk),
        .rst             (rst),
        .increment       (1'b1), // clock is always incrementing
        .count           (clk_counter)
    );
        
    // FSM states
    parameter IDLE        = 4'b0000;
    parameter DELIV_REQS  = 4'b0001;
    parameter AWAIT_RESP  = 4'b0010;
    parameter SEND_RESP   = 4'b0011;
    parameter CLEAN_UP1   = 4'b0100;
    parameter CLEAN_UP2   = 4'b0101;
    parameter CLEAN_UP3   = 4'b0110;
    parameter CLEAN_UP4   = 4'b0111;
    parameter CLEAN_UP5   = 4'b1000;
    
    // FSM registers
    reg[3:0]   current_state;
    logic[3:0] next_state;

    // FSM reset/update
    always@(posedge clk) begin : fsm_update
        if (rst) begin
            //wr_count <=  0;
            current_state  <= IDLE;
        end else begin
            //wr_count <= new_wr_count;
            current_state <= next_state;
        end
    end

    // Slot ID associated with each SoftReg req address
    parameter SLOT0_ADDR    = 64'h00;
    parameter SLOT1_ADDR    = 64'h08;
    parameter SLOT2_ADDR    = 64'h10;
    parameter SLOT3_ADDR    = 64'h18;
    parameter SLOT4_ADDR    = 64'h20;
    parameter SLOT5_ADDR    = 64'h28;
    parameter SLOT6_ADDR    = 64'h30;
    parameter SLOT7_ADDR    = 64'h38;
    parameter NOSLOT_ADDR   = 64'h40;
    
    // Quiescence client registers
    reg[63:0] curr_qresp_slot;
    logic curr_qresp_slot_we;
    logic reset_curr_qresp_slot;

    // Quiescence client update
    always@(posedge clk) begin : qreq_slot_update
        if (rst || reset_curr_qreq_slot) begin
            curr_qresp_slot <= NOSLOT_ADDR;
        end else begin
            if (curr_qresp_slot_we) begin
                curr_qresp_slot <= sr_inQ_out.addr;
            end // if (curr_qresp_slot_we)
        end // else: !if(rst)
    end // block: qreq_slot_update

    // Notify client app of any quiescence requests or checks
    assign slot0_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT0_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT0_ADDR));
    assign slot0_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot0_quiescence_req.data = 64'b1;

    assign slot1_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT1_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT1_ADDR));
    assign slot1_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot1_quiescence_req.data = 64'b1;

    assign slot2_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT2_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT2_ADDR));
    assign slot2_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot2_quiescence_req.data = 64'b1;

    assign slot3_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT3_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT3_ADDR));
    assign slot3_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot3_quiescence_req.data = 64'b1;

    assign slot4_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT4_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT4_ADDR));
    assign slot4_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot4_quiescence_req.data = 64'b1;

    assign slot5_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT5_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT5_ADDR));
    assign slot5_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot5_quiescence_req.data = 64'b1;

    assign slot6_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT6_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT6_ADDR));
    assign slot6_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot6_quiescence_req.data = 64'b1;

    assign slot7_quiescence_req.valid = ((current_state == DELIV_REQS) && (sr_inQ_out.addr == SLOT7_ADDR) && sr_inQ_out.valid) || ((current_state == AWAIT_RESP) && (curr_qresp_slot == SLOT7_ADDR));
    assign slot7_quiescence_req.isRequest = (current_state == DELIV_REQS) && sr_inQ_out.isWrite;
    assign slot7_quiescence_req.data = 64'b1;

    // Quiescence response registers
    //reg[63:0]  quiescence_check_result;
    //reg[63:0]  new_quiescence_check_result;
    //logic      quiescence_check_result_we;
    //
    //// Quiescence response update
    //always@(posedge clk) begin : response_value_update
    //    if (rst) begin
    //        quiescence_check_result <= 64'h0;
    //    end else begin
    //        if (quiescence_check_result_we) begin
    //            quiescence_check_result <= new_quiescence_check_result;
    //        end
    //    end
    //end

    // FSM update logic
    always_comb begin
        next_state = current_state;
        sr_inQ_deq    = 1'b0;
        softreg_resp = '{valid: 1'b0, data: 0};

        curr_qresp_slot_we = 1'b0;
        reset_curr_qresp_slot = 1'b0;

        //quiescence_check_result_we = 1'b0;
        //new_quiescence_check_result = quiescence_check_result;
        
        case (current_state)
            IDLE : begin
                if (!sr_inQ_empty) begin
                    next_state = DELIV_REQS;
                end else begin
                    next_state = IDLE;
                end
            end
            DELIV_REQS : begin
                if (!sr_inQ_empty) begin
                    sr_inQ_deq = 1'b1;
                    curr_qresp_slot_we = 1'b1;
                    if (!sr_inQ_out.isWrite) begin
                        next_state = AWAIT_RESP;
                    end else begin
                        next_state = DELIV_REQS;
                    end                    
                end else begin
                    // Waiting on a quiescence command to deliver
                    reset_curr_qreq_slot = 1'b1;  // Not interacting with any slot
                    next_state = DELIV_REQS;
                end
            end // case: DELIV_REQS          
            AWAIT_RESP : begin
                if (clk_counter % 100 == 0) begin
                    $display("Cycle %d QuiescenceApp %d: Awaiting responses", clk_counter, srcApp);
                end
                case (curr_qresp_slot)
                  SLOT0_ADDR : begin
                      if (slot0_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot0_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot0_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      // Wait until we can return a valid response
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT1_ADDR : begin
                      if (slot1_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot1_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot1_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT2_ADDR : begin
                      if (slot2_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot2_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot2_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT3_ADDR : begin
                      if (slot3_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot3_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot3_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT4_ADDR : begin
                      if (slot4_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot4_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot4_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT5_ADDR : begin
                      if (slot5_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot5_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot5_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT6_ADDR : begin
                      if (slot6_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot6_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot6_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  SLOT7_ADDR : begin
                      if (slot7_quiescence_resp.valid) begin
                          //new_quiescence_check_result = slot7_quiescence_resp.data;
                          //quiescence_check_result_we = 1'b1;
                          //next_state = SEND_RESP;
                          softreg_resp = '{valid: 1'b1, data: slot7_quiescence_resp.data};
                          next_state = DELIV_REQS;
                      end else begin
                          next_state = AWAIT_RESP;
                      end
                  end
                  default : begin
                      // TODO: fix this because it can get stuck in an infinite loop...
                      // Need to determine if there can be a case where the value of curr_qresp_slot
                      // can change while we are in AWAIT_RESP
                      next_state = AWAIT_RESP;
                  end
                endcase // case (curr_qresp_slot)
            end
            //SEND_RESP : begin
            //    softreg_resp = '{valid: 1'b1, data: quiescence_check_result};
            //    next_state = DELIV_REQS;
            //end
            default : begin
                next_state = current_state;
            end
        endcase
    end
    
endmodule
