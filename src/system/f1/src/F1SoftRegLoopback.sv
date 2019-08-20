

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;


module F1SoftRegLoopback(

    input               clk,
    input               rst,

    input SoftRegReq    softreg_req,
    output logic        softreg_req_grant,

    output SoftRegResp  softreg_resp,
    input               softreg_resp_grant

);

    // FSM states
    parameter IDLE        = 4'b0000;
    parameter WAITING     = 4'b0001;
    parameter RESPONDING  = 4'b0010;

    
    // FSM registers
    reg[3:0]   current_state;
    logic[3:0] next_state;

    // FSM reset/update
    always@(posedge clk) begin : fsm_update
        if (rst) begin
            current_state  <= IDLE;
        end else begin
            current_state  <= next_state;
        end
    end

    // Wait Counter 
    reg[63:0]   wait_cntr;
    logic[63:0] new_wait_cntr;
    logic       wait_cntr_we;
    
    always@(posedge clk) begin : wait_cnt_update
        if (rst) begin
            wait_cntr  <= 0;
        end else if (wait_cntr_we) begin
            wait_cntr  <= new_wait_cntr;
        end
    end

    reg[63:0]   max_wait;
    logic[63:0] new_max_wait;
    
    always@(posedge clk) begin : max_wait_update
        if (rst) begin
            max_wait  <= 0;
        end else begin
            max_wait  <= new_max_wait;
        end
    end    
    
	// Combined response
	logic softreg_req_grant_write;
	logic softreg_req_grant_read;
	
	assign softreg_req_grant = softreg_req_grant_write | softreg_req_grant_read;
	
	// Response credits
	reg[63:0]   response_credits;
    logic       resp_credit_inc;
	logic       resp_credit_dec;
    
    always@(posedge clk) begin : max_response_credits
        if (rst) begin
            response_credits  <= 0;
        end else begin
		    if (resp_credit_dec && resp_credit_inc) begin
				response_credits <= response_credits;
			end else if (resp_credit_dec && !resp_credit_inc) begin
				$display("SoftReg Loopback: Losing response credit");
				response_credits <= response_credits - 1;
			end else if (!resp_credit_dec && resp_credit_inc) begin
				$display("SoftReg Loopback: Gaining response credit");
				response_credits <= response_credits + 1;
			end else begin
				response_credits <= response_credits;
			end
        end
    end  	
	
	
    // Credits for sending a response
	always_comb begin
		resp_credit_inc = 1'b0;
		softreg_req_grant_read = 1'b0;
		if ((softreg_req.valid == 1'b1) && (softreg_req.isWrite == 1'b0)) begin
			softreg_req_grant_read = 1'b1;
			resp_credit_inc = 1'b1;
			$display("SoftReg Loopback: Received Read request Addr: %x", softreg_req.addr);
		end
	end
	
    // FSM update logic
    always_comb begin
        next_state         = current_state;
        new_wait_cntr      = wait_cntr + 1;
        wait_cntr_we       = 1'b0;
        new_max_wait       = max_wait;
        softreg_req_grant_write  = 1'b0;
        softreg_resp.valid = 1'b0;
        softreg_resp.data  = wait_cntr;
        resp_credit_dec    = 1'b0;
		case (current_state)
            IDLE : begin
                if ((softreg_req.valid == 1'b1) && (softreg_req.isWrite == 1'b1)) begin
			        $display("SoftReg Loopback: Received Write request Addr: %x Data: %x", softreg_req.addr, softreg_req.data);
                    // accept the request
                    softreg_req_grant_write = 1'b1;
                    // store the data as the number of cycles to wait
                    new_max_wait      = softreg_req.data;
                    // reset the counter
                    wait_cntr_we  = 1'b1;
                    new_wait_cntr = {64{1'b0}};
                    // go to the waiting state
                    next_state = WAITING;
                end
            end
            WAITING : begin
				$display("SoftReg Loopback: Waited %d cycles of %d max wait", wait_cntr, max_wait);
                wait_cntr_we = 1'b1;
                new_wait_cntr = wait_cntr + 1;
                if (new_wait_cntr == max_wait) begin
					$display("SoftReg Loopback: Transitioning to RESPONDING state");
                    next_state = RESPONDING;
                end
            end
            RESPONDING : begin
				if (response_credits <= 0) begin
					$display("SoftReg Loopback: No response credit available");
					next_state <= RESPONDING;
				end else begin
					softreg_resp.valid = 1'b1;
					softreg_resp.data  = wait_cntr;
					if (softreg_resp_grant == 1'b1) begin
						resp_credit_dec = 1'b1;
						$display("SoftReg Loopback: Responding with Data: %x", softreg_resp.data);
						next_state = IDLE;
					end
				end
            end
            default : begin
                next_state = current_state;
            end
        endcase
    end

endmodule
