`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/14/2019 12:11:06 AM
// Design Name: 
// Module Name: axi_id_fifo
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module axi_id_fifo#(
		parameter NUM_DECOMPRESSOR = 2
)
(
    input clk,
    input rst_n,
	
	input[NUM_DECOMPRESSOR-1:0] select_in, 
	input wr_en,
	
	output rd_en,
	output[NUM_DECOMPRESSOR-1:0] select_out,
	output full,
	output empty
);
reg[7:0] data[NUM_DECOMPRESSOR-1:0];
reg[2:0] rd_ptr,wr_ptr;
reg[NUM_DECOMPRESSOR-1:0] select_out_r;
always@(posedge clk)begin
	if(~rst_n)begin
		rd_ptr	<= 0;
		wr_ptr	<= 0;
	end else begin
		if(wr_en)begin
			if(wr_ptr == 7)begin
				wr_ptr	<= 0;
			end else begin
				wr_ptr	<= wr_ptr + 1;
			end
			data[wr_ptr]	<= select_in;
		end
		
		if(rd_en)begin
			if(rd_ptr == 7)begin
				rd_ptr	<= 0;
			end else begin
				rd_ptr	<= rd_ptr + 1;
			end
		end
	end
//	select_out_r	<= data[rd_ptr];
end

assign empty	= (wr_ptr == rd_ptr);
assign full		= (wr_ptr == rd_ptr-1); 
assign select_out	= data[rd_ptr];

endmodule
