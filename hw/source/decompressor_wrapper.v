/****************************
Module name: 	decompressor_wrapper
Author:			  Jian Fang
Date:			    14th May, 2019
Function:		  Wrapper of the decompressor, able to reset register for multiple runs
****************************/
`timescale 1ns/1ps

module decompressor_wrapper(
		input clk,
		input rst_n,

    output last,  // Whether the data is the last one in a burst
    output done,  // Whether the decompression is done
    input  start, // Start the decompressor after the compression_length and decompression_length is set
                  // The user should set it to 1 for starting the decompressor, and need to set it back to 0 after 1 cycle
                  // TODO: add logic to only check the rising edge of the clk instead of checking '1';
                  //        transform it to only have 1 cycle in "HIGH"
	
		input[511:0] in_data, //The compressed data
		input in_data_valid, //Whether or not the data on the in_data port is valid.
		output in_data_ready, //Whether or not the decompressor is ready to receive data on its in_data port
	
		input[34:0] compression_length,		//length of the data before decompression (compressed data)
		input[31:0] decompression_length,	//length of the data after decompression (uncompressed data)
		input in_metadata_valid, //Whether or not the data on the compression_length and decompression_length ports is valid.
		output in_metadata_ready, //Whether or not the decompressor is ready to receive data on its compression_length and decompression_length ports.
	
		output[511:0] out_data, //The decompressed data
		output out_data_valid, //Whether or not the data on the out_data port is valid
    output[63:0] out_data_byte_valid,
		input out_data_ready //Whether or not the component following the decompressor is ready to receive data.
	);

wire dec_done;
wire almost_full;

reg start_reg;
always@(posedge clk)begin
	if(~rst_n)begin
		start_reg	<= 1'b0;
	end else begin
		start_reg	<= start;
	end
end

reg [34:0]com_len_reg;
reg [31:0]dec_len_reg;
reg in_metadata_ready_reg;
always@(posedge clk)begin
	if(~rst_n)begin
    com_len_reg <= 35'b0;
    dec_len_reg <= 32'b0;
	end else begin
		if(in_metadata_valid && in_metadata_ready_reg) begin
      com_len_reg <= compression_length;
      dec_len_reg <= decompression_length;
    end
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
    in_metadata_ready_reg <= 1'b1;
	end else begin
		if(in_metadata_ready_reg) begin // ready to get metadata
      if(in_metadata_valid) begin
        in_metadata_ready_reg <= 1'b0;  // lock the ready signal after the metadata is set
      end
    end
    else begin  // not ready to get the metadata, means it is busy. Unlock after the decompression is "done"
      if(dec_done)
        in_metadata_ready_reg <= 1'b1;
    end
	end
end


decompressor dec0(
  .clk(clk),
	.rst_n(rst_n),
	.data(in_data),
	.valid_in(in_data_valid),
	.start(start_reg),
	.compression_length(com_len_reg),
	.decompression_length(dec_len_reg),
	.wr_ready(out_data_ready),

	.data_fifo_almostfull(almost_full),
	
	.done(dec_done),
	.last(last),///whether it is the last 64B of a burst
	.data_out(out_data),
	.byte_valid_out(out_data_byte_valid),
	.valid_out(out_data_valid)
);

assign in_metadata_ready = in_metadata_ready_reg;
assign done = dec_done;
assign in_data_ready = ~almost_full;

endmodule 
