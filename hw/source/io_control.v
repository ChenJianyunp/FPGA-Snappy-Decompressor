/********************************************
File name: 		io_control
Author: 		Jianyu Chen
School: 		Delft Univsersity of Technology
Date:			10th Sept, 2018
Description:	The module to contol the input and output dataflow. 
				Each burst read will acquire 4K data, except the last burst read of a file (it can be less)
				Each burst write will write 4K data, also except the last one
				This module is to control the dataflow of axi protocal interface.
********************************************/
module io_control(
	input clk,
	input rst_n,
	
	input[63:0] src_addr,
	output rd_req,
	input rd_req_ack,
	output[7:0] rd_len,
	output[63:0] rd_address,
	
	input wr_valid,
	input wr_ready,
	input[63:0] des_addr,
	output wr_req,
	input wr_req_ack,
	output[7:0] wr_len,
	output[63:0] wr_address,
//	output wr_last,
	output bready,
	
	input done,
	input start,
	output idle,
	
	input[31:0] decompression_length,
	input[34:0] compression_length
);

/****************solved the read data*************/ 
reg[34:0] compression_length_r;   ///[34:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] rd_address_r;
reg[7:0] rd_len_r;
reg rd_req_r;
reg[2:0] rd_state;
always@(posedge clk)begin
	if(~rst_n)begin
		rd_req_r	<=1'b0;
		rd_state		<=3'd0;
	end else case(rd_state)
		3'd0:begin
			if(start)begin
				compression_length_r[34:6]	<=compression_length[34:6]+(compression_length[5:0]!=6'b0);
				rd_address_r			<=src_addr;
				rd_req_r				<=1'b0;
				rd_state				<=3'd1;
			end
		end
		3'd1:begin
			if(compression_length_r[34:6]<=29'd64)begin
					rd_len_r					<={2'd0,compression_length_r[11:6]-6'd1};
			end else begin
					rd_len_r					<=8'b11_1111;
					compression_length_r[34:6]	<=compression_length_r[34:6]-29'd64;
			end
			rd_state				<=3'd2;
			rd_req_r				<=1'b1;
		end
		3'd2:begin
			if(rd_req_ack)begin
				rd_address_r			<=rd_address_r+64'd4096;
				if(compression_length_r[34:6]<=29'd64)begin
					rd_state					<=3'd3;
					rd_len_r					<={2'd0,compression_length_r[11:6]-6'd1};
				end else begin
					rd_len_r					<=8'b11_1111;
					compression_length_r[34:6]	<=compression_length_r[34:6]-29'd64;
				end
			end
		end
		3'd3:begin
			if(rd_req_ack)begin
				rd_req_r				<=1'b0;
				rd_state				<=3'd0;
			end 
		end
		default:rd_state	<=3'd0;
	endcase
end

/****************write data*****************/
reg[31:0] decompression_length_r;   ///[32:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] wr_address_r;
reg[2:0] wr_state;
reg[7:0] wr_len_r;
reg wr_req_r;
always@(posedge clk)begin
	if(~rst_n)begin
		wr_state	<=3'd0;
		wr_req_r	<=1'b0;
	end else case(wr_state)
		3'd0:begin
			if(start)begin
				wr_state		<=3'd1;
				decompression_length_r[31:6]<=decompression_length[31:6]+(decompression_length[5:0]!=6'b0);
				wr_req_r		<=1'b0;
				wr_address_r	<=des_addr;
			end
		end
		3'd1:begin
			if(decompression_length_r[31:6]<=26'd64)begin
				wr_len_r	<={2'b0,decompression_length_r[11:6]};
			end else begin
				wr_len_r	<=8'b11_1111;
				decompression_length_r[31:6]	<=decompression_length_r[31:6]-26'd64;
			end
			wr_req_r	<=1'b1;
			wr_state	<=3'd2;
		end
		3'd2:begin
			if(wr_req_ack)begin
				wr_address_r	<=wr_address_r+64'd4096;
				if(decompression_length_r[31:6]<=26'd64)begin
					wr_len_r	<={2'b0,decompression_length_r[11:6]-8'b1};
					wr_state	<=3'd3;
				end else begin
					wr_len_r	<=8'b11_1111;
					decompression_length_r[31:6]	<=decompression_length_r[31:6]-26'd64;
				end
			end
		end
		3'd3:begin
			if(wr_req_ack)begin
				wr_req_r	<=1'b0;
				wr_state	<=3'd0;
			end
		end
	
		default:wr_state<=3'd0;
	endcase;
end

reg wr_last_r;
reg[31:0] decompression_length_minus;
reg[31:0] data_cnt;  
always@(posedge clk)begin
	if(~rst_n)begin
		data_cnt	<=32'b0;
	end else if(wr_valid & wr_ready)begin
		data_cnt	<= data_cnt+32'd64;
	end
	
	if(start)begin
		decompression_length_minus[31:6]<=decompression_length[31:6]+(decompression_length[5:0]!=6'b0)-32'b1;
	end
	
	if(~rst_n)begin
		wr_last_r	<=1'b0;
	end else if((data_cnt[11:6]==6'b11_1111)|(data_cnt[31:6]==decompression_length_minus[31:6]))begin
		wr_last_r	<=1'b1;
	end else begin
		wr_last_r	<=1'b0;
	end
	
end




reg idle_r;
reg bready_r;
always@(posedge clk)begin
	if(~rst_n)begin
		idle_r<=1'b1;
		bready_r<=1'b0;
	end else if(start)begin
		idle_r<=1'b0;
		bready_r<=1'b1;
	end else if(done)begin
		idle_r<=1'b1;
		bready_r<=1'b0;
	end
end

assign rd_address=rd_address_r;
assign rd_req=rd_req_r;
assign rd_len=rd_len_r;
assign idle=idle_r;

//assign wr_last=wr_last_r&wr_valid;
assign wr_address=wr_address_r;
assign wr_req=wr_req_r;
assign wr_len=wr_len_r;
//assign wr_len=8'h3f;
assign bready=bready_r;

endmodule