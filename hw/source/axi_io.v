/********************************************
File name: 		axi_io
Author: 		Jianyu Chen
School: 		Delft Univsersity of Technology
Date:			10th Sept, 2018
Description:	Top level of the axi protocal interface, containing the decompressor and an io_control module to control
				the input and output data flow from axi interface.
				NOTICE: if you want to migrate the decompressor to other platform or other interface. Only the decompressor
				module is needed.
********************************************/
module axi_io
#(
	parameter C_M_AXI_ADDR_WIDTH=64,
	C_M_AXI_DATA_WIDTH=512
)(
	input clk,
	input rst_n,
//////ports from axi_slave module
	input start, 
	output done,
	output idle,
	
	input job_valid,
	input[15:0] job_id,
	input[C_M_AXI_ADDR_WIDTH-1:0] src_addr,  //address to read from host memory
	input[C_M_AXI_ADDR_WIDTH-1:0] des_addr, ///address to write result to host memory
	input[31:0] compression_length,
	input[31:0] decompression_length,
/////////ports to read data from host memory
	output dma_rd_req,
    output[C_M_AXI_ADDR_WIDTH-1:0] dma_rd_addr,
    output[7:0] dma_rd_len,
    input dma_rd_req_ack,
    input[C_M_AXI_DATA_WIDTH-1:0] dma_rd_data,
    input dma_rd_data_valid,
	input dma_rd_data_last,
    output dma_rd_data_taken,
///////// ports to write data to host memory
	output dma_wr_req,
    output[C_M_AXI_ADDR_WIDTH-1:0] dma_wr_addr,
    output[7:0] dma_wr_len,
    input dma_wr_req_ack,
    output[C_M_AXI_DATA_WIDTH-1:0] dma_wr_data,
	output dma_wr_wvalid,
    output[63:0] dma_wr_data_strobe,
    output dma_wr_data_last,
    input dma_wr_ready,
    output dma_wr_bready,
    input dma_wr_done
	
	
);
wire dec_almostfull;

/********************
reorder the input and output data
data for dma is in this order: byte n,byte n-1,...,byte 1,byte 0,
data for decompressor is in a reverse order: byte 0,byte 1,...byte n-1,byte n
********************/
wire[C_M_AXI_DATA_WIDTH-1:0] dec_data_in,dec_data_out;
wire[C_M_AXI_ADDR_WIDTH-1:0] dec_byte_valid;
genvar i;
generate
	for(i=0;i<(C_M_AXI_DATA_WIDTH/8);i=i+1)begin
		assign dec_data_in[i*8+7:i*8+0]	= dma_rd_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8];
		assign dma_wr_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8]	= dec_data_out[i*8+7:i*8+0];
		assign dma_wr_data_strobe[C_M_AXI_ADDR_WIDTH-1-i]=dec_byte_valid[i];
	end
endgenerate
/*******************/


io_control io_control0
(
	.clk(clk),
	.rst_n(rst_n),
	
	.done(done),
	.start(start),
	.job_valid(job_valid),
	.idle(idle),
	
	.src_addr(src_addr),
	.rd_req(dma_rd_req),
	.rd_req_ack(dma_rd_req_ack),
	.rd_len(dma_rd_len),
	.rd_address(dma_rd_addr),
	.job_id(job_id),
	

	.des_addr(des_addr),
	.wr_req(dma_wr_req),
	.wr_req_ack(dma_wr_req_ack),
	.wr_address(dma_wr_addr),
	.bready(dma_wr_bready),
	
	.data_out(dec_data_out),
	.byte_valid_out(dec_byte_valid),
	.wr_valid(dma_wr_wvalid),
	.wr_ready(dma_wr_ready),
	.wr_data_last(dma_wr_data_last),///whether it is the last 64B of a burst
	
	.data_in(dec_data_in),
	.valid_in(dma_rd_data_valid),
	.rd_last(dma_rd_data_last),
	.data_ready(dec_almostfull), //whether decompressors are ready to receive data
	.decompression_length(decompression_length),
	.compression_length(compression_length)
);

assign dma_rd_data_taken=~dec_almostfull;

endmodule 
