////it is an fifo to store token with some necessary information to calculate
////format of input : | 18Byte data | 16bit token position | 16bit address | 1bit flag to check whether starts with literal content |
module queue_token(
	input clk,
	input rst_n,
	///////input and output of page
	input[143:0] data_in,
	input[15:0] position_in,
	input[16:0] address_in,
	input[1:0] garbage_in,
	input lit_flag_in,
	input wrreq,
	
	output[143:0] data_out,
	output[15:0] position_out,
	output[16:0] address_out,
	output[1:0] garbage_out,
	output lit_flag_out,
	output valid_out,
	////////control signal
	
	
	input rdreq,
	output isempty,
	
	output almost_full
);

reg valid_reg;
always@(posedge clk)begin
	if(~rst_n)begin
		valid_reg <=1'b0;
	end else if(isempty==1'b0 & valid_reg==1'b0)begin
		valid_reg <=1'b1;
	end else if(rdreq)begin
		valid_reg <= ~isempty;
	end
end

wire[179:0] q;
page_fifo pf0(
	.clk(clk),
	.srst(~rst_n),
	.din({data_in,position_in,address_in,garbage_in,lit_flag_in}),
	.wr_en(wrreq),
	.rd_en(isempty?1'b0:rdreq),
	.dout(q),
	.full(),
	.empty(isempty),
	.prog_full(almost_full),
	.valid(),
	.wr_rst_busy(),
	.rd_rst_busy()
);
assign data_out		=	q[179:36];
assign position_out	=	q[35:20];
assign address_out	=	q[19:3];
assign garbage_out	=	q[2:1];
assign lit_flag_out	=	q[0];
assign valid_out	=	valid_reg;

endmodule