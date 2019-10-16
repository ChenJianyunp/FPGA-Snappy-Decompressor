/********************************************
File name:      io_control
Author:         Jianyu Chen
School:         Delft Univsersity of Technology
Date:           10th Sept, 2018
Description:    The module to contol the input and output dataflow. 
                Each burst read will acquire 4K data, except the last burst read of a file (it can be less)
                Each burst write will write 4K data, also except the last one
                This module is to control the dataflow of axi protocal interface.
********************************************/
`timescale 1ns/1ps



module io_control#(
	parameter NUM_DECOMPRESSOR = 2
)(
    input clk,
    input rst_n,

    input[63:0] src_addr,
    output rd_req,
    input rd_req_ack,
    output[7:0] rd_len,
    output[63:0] rd_address,
	input rd_axi_last,
	output[NUM_DECOMPRESSOR-1:0] rd_dec_valid,
	input[15:0] job_id_i,
	input job_valid_i,
	
    input wr_valid,
    input wr_ready,
    input[63:0] des_addr,
    output wr_req,
    input wr_req_ack,
    output[7:0] wr_len,
    output[63:0] wr_address,
	input wr_axi_last,
	output[NUM_DECOMPRESSOR-1:0] wr_dec_valid,
    output bready,
    input bresp,

    input[NUM_DECOMPRESSOR-1:0] done_i,
    input start,
    output idle,
    output ready,
    output done_out,
	
	input[NUM_DECOMPRESSOR-1 :0] decompressor_almost_empty,

    input[31:0] decompression_length,
    input[34:0] compression_length
);



/****************solved the read data*************/ 
reg[34:6] compression_length_temp;   ///[34:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] rd_address_temp;
reg[7:0] rd_len_r;
reg rd_req_r;
reg[2:0] rd_state;
reg[NUM_DECOMPRESSOR-1 :0] read_done_r;
reg read_done_temp;
reg[5:0] rd_record; //record reading for which decompressor 
reg[NUM_DECOMPRESSOR-1:0] rd_round_robin;
reg[34:6] compression_length_r[NUM_DECOMPRESSOR-1:0];
reg[63:0] rd_address_r[NUM_DECOMPRESSOR-1:0];

reg[NUM_DECOMPRESSOR-1:0] rd_dec_select;
wire rd_select_fifo_full,rd_select_fifo_empty;
integer i;
localparam ZERO = 0;

axi_id_fifo 
#(
	.NUM_DECOMPRESSOR(NUM_DECOMPRESSOR)
)rd_select_fifo
(
    .clk(clk),
    .rst_n(rst_n),
	
	.select_in(rd_dec_select), 
	.wr_en(rd_req_ack & rd_req_r),
	
	.rd_en(rd_axi_last),
	.select_out(rd_dec_valid),
	.full(rd_select_fifo_full),
	.empty(rd_select_fifo_empty)
);

always@(posedge clk)begin
    if(~rst_n)begin
        rd_req_r        <= 1'b0;
        rd_state        <= 3'd0;
        read_done_r     <= 0;
		rd_round_robin	<= 1;
    end else case(rd_state)
        3'd0:begin
            if(job_valid_i)begin
                //Round the length to the upper 64*n, n is an integer. Because the bandwidth is 64Byte
                if(compression_length[5:0]!=6'b0)begin
                    compression_length_r[job_id_i]  <= compression_length[34:6] + 29'd1;
                end else begin
                    compression_length_r[job_id_i]  <= compression_length[34:6];
                end
				rd_address_r[job_id_i]            <= src_addr;
                
            end
			if(start)begin //if receive all the starts signal
				rd_state                <= 3'd1;
			end
			read_done_r     <= 0;
			rd_req_r        <= 1'b0;
        end
		
		3'd1:begin //choose an decompressor
			if((rd_round_robin & decompressor_almost_empty & (~read_done_r)) != 0)begin
				rd_state    <= 3'd2;
			end
			for(i =0;i<NUM_DECOMPRESSOR;i=i+1)begin:select_read
				if(rd_round_robin[i] == 1'b1)begin
					compression_length_temp	<= compression_length_r[i];
					rd_address_temp			<= rd_address_r[i];
					rd_record		<= i;
					disable select_read;
				end
			end
			rd_round_robin <= {rd_round_robin[0],rd_round_robin[NUM_DECOMPRESSOR-1:1]}; //shift
		end
		
        3'd2:begin // the state to read the first 4KB chunk of the 64KB Snappy block
            //If the block is greater than 4KB (64*64), read a 4KB block. If not, read all the block
            if(compression_length_temp[34:6]<=29'd64)begin
                rd_len_r                    <= {2'd0,compression_length_temp[11:6]-6'd1};
                compression_length_r[rd_record]  <= 29'd0;
				read_done_temp				<= 1'b1;
            end else begin
                rd_len_r                    <= 8'b11_1111;
                compression_length_r[rd_record]    <= compression_length_temp[34:6]-29'd64;
				read_done_temp				<= 1'b0;
            end
			

            rd_dec_select	<= (1<<rd_record);
			if(~rd_select_fifo_full)begin
				rd_req_r                	<= 1'b1;
				rd_state                    <= 3'd3;
			end
			
        end
        3'd3:begin
            if(rd_req_ack)begin
				read_done_r[rd_record]	<= read_done_temp;
				rd_req_r                <= 1'b0;
				rd_state                <= 3'd4;
				rd_address_r[rd_record]		<= rd_address_temp+64'd4096;
            end
        end
        3'd4:begin//check whether all reading is done
            if((~read_done_r) == 0)begin // if all reading is done
				rd_state        <= 3'd0;
			end else begin
				rd_state        <= 3'd1;
			end
        end

        default:rd_state    <= 3'd0;
    endcase
end


/****************write data*****************/
reg[31:6] decompression_length_r[NUM_DECOMPRESSOR-1:0];   ///[32:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] wr_address_r[NUM_DECOMPRESSOR-1:0];
reg[NUM_DECOMPRESSOR-1:0] wr_round_robin;
reg[NUM_DECOMPRESSOR-1:0] write_done_r;
reg[31:6] decompression_length_temp;   ///[34:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] wr_address_temp;
reg[2:0] wr_state;
reg[7:0] wr_len_r;
reg wr_req_r;
reg write_done_temp;
reg[5:0] wr_record; //record reading for which decompressor 
reg[63:0] wr_req_count;
reg[63:0] wr_done_count;    // a counter to count the write_done of the data write before the done signal is sent.
reg done_out_r;
reg wr_axi_last_r;

reg[NUM_DECOMPRESSOR-1:0] wr_dec_select;
wire wr_select_fifo_full,wr_select_fifo_empty;

wire debug1,debug2;
axi_id_fifo #(
	.NUM_DECOMPRESSOR(NUM_DECOMPRESSOR)
)wr_select_fifo
(
    .clk(clk),
    .rst_n(rst_n),
	
	.select_in(wr_dec_select), 
	.wr_en(wr_req_ack & wr_req_r),
	
	.rd_en(wr_axi_last),
	.select_out(wr_dec_valid),
	.full(wr_select_fifo_full),
	.empty(wr_select_fifo_empty)
);

always@(posedge clk)begin
    if(~rst_n)begin
        wr_state        <= 3'd0;
        wr_req_r        <= 1'b0;
        wr_req_count    <= 64'b0;
        done_out_r        <= 1'b0;
		wr_round_robin	<= 1;
		write_done_r	<= 0;
    end else case(wr_state)
        3'd0:begin                // initial state
            if(job_valid_i)begin
                //similar to the read case
                if(decompression_length[5:0]!=6'b0)begin
					decompression_length_r[job_id_i]  <= decompression_length[31:6] + 29'd1;
                end else begin
                    decompression_length_r[job_id_i]    <= decompression_length[31:6];
                end
				wr_address_r[job_id_i]    <= des_addr;
			end
			if(start)begin //if receive all the starts signal
				wr_state        <= 3'd1;
				done_out_r        <= 1'b0;
			end
            wr_req_r        <= 1'b0;
                	
        end
		
		3'd1:begin //choose an decompressor
			if((wr_round_robin & (~write_done_r)) != 0)begin
				wr_state	<= 3'd2;
			end
			
			for(i =0;i<NUM_DECOMPRESSOR;i=i+1)begin:select_write
				if(wr_round_robin[i] == 1'b1)begin
					decompression_length_temp	<= decompression_length_r[i];
					wr_address_temp			<= wr_address_r[i];
					wr_record		<= i;
					disable select_write;
				end
			end
			wr_round_robin <= {wr_round_robin[0],wr_round_robin[NUM_DECOMPRESSOR-1:1]}; //shift
		end 
		
        3'd2:begin                // state for sending the first 4K block
            if(decompression_length_temp[31:6]<=26'd64)begin
                wr_len_r                        <= {2'b0,decompression_length_temp[11:6]-6'd1};
                decompression_length_r[wr_record]    <= 26'd0;
                write_done_temp					<= 1'b1;
            end else begin
                wr_len_r                        <= 8'b11_1111;
                decompression_length_r[wr_record]    <= decompression_length_temp[31:6]-26'd64;
                write_done_temp					<= 1'b0;
            end
            
			
			wr_dec_select		<= (1<<wr_record);
			if(~wr_select_fifo_full)begin
				wr_req_r    				<= 1'b1;
				wr_state                    <= 3'd3;
			end
			wr_req_r    				<= 1'b1;
			wr_state                    <= 3'd3;
        end
				
        3'd3:begin                
            if(wr_req_ack)begin
                write_done_r[wr_record]	<= write_done_temp;
                wr_req_r        		<= 1'b0;
                wr_state        		<= 3'd4;
                wr_address_r[wr_record] <= wr_address_temp+64'd4096;
            end
        end

        3'd4:begin
            if(((~write_done_r) ==ZERO[NUM_DECOMPRESSOR-1:0]) && ((~read_done_r) == ZERO[NUM_DECOMPRESSOR-1:0])) begin    //write request ack count equal to write data ack count and the read is done
                done_out_r  <= 1'b1;
                wr_state    <= 3'd0;
            end else begin
				wr_state    <= 3'd1;
			end
        end

        default:wr_state    <= 3'd0;
    endcase
end

reg idle_r;
reg bready_r;
reg ready_r;
always@(posedge clk)begin
    if(~rst_n)begin
        idle_r      <= 1'b1;
        bready_r    <= 1'b0;
    end else if(start)begin
        idle_r      <= 1'b0;
        bready_r    <= 1'b1;
    end else if(((~done_i) == ZERO[NUM_DECOMPRESSOR-1:0]) && done_out_r)begin
        idle_r      <= 1'b1;
        bready_r    <= 1'b0;
    end
end

always@(posedge clk) begin
    if(~rst_n)begin
        ready_r    <= 1'b0;
    end else begin
        ready_r    <= 1'b1;
    end
end

assign rd_address   = rd_address_temp;
assign rd_req       = rd_req_r;
assign rd_len       = rd_len_r;
assign idle         = idle_r;
assign ready        = ready_r;

assign wr_address   = wr_address_temp;
assign wr_req       = wr_req_r;
assign wr_len       = wr_len_r;
assign bready       = bready_r;

assign done_out     = done_out_r;

endmodule
