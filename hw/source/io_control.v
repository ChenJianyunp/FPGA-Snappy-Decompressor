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
module io_control
#(	parameter C_M_AXI_ADDR_WIDTH=64,
	C_M_AXI_DATA_WIDTH=512,
	NUM_DECOMPRESSOR = 3,
	NUM_DECOMPRESSOR_LOG = 2
)
(
	input clk,
	input rst_n,
	
	input done,
	input start,
	input job_valid,
	output idle,
	
	input[63:0] src_addr,
	output rd_req,
	input rd_req_ack,
	output[7:0] rd_len,
	output[63:0] rd_address,
	input[15:0] job_id,
	

	input[63:0] des_addr,
	output wr_req,
	input wr_req_ack,
	output[7:0] wr_len,
	output[63:0] wr_address,
	output bready,
	
	output[511:0] data_out,
	output[63:0] byte_valid_out,
	output wr_valid,
	input wr_ready,
	output wr_data_last,///whether it is the last 64B of a burst
	
	input[511:0] data_in,
	input valid_in,
	input rd_last,
	output data_ready, //whether decompressors are ready to receive data
	input[31:0] decompression_length,
	input[34:0] compression_length
);
//wires for the pending fifo
wire[63:0] pend_des_addr, pend_src_addr;
reg[34:0] pend_rd_compression_length;
wire[34:0] pend_rd_compression_length_w;
reg[31:0] pend_rd_decompression_length;
wire[31:0] pend_rd_decompression_length_w;
wire[15:0] pend_job_id;
wire pend_valid;
reg pend_rd;
wire pend_almost_full;
//wires for the FSM of reading
reg[34:6] compression_length_r;   ///[34:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] rd_address_r;
reg[15:0] rd_job_id;
reg[7:0] rd_len_r;
reg rd_req_r;
reg[2:0] rd_state;
reg push_back_flag;
//wires for rd_fifo
wire[15:0] rd_fifo_job_id_out;
wire rd_fifo_almost_full;
//wires for the decompressors
reg[NUM_DECOMPRESSOR-1:0] decompressors_idle, decompressors_done;
wire[NUM_DECOMPRESSOR-1:0] decompressors_idle_w, decompressors_done_w;
wire[NUM_DECOMPRESSOR-1:0] dec_valid_out, dec_last_out, dec_almostfull;
wire[NUM_DECOMPRESSOR * 64 -1:0] dec_des_address_w;
wire[NUM_DECOMPRESSOR * 32 -1:0] dec_decompression_length_w;
wire[NUM_DECOMPRESSOR * 512 -1:0] dec_data_out_w;

///buffer the input data and output signal of decompressors 
reg data_ready_r;
reg rd_last_buff;
reg valid_in_buff;
reg[511:0] data_in_buff;
//wires for output fifo
reg[511:0] of_data_in;
wire[511:0] of_data_in_w;
reg of_last_in;
reg of_valid_in;
reg of_almost_full;
wire of_almost_full_w;
always@(posedge clk)begin
	///input 
	if(dec_almostfull == 0)begin
		data_ready_r	<= 1'b1;
	end else begin 		//if one of the decompressor is almost full, stop the input
		data_ready_r	<= 1'b0;
	end
	
	data_in_buff	<= data_in;
	rd_last_buff	<= data_ready_r & data_ready_r;
	valid_in_buff	<= valid_in & data_ready_r;
	
	///output
	decompressors_idle <= decompressors_idle_w;
end


pending_fifo pending_fifo0(
	.clk(clk),
	.rst_n(rst_n),
	
	.wr(job_valid),
	
	.des_addr_in(des_addr),
	.rd_compression_length_in(compression_length),
	.rd_decompression_length_in(decompression_length),
	.src_addr_in(src_addr),
	.job_id_in(job_id),
	
	.des_addr_out(pend_des_addr),
	.rd_compression_length_out(pend_rd_compression_length_w),
	.rd_decompression_length_out(pend_rd_decompression_length_w),
	.src_addr_out(pend_src_addr),
	.job_id_out(pend_job_id),
	.rd(pend_rd),
	
	.almost_full(pend_almost_full),
	.valid_out(pend_valid)
);

/****************solved the read data*************/
localparam RD_START = 3'd0, RD_CHECK = 3'd1, RD_PROCESS = 3'd2, RD_PUSH_BACK = 3'd3, RD_WAIT = 3'd4;
 
