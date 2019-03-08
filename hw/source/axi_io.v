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
    output ready,

    output after_done_o,
    output after_all_wr_ack_o,
    output after_rd_done_o,
    output after_first_wr_ack_o,
    output after_wr_data_sent_o,
    output after_first_wr_rqt_ack_o,
    output after_first_wr_rqt_o,
    output after_first_rd_rqt_ack_o,
    output after_first_rd_rqt_o,
    output after_start_o,
    output after_first_wr_ready_o,
    output after_first_wr_valid_o,
    output[3:0] preparser_state_out_o,
    output after_first_rd_ready_o,
    output after_first_rd_valid_o,
    output after_first_data_read_o,
    output after_df_valid_o,
    output after_preparser_valid_o,
    output after_queue_token_valid_o,
    output after_distributor_valid_o,
    output[15:0] data_out_valid_in_o,
    output[63:0] byte_valid_out_o,
    output[3:0] distributor_state_out_o,
    output[3:0] parser_state_out_o,
    output[3:0] parser_state_check_out_o,
    output[3:0] lit_fifo_wr_en_out_o,
    output[3:0] lit_ramselect_o,
    output[3:0] fifo_error_in_o,
    
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
        assign dec_data_in[i*8+7:i*8+0]    = dma_rd_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8];
        assign dma_wr_data[C_M_AXI_DATA_WIDTH-i*8-1:C_M_AXI_DATA_WIDTH-i*8-8]    = dec_data_out[i*8+7:i*8+0];
        assign dma_wr_data_strobe[C_M_AXI_ADDR_WIDTH-1-i]=dec_byte_valid[i];
    end
endgenerate
/*******************/
wire done_decompressor;
wire done_control;

decompressor d0(
    .clk(clk),
    .rst_n(rst_n),
    .data(dec_data_in),
    .valid_in(dma_rd_data_valid),
    .start(start),
    .compression_length({3'b0,compression_length}),
    .decompression_length(decompression_length),
    .wr_ready(dma_wr_ready),

    .data_fifo_almostfull(dec_almostfull),
    .after_wr_data_sent_o(after_wr_data_sent_o),
    .after_first_wr_ready_o(after_first_wr_ready_o),
    .after_first_wr_valid_o(after_first_wr_valid_o),
    .preparser_state_out_o(preparser_state_out_o),
    .after_df_valid_o(after_df_valid_o),
    .after_preparser_valid_o(after_preparser_valid_o),
    .after_queue_token_valid_o(after_queue_token_valid_o),
    .after_distributor_valid_o(after_distributor_valid_o),
    .data_out_valid_in_o(data_out_valid_in_o),
    .byte_valid_out_o(byte_valid_out_o),
    .distributor_state_out_o(distributor_state_out_o),
    .parser_state_out_o(parser_state_out_o),
    .parser_state_check_out(parser_state_check_out_o),
    .lit_fifo_wr_en_out(lit_fifo_wr_en_out_o),
    .lit_ramselect_out(lit_ramselect_o),
    .fifo_error_in_out(fifo_error_in_o),
    
    .done(done_decompressor),
    .last(dma_wr_data_last),
    .data_out(dec_data_out),
    .byte_valid_out(dec_byte_valid),
    .valid_out(dma_wr_wvalid)
);
io_control io_control0(
    .clk(clk),
    .rst_n(rst_n),
    
    .src_addr(src_addr),
    .rd_req(dma_rd_req),
    .rd_req_ack(dma_rd_req_ack),
    .rd_len(dma_rd_len),
    .done_i(done_decompressor),
    .start(start),
    .idle(idle),
    .ready(ready),
    .rd_address(dma_rd_addr),
    .done_out(done_control),

    .after_all_wr_ack_o(after_all_wr_ack_o),
    .after_rd_done_o(after_rd_done_o),
    .after_first_wr_ack_o(after_first_wr_ack_o),
    .after_first_wr_rqt_ack_o(after_first_wr_rqt_ack_o),
    .after_first_wr_rqt_o(after_first_wr_rqt_o),
    .after_first_rd_rqt_ack_o(after_first_rd_rqt_ack_o),
    .after_first_rd_rqt_o(after_first_rd_rqt_o),
    
    .wr_valid(dma_wr_wvalid),
    .wr_ready(dma_wr_ready),
    .des_addr(des_addr),
    .wr_req(dma_wr_req),
    .wr_req_ack(dma_wr_req_ack),
    .wr_len(dma_wr_len),
    .wr_address(dma_wr_addr),
    .bready(dma_wr_bready),
    .bresp(dma_wr_done),
    
    .decompression_length(decompression_length),
    .compression_length({3'b0,compression_length})

);

// for debug only
reg after_start_r;
reg after_first_rd_ready_r;
reg after_first_rd_valid_r;
reg after_first_data_read_r;

always@(posedge clk)begin
    if(~rst_n)begin
        after_start_r   <= 1'b0;
    end else if(start)begin
        after_start_r   <= 1'b1;
    end
end

always@(posedge clk)begin
    if(~rst_n)begin
        after_first_rd_ready_r      <= 1'b0;
        after_first_rd_valid_r      <= 1'b0;
        after_first_data_read_r     <= 1'b0;
    end else begin
        if(dma_rd_data_valid)begin
            after_first_rd_valid_r      <= 1'b1;
        end
        if(dma_rd_data_taken)begin
            after_first_rd_ready_r      <= 1'b1;
        end
        if(dma_rd_data_valid && dma_rd_data_taken)begin
            after_first_data_read_r     <= 1'b1;
        end
    end
end


assign after_start_o            = after_start_r;
assign after_first_rd_ready_o   = after_first_rd_ready_r;
assign after_first_rd_valid_o   = after_first_rd_valid_r;
assign after_first_data_read_o  = after_first_data_read_r;
// end of for debug only

assign dma_rd_data_taken    = ~dec_almostfull;
assign done                 = done_decompressor && done_control;
assign after_done_o         = done;

endmodule 
