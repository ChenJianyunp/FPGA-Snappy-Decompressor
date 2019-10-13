/********************************************
File name:      axi_io
Author:         Jianyu Chen
School:         Delft Univsersity of Technology
Date:           10th Sept, 2018
Description:    Top level of the axi protocal interface, containing the decompressor and an io_control module to control
                the input and output data flow from axi interface.
                NOTICE: if you want to migrate the decompressor to other platform or other interface. Only the decompressor
                module is needed.
********************************************/
`timescale 1ns/1ps

module axi_io
#(
    parameter C_M_AXI_ADDR_WIDTH=64,
    C_M_AXI_DATA_WIDTH=512,
	NUM_DECOMPRESSOR=2		 //number of compressors
)(
    input clk,
    input rst_n,
//////ports from axi_slave module
    input start, 
    output done,
    output idle,
    output ready,
    
    input[C_M_AXI_ADDR_WIDTH-1:0] src_addr,  //address to read from host memory
    input[C_M_AXI_ADDR_WIDTH-1:0] des_addr, ///address to write result to host memory
    input[31:0] compression_length,
    input[31:0] decompression_length,
	input[15:0] job_id_i,
	input job_valid_i,
/////////ports to read data from host memory
    output dma_rd_req,
    output[C_M_AXI_ADDR_WIDTH-1:0] dma_rd_addr,
    output[7:0] dma_rd_len,
    input dma_rd_req_ack,
    input[C_M_AXI_DATA_WIDTH-1:0] dma_rd_data,
    input dma_rd_data_valid,
    output dma_rd_data_taken,
	input dma_rd_rlast,
///////// ports to write data to host memory
    output dma_wr_req,
    output[C_M_AXI_ADDR_WIDTH-1:0] dma_wr_addr,
    output[7:0] dma_wr_len,
    input dma_wr_req_ack,
    output[C_M_AXI_DATA_WIDTH-1:0] dma_wr_data,
    output dma_wr_wvalid,
    output[63:0] dma_wr_data_strobe,
    input dma_wr_ready,
    output dma_wr_bready,
    input dma_wr_wlast,
	input dma_wr_done
    
    
);
wire[NUM_DECOMPRESSOR-1:0] dec_almostempty;
wire[NUM_DECOMPRESSOR-1:0] dec_almostfull;
wire[NUM_DECOMPRESSOR-1:0] rd_dec_valid;
wire[NUM_DECOMPRESSOR-1:0] wr_dec_valid;
/********************
reorder the input and output data
data for dma is in this order: byte n,byte n-1,...,byte 1,byte 0,
data for decompressor is in a reverse order: byte 0,byte 1,...byte n-1,byte n
********************/
wire[C_M_AXI_DATA_WIDTH-1:0] dec_data_in,dec_data_out;
wire[NUM_DECOMPRESSOR-1:0] dec_data_out_all[C_M_AXI_DATA_WIDTH-1:0];
wire[C_M_AXI_ADDR_WIDTH-1:0] dec_byte_valid;
wire[C_M_AXI_ADDR_WIDTH-1:0] dec_wr_valid;
/***********axi_out_fifo*************/
wire axi_out_fifo_prog_full;
reg [C_M_AXI_DATA_WIDTH-1:0] dec_data_selected;
genvar i;
generate
    for(i=0;i<(C_M_AXI_DATA_WIDTH/8);i=i+1)begin
        assign dec_data_in[i*8+7:i*8+0]    = dma_rd_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8];
        assign dma_wr_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8]    = dec_data_out[i*8+7:i*8+0];
        assign dma_wr_data_strobe[C_M_AXI_ADDR_WIDTH-1-i]=dec_byte_valid[i];
    end
endgenerate
/*******************/
wire done_decompressor;
wire done_control;

genvar j;
generate 
for(j=0;j< NUM_DECOMPRESSOR;j=j+1)begin:gen_decompressor
    wire dec_rd_data_valid;
    wire dec_wr_ready;
    assign dec_rd_data_valid = rd_dec_valid[j] & dma_rd_data_valid;
    assign dec_wr_ready = dma_wr_ready & wr_dec_valid[j] & axi_out_fifo_prog_full;
    reg[31:0] compression_length_r;
    reg[31:0] decompression_length_r;
    always@(posedge clk)begin
	   if(job_valid_i && j == j[15:0])begin
		  compression_length_r	<= compression_length;
		  decompression_length_r	<= decompression_length;
	   end
    end
	decompressor d0(
		.clk(clk),
		.rst_n(rst_n),
		.data(dec_data_in),
		.valid_in(dec_rd_data_valid),
		.start(start),
		.compression_length({3'b0,compression_length_r}),
		.decompression_length(decompression_length_r),

		.data_fifo_almostempty(dec_almostempty[j]),
		.data_fifo_almostfull(dec_almostfull[j]),
    
		.done(done_decompressor),
//		.last(),
		.wr_ready(dec_wr_ready),
		.data_out(dec_data_out_all[j]),
		.byte_valid_out(dec_byte_valid),
		.valid_out(dec_wr_valid)
	);
end
endgenerate

io_control io_control0(
    .clk(clk),
    .rst_n(rst_n),
    
    .src_addr(src_addr),
    .rd_req(dma_rd_req),
    .rd_req_ack(dma_rd_req_ack),
    .rd_len(dma_rd_len),
	.rd_address(dma_rd_addr),
	.rd_axi_last(dma_rd_rlast),
	.rd_dec_valid(rd_dec_valid),
	.job_id_i(job_id_i),
	.job_valid_i(job_valid_i),
    
    .wr_valid(dma_wr_wvalid),
    .wr_ready(dma_wr_ready),
    .des_addr(des_addr),
    .wr_req(dma_wr_req),
    .wr_req_ack(dma_wr_req_ack),
    .wr_len(dma_wr_len),
    .wr_address(dma_wr_addr),
	.wr_axi_last(dma_wr_wlast),
	.wr_dec_valid(wr_dec_valid),
    .bready(dma_wr_bready),
    .bresp(dma_wr_done),
	
	.done_i(done_decompressor),
    .start(start),
    .idle(idle),
    .ready(ready),
    .done_out(done_control),
	.decompressor_almost_empty(dec_almostempty),
    
    .decompression_length(decompression_length),
    .compression_length({3'b0,compression_length})

);

assign dma_wr_wvalid = (dec_wr_valid & wr_dec_valid)!=0;

integer k;
always@(*)begin
    for(k=0;k<NUM_DECOMPRESSOR;k=k+1)begin:select_data_out
	   if(wr_dec_valid[k])begin
		   dec_data_selected <= dec_data_out_all[k];
		  disable select_data_out;
	   end
    end
end
assign dec_data_out = dec_data_selected;


/*
axi_out_fifo your_instance_name (
  .clk(clk),                  // input wire clk
  .srst(~rst_n),                // input wire srst
  .din(din),                  // input wire [512 : 0] din
  .wr_en(wr_en),              // input wire wr_en
  .rd_en(rd_en),              // input wire rd_en
  .dout(dout),                // output wire [512 : 0] dout
  .full(full),                // output wire full
  .empty(empty),              // output wire empty
  .valid(valid),              // output wire valid
  .prog_full(axi_out_fifo_prog_full),      // output wire prog_full
  .wr_rst_busy(wr_rst_busy),  // output wire wr_rst_busy
  .rd_rst_busy(rd_rst_busy)  // output wire rd_rst_busy
);
*/

assign dma_rd_data_taken    = (dec_almostfull & rd_dec_valid)!=0;
assign done                 = done_decompressor && (~done_control)==0;

endmodule 