//wires for working FIFO
reg[63:0] work_src_addr;
wire[63:0] work_src_addr_out;
reg[34:6] work_rd_length;
wire[34:6] work_rd_length_out;
reg[15:0] work_job_id, work_job_id_out;
wire[NUM_DECOMPRESSOR_LOG-1:0] work_count;
wire work_valid;
reg work_wr_valid;
always@(*)begin
/*the input of working fifo comes from FSM (write back unsolved job),
or the pending FIFO, the input from FSM should get priority*/
	if(push_back_flag)begin //the write back can be directly processed
		work_wr_valid	<= 1'b1;
		pend_rd			<=1'b0;
	end else if(pend_valid & (decompressors_idle != 0) & (work_count < 2))begin 
	//only add a new job if at least one of the decompressor is idle and there is empty place in work_fifo
		work_wr_valid	<= 1'b1;
		pend_rd			<=1'b1;
	end else begin
		work_wr_valid	<= 1'b0;
		pend_rd			<=1'b0;
	end
	
	if(push_back_flag)begin
		work_src_addr	<= rd_address_r;
		work_rd_length	<= compression_length_r;
		work_job_id		<= rd_job_id;
	end else begin
		work_src_addr	<= pend_src_addr;
		work_rd_length	<= pend_rd_compression_length;
		work_job_id		<= pend_job_id;
	end
end

