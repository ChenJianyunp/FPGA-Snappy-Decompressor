module handshake_counter#(
	parameter burst_len = 8'b11_1111
)(
	input clk,
	input rst_n,
	input start,
	input handshake,
	input last,
	
	output axi_last
);
reg[7:0] counter;
reg axi_last_r;
always@(posedge clk)begin
	if(~rst_n)begin
		counter <= 0;
		axi_last_r <= 1'b0;
	end else begin
		if(start | last)begin
			counter <= 0;
			axi_last_r <= 1'b0;
		end else if(handshake)begin
			if(counter == burst_len[7:0])begin
				axi_last_r	<= 1'b1;
				counter <= 0;
			end else begin
				axi_last_r	<= 1'b0;
				counter <= counter + 1;
			end
		end
	end
end
assign axi_last = axi_last_r | last;

endmodule

