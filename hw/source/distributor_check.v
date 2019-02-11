module distributor_check(
	input clk,
	input rst_n,
	
	input[143:0] data_out,
	input[15:0] token_pos,
	input[16:0] address,
	input[2:0] garbage,
	input start_lit,
	input[5:0] valid,
	
	output[3:0] state_out
);

reg[3:0] state;
reg[3:0] state_buff;
always@(posedge clk)begin
	if(~rst_n)begin
		state <= 4'd0;
	end else 
	case(state)
	4'd0:begin
		if(valid != 0)begin
			if(valid==6'h01 & data_out == 144'h040d0a090200203a01007c414c4943000000 & token_pos== 16'h9520 & address == 17'h00000 & garbage == 3'h3 & start_lit == 1'b0)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end

	4'd1:begin
		if(valid != 0)begin
			if(valid==6'h02 & data_out == 144'h494345275320414456454e54555245532049 & token_pos== 16'h0000 & address == 17'h0001a & garbage == 3'h0 & start_lit == 1'b1)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd2:begin
		if(valid != 0)begin
			if(valid==6'h04 & data_out == 144'h20494e20574f4e4445524c414e4401363e34 & token_pos== 16'h0002 & address == 17'h0002a & garbage == 3'h0 & start_lit == 1'b1)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd3:begin
		if(valid != 0)begin
			if(valid==6'h08 & data_out == 144'h3e34001944304c6577697320436172726f6c & token_pos== 16'h9400 & address == 17'h0003c & garbage == 3'h0 & start_lit == 1'b0)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd4:begin
		if(valid != 0)begin
			if(valid==6'h10 & data_out == 144'h6f6c6c01613a5f0088544845204d494c4c45 & token_pos== 16'h1480 & address == 17'h00060 & garbage == 3'h0 & start_lit == 1'b1)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd5:begin
		if(valid==6'h20 & valid != 0)begin
			if(data_out == 144'h4c454e4e49554d2046554c4352554d204544 & token_pos== 16'h0000 & address == 17'h0007d & garbage == 3'h0 & start_lit == 1'b1)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd15:begin ///wrong state
		state <= state;
	end
	endcase
	
	state_buff	<= state;
end

assign state_out = state_buff;

endmodule