always@(*)begin
	if(pend_rd_compression_length_w[5:0]!=6'b0)begin
		pend_rd_compression_length[34:6]	<= pend_rd_compression_length_w[34:6] + 29'd1;
	end else begin
		pend_rd_compression_length[34:6]	<= pend_rd_compression_length_w[34:6];
	end
	
	if(pend_rd_decompression_length_w[5:0]!=6'b0)begin
		pend_rd_decompression_length[34:6]	<= pend_rd_decompression_length_w[34:6] + 29'd1;
	end else begin
		pend_rd_decompression_length[34:6]	<= pend_rd_decompression_length_w[34:6];
	end
	
end

working_fifo working_fifo0(
	.clk(clk),
	.rst_n(rst_n),
	
	.wr(work_wr_valid),
	
	.rd_length_in(work_rd_length),
	.src_addr_in(work_src_addr),
	.job_id_in(work_job_id),
	.count(work_count),
	
	.rd_length_out(work_rd_length_out),
	.src_addr_out(work_src_addr_out),
	.job_id_out(work_job_id_out),
	
	.rd(rd_req_r),
	
	.valid_out(work_valid)
);



always@(posedge clk)begin
	if(~rst_n)begin
		rd_req_r	<= 1'b0;
		rd_state	<= RD_START;
	end else case(rd_state)
	RD_START:begin
		if(start)begin
			rd_state	<= RD_CHECK;
		end
		push_back_flag	<= 1'b0;
	end
	
	RD_CHECK:begin//check whether there is a job in the working fifo
		///if this is the last read, we do not need to write back
		if(work_rd_length_out[34:6]	< 29'd64)begin
			rd_len_r					<= {2'd0,work_rd_length_out[11:6]-6'd1};
			push_back_flag				<= 1'b0;
		end else begin
			rd_len_r					<= 8'b11_1111;
			push_back_flag				<= 1'b1;
		end
		
		compression_length_r[34:6]	<= work_rd_length_out[34:6]-29'd64;
		
		if(work_valid)begin //once there is job in the working_fifo, go to the next step to read
			rd_state	<= RD_PROCESS;
			rd_req_r	<= 1'b1;
		end
		
		rd_job_id		<= work_job_id_out;
		rd_address_r	<= work_src_addr_out + 64'd4096;
	end
	
	RD_PROCESS:begin
		push_back_flag				<= 1'b0;
		if(rd_req_ack)begin
			rd_req_r	<= 1'b0;
			//once the rd_fifo is almost full, stop sending command, wait until it is not full
			if(rd_fifo_almost_full)begin
				rd_state	<= RD_WAIT;
			end else begin
				rd_state	<= RD_CHECK;
			end
		end
	end
	
	RD_WAIT:begin
		if(~rd_fifo_almost_full)begin
			rd_state	<= RD_CHECK;
		end
	end
	
	default:begin rd_state	<= RD_START; end
	endcase
end

//once a request is sent to the AXI, record its job_id
//when the data comes, the id in this fifo indicates which decompressor should receive it
rd_fifo rd_fifo0(
	.clk(clk),
	.rst_n(rst_n),
	
	.wr(rd_req_r & rd_req_ack),
	.job_id_in(rd_job_id),
	.almost_full(rd_fifo_almost_full),
	
	.job_id_out(rd_fifo_job_id_out),
	.rd(rd_last_buff)
);


/****************write data*****************/
localparam WR_START = 3'd0, WR_CHECK = 3'd1, WR_PROCESS = 3'd2, WR_WRITE_ADDRESS =3'd3, WR_WAIT = 3'd4;

reg[31:0] decompression_length_r;   ///[32:15]:number of writing [14:12]:number of 4k blocks in writing  [11:6]:number of 64B in block [5:0]:fraction
wire[31:0] decompression_length_select;
reg[9:0] wr_length_64B; //number of 64B data to be written
reg[63:0] wr_address_r, wr_address_wb;
wire[31:0] wr_address_w;
reg[2:0] wr_state;
reg[7:0] wr_len_r;
reg[NUM_DECOMPRESSOR-1:0] wr_write_back; //write the address and length of unsolved job back 
reg wr_req_r;
reg wr_flag,wr_flag_buff; //whether the output of decompressor can start
reg[NUM_DECOMPRESSOR_LOG-1:0] wr_select;
reg[NUM_DECOMPRESSOR-1:0] dec_valid_flag; //select a decompressor to output
/*First, check all decompressors one by one to find a decompressor with valid output, then output all the data in the 64KB block,
and change to next decompressor*/
always@(posedge clk)begin
	if(~rst_n)begin
		wr_state	<= WR_START;
		wr_req_r	<= 1'b0;
		wr_select	<= 0;
		wr_write_back<= 0;
		dec_valid_flag	<= 0;
	end else case(wr_state)
	WR_START:begin
		if(start)begin
			wr_state	<= WR_CHECK;
		end
		wr_write_back<= 0;
		wr_req_r	<= 1'b0;
		dec_valid_flag	<= 0;
	end
	
	WR_CHECK:begin //check all the decompressor one by one to find the decompressor with valid output
		if(dec_valid_out[wr_select] == 1'b1)begin
			wr_state	<= WR_PROCESS;
		end else begin
			if(wr_select == NUM_DECOMPRESSOR)begin
				wr_select	<= 0;
			end else begin
				wr_select	<= wr_select + 1;
			end
		end
		dec_valid_flag	<= 0;
		wr_req_r	<= 1'b0;
		wr_write_back <= 0;
		//assign the data of corresponding decompressor to the registers of this FSM
		decompression_length_r[32:6]	<= decompression_length_select[31:6];
		wr_address_r[63:0]				<= wr_address_w;
	end
	
	WR_PROCESS:begin
		if(decompression_length_r[31:6] <= 26'd512)begin//check whether this is the last writing of the job
			wr_length_64B	<= decompression_length_r[15:6];
			wr_write_back	<= 0;
		end else begin
			wr_length_64B	<= 10'd512;
			wr_write_back	<= (1 << wr_select);
		end
		decompression_length_r[31:6]<= decompression_length_r[31:6] - 26'd512;
		wr_address_wb				<= wr_address_r + 64'd32768;
		wr_state					<= WR_WRITE_ADDRESS;
		wr_req_r					<= 1'b1; //start to write address
		dec_valid_flag				<= (1 << wr_select);
	end
	
	WR_WRITE_ADDRESS:begin
		if(wr_length_64B == 10'd1)begin //the last
			if(dec_valid_out[wr_select] & wr_req_ack)begin
				wr_req_r	<= 1'b0;
				wr_state	<= WR_WAIT;
			end
		end
		wr_write_back	<= 0;
		
		//once output a 64B data, plus address and minus left length
		if(wr_req_ack)begin
			wr_length_64B	<= wr_length_64B - 10'd1;
			wr_address_r	<= wr_address_r + 64;
		end
	end
	
	WR_WAIT:begin ///wait for the output of data
		if(dec_last_out[wr_select])begin
			wr_state	<= WR_CHECK;
			wr_select	<= 0;
			dec_valid_flag	<= 0;
		end
	end
	default:begin wr_state	<= WR_START; end 
	endcase
end

select 
#(
	.NUM_SEL(3), 
	.NUM_LOG(2),
	.NUM_WIDTH(32)
)select_decompression_length
(
    .data_in(decompression_length),
    .sel(wr_select),
    .data_out(decompression_length_select)
);

select 
#(
	.NUM_SEL(3), 
	.NUM_LOG(2),
	.NUM_WIDTH(64)
)select_des_address
(
    .data_in(dec_des_address_w),
    .sel(wr_select),
    .data_out(wr_address_w)
);

genvar dec_i; 
generate 	
	for(dec_i=0;dec_i<NUM_DECOMPRESSOR;dec_i=dec_i+1)begin: generate_decompressor
	
	wire[34:0] dm_compression_length_out;
	wire[31:0] dm_decompression_length_out;
	wire[511:0] dm_data_out;
	wire dm_data_valid_out;
	wire dm_start_out;
	decompressor_input_manage
	#( 
		.NUM_DECOMPRESSOR(NUM_DECOMPRESSOR),
		.NUM_DECOMPRESSOR_LOG(NUM_DECOMPRESSOR_LOG),
		.DEC_INDEX(dec_i)
	) dm0
	(
		.clk(clk),
		.rst_n(rst_n),
	
		.job_valid(pend_rd),
		.job_id_in(pend_job_id),  
		.des_address(pend_des_addr), 
		.decompression_length(pend_rd_decompression_length),
	
		.update_valid(wr_write_back[dec_i]), 
		.des_address_update(wr_address_wb), 
		.dec_decompression_length_update(decompression_length_r), 
	
		.des_address_out(dec_des_address_w[dec_i * 64 + 63:dec_i * 64]),
		.decompression_length_out(dec_decompression_length_w[dec_i * 32 + 31:dec_i * 32 + 6]),
		.job_id_out(),
	
		//signal to the decompressor
		.data_in(data_in_buff),
		.data_valid_in(valid_in_buff),
		.data_id(rd_fifo_job_id_out),
		.decompression_length_original(pend_rd_decompression_length_w),
		.compression_length_original(pend_rd_compression_length_w),
		.data_out(dm_data_out),
		.data_valid_out(dm_data_valid_out),

		.decompression_length_original_out(dm_decompression_length_out),
		.compression_length_original_out(dm_compression_length_out),
	    .start_out(),
		
		.decompressors_idle(decompressors_idle)
	);
		
	decompressor d0(
		.clk(clk),
		.rst_n(rst_n),
		.data(dm_data_out),
		.valid_in(dm_data_valid_out),
		.start(dm_start_out),
		.compression_length(dm_compression_length_out),
		.decompression_length(dm_decompression_length_out),
		.wr_ready(of_almost_full_w & dec_valid_flag[dec_i]),

		.data_fifo_almostfull(dec_almostfull[dec_i]),
	
		.done(decompressors_done_w[dec_i]),
		.idle(decompressors_idle_w[dec_i]),
		.last(dec_last_out[dec_i]),
		.data_out(dec_data_out_w[dec_i * 512 + 511:dec_i * 512]),
		.byte_valid_out(),
		.valid_out(dec_valid_out[dec_i])
	);
	end
endgenerate 


always@(posedge clk)begin
	of_data_in		<= of_data_in_w;
	of_last_in		<= dec_last_out[wr_select];
	of_valid_in		<= dec_valid_out[wr_select] & (dec_valid_flag!=0);
end

select 
#(
	.NUM_SEL(3), 
	.NUM_LOG(2),
	.NUM_WIDTH(512)
)select_data
(
    .data_in(dec_data_out_w),
    .sel(wr_select),
    .data_out(of_data_in_w)
);

output_fifo_ip output_fifo0 (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst_n),          // input wire s_aresetn
  .s_axis_tvalid(of_valid_in),  // input wire s_axis_tvalid
  .s_axis_tready(of_almost_full_w),  // output wire s_axis_tready
  .s_axis_tdata(of_data_in),    // input wire [511 : 0] s_axis_tdata
  .s_axis_tlast(of_last_in),    // input wire s_axis_tlast
  
  .m_axis_tvalid(wr_valid),  // output wire m_axis_tvalid
  .m_axis_tready(wr_ready),  // input wire m_axis_tready
  .m_axis_tdata(data_out),    // output wire [511 : 0] m_axis_tdata
  .m_axis_tlast(wr_data_last)    // output wire m_axis_tlast
);



reg wr_last_r;
reg[31:0] decompression_length_minus;
reg[31:0] data_cnt;  
always@(posedge clk)begin//generate the wr_last signal
	if(~rst_n)begin
		data_cnt	<=32'b0;
	end else if(wr_valid & wr_ready)begin
		data_cnt	<= data_cnt+32'd64;
	end
	
	// decompression_length_minus = decompression_length_r
	if(start)begin
		decompression_length_minus[31:6]<=decompression_length[31:6]+(decompression_length[5:0]!=6'b0)-32'b1;
	end
	
	//check whether this is the last write
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
	end else if((~decompressors_idle) == 0)begin
		idle_r<=1'b1;		
	end else begin
		idle_r<=1'b0;
	end
	
	if(~rst_n)begin
		bready_r<=1'b0;
	end else begin
		bready_r<=~pend_almost_full;
	end
end

assign byte_valid_out = 64'hffff_ffff_ffff_ffff;

assign rd_address	=rd_address_r;
assign rd_req		=rd_req_r;
assign rd_len		=rd_len_r;
assign idle			=idle_r;

assign wr_address	=wr_address_r;
assign wr_req		=wr_req_r;
assign wr_len		=wr_len_r;
assign bready		=bready_r;

assign data_ready 	= data_ready_r;

endmodule