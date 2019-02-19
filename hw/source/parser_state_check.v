module parser_state_check(
	input clk,
	input rst_n,
	
	input[2:0] state_in,
	input lit_valid,
	input copy_valid,
	input valid,
	
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
			if(state_in==3'd1 && lit_valid == 1'b0 && copy_valid == 1'b0)begin
				state <= state + 4'd1;
			end else begin
				state <= 4'd15; 
			end
		end
	end
	
	4'd1:begin
		if(state_in==3'd2 && lit_valid == 1'b0 && copy_valid == 1'b0)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
		end
	end
	
	4'd2:begin
		if(state_in==3'd2 && lit_valid == 1'b1 && copy_valid == 1'b0)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
		end
	end
	
	4'd3:begin
		if(state_in==3'd2 && lit_valid == 1'b0 && copy_valid == 1'b1)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
		end
	end
	
	4'd4:begin
		if(state_in==3'd2 && lit_valid == 1'b1 && copy_valid == 1'b0)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
		end
	end
	
	4'd5:begin
		if(state_in==3'd2 && lit_valid == 1'b0 && copy_valid == 1'b1)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
		end
	end
	
	4'd6:begin
		if(state_in==3'd1 && lit_valid == 1'b1 && copy_valid == 1'b0)begin
			state <= state + 4'd1;
		end else begin
			state <= 4'd15; 
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