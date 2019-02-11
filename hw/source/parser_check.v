module parser_check(
	input clk,
	input rst_n,
	
	input[63:0] data_out,
	input[7:0] byte_valid,
	input[8:0] address,
	input[15:0] valid,
	
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
			if(valid==16'h01 & data_out[63:48] == 16'h0d0a & byte_valid == 8'hc0)begin
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