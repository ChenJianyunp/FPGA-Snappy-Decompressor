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
	output data_taken, //whether decompressors are ready to receive data
	input[31:0] decompression_length,
	input[31:0] compression_length
);
//wires for the pending fifo
wire[63:0] pend_des_addr_w, pend_src_addr_w;
reg[63:0] pend_des_addr, pend_src_addr;
reg[31:0] pend_rd_compression_length;
wire[31:0] pend_rd_compression_length_w;
reg[31:6] pend_rd_decompression_length;
wire[31:0] pend_rd_decompression_length_w;
wire[15:0] pend_job_id_w;
reg[15:0] pend_job_id;
wire pend_valid;
wire pend_empty;
reg pend_rd;
wire pend_almost_full;
//wires for the FSM of reading
reg[31:6] compression_length_r;   ///[31:12]:number of 4k blocks  [11:6]:number of 64B [5:0]:fraction
reg[63:0] rd_address_r, rd_address_wb;
reg[15:0] rd_job_id;
reg[7:0] rd_len_r;
reg rd_req_r;
reg rd_ack;
reg[2:0] rd_state;
reg push_back_flag;
//wires for rd_fifo
wire[15:0] rd_fifo_job_id_out;
wire rd_fifo_almost_full;
//wires for the decompressors
reg[NUM_DECOMPRESSOR-1:0] decompressors_idle, decompressors_done;
wire[NUM_DECOMPRESSOR-1:0] decompressors_idle_w, decompressors_done_w, decompressors_block_out_w;
wire[NUM_DECOMPRESSOR-1:0] dec_valid_out, dec_last_out, dec_almostfull;
wire[NUM_DECOMPRESSOR * 64 -1:0] dec_des_address_w;
wire[NUM_DECOMPRESSOR * 32 -1:0] dec_decompression_length_w;
wire[NUM_DECOMPRESSOR * 512 -1:0] dec_data_out_w;

///buffer the input data and output signal of decompressors 
reg data_taken_r;
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
		data_taken_r	<= 1'b1;
	end else begin 		//if one of the decompressor is almost full, stop the input
		data_taken_r	<= 1'b0;
	end
	
	data_in_buff	<= data_in;
	rd_last_buff	<= rd_last & data_taken_r;
	valid_in_buff	<= valid_in & data_taken_r;
	
	///output
	decompressors_idle <= decompressors_idle_w;
end

wire[207:0] pend_din, pend_dout;
pending_fifo_ip pending_fifo_ip0 (
  .clk(clk),                  // input wire clk
  .srst(~rst_n),                // input wire srst
  .din(pend_din),                  // input wire [210 : 0] din
  .wr_en(job_valid),              // input wire wr_en
  .rd_en(pend_rd),              // input wire rd_en
  .dout(pend_dout),                // output wire [210 : 0] dout
  .full(),                // output wire full
  .empty(pend_empty),              // output wire empty
  .valid(),              // output wire valid
  .prog_full(pend_almost_full),      // output wire prog_full
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);
assign pend_din 						= {des_addr, compression_length, decompression_length, src_addr, job_id};
assign pend_job_id_w 					= pend_dout[15:0];
assign pend_src_addr_w 					= pend_dout[79:16];
assign pend_rd_decompression_length_w 	= pend_dout[111:80];
assign pend_rd_compression_length_w 	= pend_dout[143:112];
assign pend_des_addr_w 					= pend_dout[207:144];
/****************solved the read data*************/
localparam RD_START = 3'd0, RD_CHECK = 3'd1, RD_PROCESS = 3'd2, RD_PUSH_BACK = 3'd3, RD_WAIT = 3'd4;
 
//wires for working FIFO
reg[63:0] work_src_addr;
wire[63:0] work_src_addr_out;
reg[31:6] work_rd_length;
wire[31:6] work_rd_length_out;
reg[15:0] work_job_id;
wire[15:0] work_job_id_out;
wire[NUM_DECOMPRESSOR_LOG-1:0] work_count;
wire work_valid;
reg working_add;	//whether a new job can be added to working fifo
reg work_wr_valid;
wire work_empty;
always@(*)begin
/*the input of working fifo comes from FSM (write back unsolved job),
or the pending FIFO, the input from FSM should get priority*/
	if(push_back_flag)begin //the write back can be directly processed
		work_wr_valid	<= 1'b1;
	end else if(working_add)begin 
	//only add a new job if at least one of the decompressor is idle and there is empty place in work_fifo
		work_wr_valid	<= 1'b1;
	end else begin
		work_wr_valid	<= 1'b0;
	end
	
	if(push_back_flag)begin
		work_src_addr			<= rd_address_wb;
		work_rd_length[31:6]	<= compression_length_r[31:6];
		work_job_id				<= rd_job_id;
	end else begin
		work_src_addr			<= pend_src_addr;
		work_rd_length[31:6]	<= pend_rd_compression_length[31:6];
		work_job_id				<= pend_job_id;
	end
end

reg[2:0] pd_rd_state; //FSM to add new job to working fifo
reg dm_job_valid;
always@(posedge clk)begin
	if(~rst_n)begin
		pd_rd_state	<= 3'd0;
		pend_rd		<= 1'b0;
		working_add	<= 1'b0;
		dm_job_valid<= 1'b0;
	end else case(pd_rd_state)
		3'd0:begin
			if(start)begin pd_rd_state <= 3'd1; end
			pend_rd		<= 1'b0;
			working_add	<= 1'b0;
			dm_job_valid<= 1'b0;
		end
		
		3'd1:begin  //wait until pending fifo is not empty
			if(~pend_empty)begin
				pend_rd		<= 1'b1;
				pd_rd_state <= 3'd2;
			end
			dm_job_valid	<= 1'b0;
		end
		
		3'd2:begin //there is output register on pending fifo
			pend_rd		<= 1'b0;
			pd_rd_state <= 3'd3;
			dm_job_valid<= 1'b0;
		end
		
		3'd3:begin //read data
			if(pend_rd_compression_length_w[5:0]!=6'b0)begin
				pend_rd_compression_length[31:6]	<= pend_rd_compression_length_w[31:6] + 26'd1;
			end else begin
				pend_rd_compression_length[31:6]	<= pend_rd_compression_length_w[31:6];
			end
	
			if(pend_rd_decompression_length_w[5:0]!=6'b0)begin
				pend_rd_decompression_length[31:6]	<= pend_rd_decompression_length_w[31:6] + 26'd1;
			end else begin
				pend_rd_decompression_length[31:6]	<= pend_rd_decompression_length_w[31:6];
			end
			pend_src_addr	<= pend_src_addr_w;
			pend_des_addr	<= pend_des_addr_w;
			pend_job_id		<= pend_job_id_w;
			dm_job_valid	<= 1'b0;
			pd_rd_state 	<= 3'd4;
		end
		
		3'd4:begin//check whether there is idle decompressor
			if((decompressors_idle != 0) & (work_count < (NUM_DECOMPRESSOR-1)))begin 
				pd_rd_state <= 3'd5;
				working_add	<= 1'b1;
			end
			dm_job_valid	<= 1'b0;
		end
		
		3'd5:begin
			if(~push_back_flag)begin//if no job is pushed back, this new job has added
				working_add		<= 1'b0;
				pd_rd_state 	<= 3'd1;
				dm_job_valid	<= 1'b1;
			end
		end
		
		default:begin pd_rd_state <= 3'd0; end
	endcase
end

working_fifo working_fifo0(
	.clk(clk),
	.rst_n(rst_n),
	
	.wr(work_wr_valid),
	
	.rd_length_in(work_rd_length[31:6]),
	.src_addr_in(work_src_addr),
	.job_id_in(work_job_id),
	.count(work_count),
	
	.rd_length_out(work_rd_length_out[31:6]),
	.src_addr_out(work_src_addr_out),
	.job_id_out(work_job_id_out),
	.empty(work_empty),
	
	.rd(rd_ack),
	
	.valid_out(work_valid)
);

//FSM to read data from host memory
always@(posedge clk)begin
	if(~rst_n)begin
		rd_req_r	<= 1'b0;
		rd_ack		<= 1'b0;
		rd_state	<= RD_START;
	end else case(rd_state)
	RD_START:begin
		if(start)begin
			rd_state	<= RD_CHECK;
		end
		rd_req_r		<= 1'b0;
		rd_ack			<= 1'b0;
		push_back_flag	<= 1'b0;
	end
	
	RD_CHECK:begin//check whether there is a job in the working fifo
		///if this is the last read, we do not need to write back
		if(work_rd_length_out[31:6]	< 26'd64)begin
			rd_len_r					<= {2'd0,work_rd_length_out[11:6]-6'd1};
			push_back_flag				<= 1'b0;
		end else begin
			rd_len_r					<= 8'b11_1111;
			push_back_flag				<= 1'b1;
		end
		
		compression_length_r[31:6]	<= work_rd_length_out[31:6]-26'd64;
		
		if(work_valid)begin //once there is job in the working_fifo, go to the next step to read
			rd_state	<= RD_PROCESS;
			rd_req_r	<= 1'b1;
			rd_ack		<= 1'b1;
		end
		
		rd_job_id		<= work_job_id_out;
		rd_address_r	<= work_src_addr_out;
		rd_address_wb	<= work_src_addr_out + 64'd4096;
	end
	
	RD_PROCESS:begin
		push_back_flag	<= 1'b0;
		rd_ack			<= 1'b0;
		if(rd_req_ack)begin
			//once the rd_fifo is almost full, stop sending command, wait until it is not full
			rd_req_r	<= 1'b0;
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
	
	.wr(rd_ack),
	.job_id_in(rd_job_id),
	.almost_full(rd_fifo_almost_full),
	
	.job_id_out(rd_fifo_job_id_out),
	.rd(rd_last_buff)
);


/****************write data*****************/
localparam WR_START = 3'd0, WR_CHECK = 3'd1, WR_PROCESS = 3'd2, WR_WRITE_ADDRESS =3'd3, WR_WAIT = 3'd4;

reg[31:6] decompression_length_r;   ///[32:15]:number of writing [14:12]:number of 4k blocks in writing  [11:6]:number of 64B in block [5:0]:fraction
wire[31:0] decompression_length_select;
reg[10:0] wr_length_64B; //number of 64B data to be written
reg[63:0] wr_address_r, wr_address_wb;
wire[63:0] wr_address_w;
reg[2:0] wr_state;
reg[7:0] wr_len_r;
reg[NUM_DECOMPRESSOR-1:0] wr_write_back; //write the address and length of unsolved job back 
reg wr_req_r;
reg wr_flag,wr_flag_buff; //whether the output of decompressor can start
reg[NUM_DECOMPRESSOR_LOG-1:0] wr_select;
reg[NUM_DECOMPRESSOR-1:0] dec_valid_flag; //select a decompressor to output
reg wr_block; //block the data out
/*First, check all decompressors one by one to find a decompressor with valid output, then output all the data in the 64KB block,
and change to next decompressor*/
always@(posedge clk)begin
	if(~rst_n)begin
		wr_state		<= WR_START;
		wr_req_r		<= 1'b0;
		wr_select		<= 0;
		wr_write_back	<= 0;
		dec_valid_flag	<= 0;
		wr_block		<= 1'b0;
	end else case(wr_state)
	WR_START:begin
		if(start)begin
			wr_state	<= WR_CHECK;
		end
		wr_write_back<= 0;
		wr_req_r	<= 1'b0;
		dec_valid_flag	<= 0;
		wr_block		<= 1'b0;
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
		wr_req_r		<= 1'b0;
		wr_write_back 	<= 0;
		wr_block		<= 1'b0;
		//assign the data of corresponding decompressor to the registers of this FSM
		decompression_length_r[31:6]	<= decompression_length_select[31:6];
		wr_address_r[63:0]				<= wr_address_w;
	end
	
	WR_PROCESS:begin
		if(decompression_length_r[31:6] <= 26'd1024)begin//check whether this is the last writing of the job
			wr_length_64B	<= decompression_length_r[16:6];
			wr_write_back	<= 0;
		end else begin
			wr_length_64B	<= 11'd1024;
			wr_write_back	<= (1 << wr_select);
		end
		decompression_length_r[31:6]<= decompression_length_r[31:6] - 26'd1024;
		wr_address_wb				<= wr_address_r + 64'd65536;
		wr_state					<= WR_WRITE_ADDRESS;
		wr_req_r					<= 1'b1; //start to write address
		dec_valid_flag				<= (1 << wr_select);
		
		if(decompression_length_r[12:6] <= 26'd64)begin
			wr_len_r		<= {1'b0, decompression_length_r[12:6] - 1};
		end else begin
			wr_len_r		<= 8'b11_1111;
		end
		
	end
				
	WR_WRITE_ADDRESS:begin
		if(wr_length_64B <= 11'd64)begin //the last
			if(wr_req_ack)begin
				wr_req_r	<= 1'b0;
				wr_state	<= WR_WAIT;
			end
		end
		wr_write_back	<= 0;
		
		//once output a 64B data, plus address and minus left length
		if(wr_req_ack)begin
			wr_length_64B	<= wr_length_64B - 11'd64;
			wr_address_r	<= wr_address_r + 64'd4096;
			if(wr_length_64B <= 10'd128)begin
				wr_len_r	<= {wr_length_64B[7:0] - 8'd65};
			end else begin
				wr_len_r	<= 8'b11_1111;
			end
			wr_block		<= 1'b1;
		end
	end
	
	WR_WAIT:begin ///wait for the output of data
		if(decompressors_block_out_w[wr_select])begin
			wr_state	<= WR_CHECK;
			wr_select	<= 0;
			dec_valid_flag	<= 0;
			wr_block		<= 1'b0;
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
    .data_in(dec_decompression_length_w),
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
	
	wire[31:0] dm_compression_length_out;
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
	
		.job_valid(dm_job_valid),
		.job_id_in(pend_job_id),  
		.des_address(pend_des_addr), 
		.decompression_length(pend_rd_decompression_length),
	
		.update_valid(wr_write_back[dec_i]), 
		.des_address_update(wr_address_wb), 
		.dec_decompression_length_update(decompression_length_r[31:6]), 
	
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
	    .start_out(dm_start_out),
		
		.decompressors_idle(decompressors_idle)
	);
		
	decompressor d0(
		.clk(clk),
		.rst_n(rst_n),
		.data(dm_data_out),
		.valid_in(dm_data_valid_out),
		.start(dm_start_out),
		.compression_length({3'd0, dm_compression_length_out}),
		.decompression_length(dm_decompression_length_out),
		.wr_ready(of_almost_full_w & dec_valid_flag[dec_i]),

		.data_fifo_almostfull(dec_almostfull[dec_i]),
	
		.block_out(decompressors_block_out_w[dec_i]),
		.done(decompressors_done_w[dec_i]),
		.idle(decompressors_idle_w[dec_i]),
		.last(dec_last_out[dec_i]),
		.data_out(dec_data_out_w[dec_i * 512 + 511:dec_i * 512]),
		.byte_valid_out(),
		.valid_out(dec_valid_out[dec_i])
	);
	end
endgenerate 


always@(*)begin
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
  .s_aresetn(rst_n),          // input wire s_aresetn
  .s_axis_tvalid(of_valid_in),  // input wire s_axis_tvalid
  .s_axis_tready(of_almost_full_w),  // output wire s_axis_tready
  .s_axis_tdata(of_data_in),    // input wire [511 : 0] s_axis_tdata
  .s_axis_tlast(of_last_in),    // input wire s_axis_tlast
  
  .m_axis_tvalid(wr_valid),  // output wire m_axis_tvalid
  .m_axis_tready(wr_ready),  // input wire m_axis_tready
  .m_axis_tdata(data_out),    // output wire [511 : 0] m_axis_tdata
  .m_axis_tlast(wr_data_last)    // output wire m_axis_tlast
);

reg idle_r;
reg bready_r;
reg done_r;
reg[6:0] done_buff;
reg pend_empty_buff,work_empty_buff, of_empty_buff;
reg[NUM_DECOMPRESSOR-1:0] decompressors_idle_buff;
wire[NUM_DECOMPRESSOR-1:0] decompressors_idle_buff_inverse;
always@(posedge clk)begin	
	if(~rst_n)begin
		bready_r<=1'b0;
	end else begin
		bready_r<=~pend_almost_full;
	end
end
assign decompressors_idle_buff_inverse = ~decompressors_idle_buff;

always@(posedge clk)begin
	//buffer some signal to check the finish of all the jobs
	pend_empty_buff 		<= pend_empty;
	work_empty_buff 		<= work_empty;
	of_empty_buff			<= ~wr_valid;
	decompressors_idle_buff	<=decompressors_idle_w;
	
	if(~rst_n)begin
		done_buff <= 0;
	end else begin
		if(pend_empty_buff & work_empty_buff & of_empty_buff & (decompressors_idle_buff_inverse == 0) )begin
			done_buff[0] <= 1'b1;
		end else begin
			done_buff[0] <= 1'b0;
		end
		done_buff[6:1] <= done_buff[5:0];
	end
end

reg[1:0] action_state;
always@(posedge clk)begin
	if(~rst_n)begin
		action_state <= 2'd0;
		done_r	<= 1'b0;
		idle_r	<= 1'b1;
	end else begin
		case(action_state)
		2'd0:begin
			if(start)begin
				action_state	<= 2'd1;
				done_r			<= 1'b0;
				idle_r			<= 1'b0;				
			end
		end
		2'd1:begin
			if(done_buff[6:1]==6'b11_1111)begin
				done_r			<= 1'b1;
				idle_r			<= 1'b1;
				action_state 	<= 2'd0;
			end
		end
		endcase
	end
end

assign byte_valid_out = 64'hffff_ffff_ffff_ffff;

assign rd_address	= rd_address_r;
assign rd_req		= rd_req_r;
assign rd_len		= rd_len_r;
assign idle			= idle_r;

assign wr_address	= wr_address_r;
assign wr_req		= wr_req_r;
assign wr_len		= wr_len_r;
assign bready		= bready_r;

assign done			= done_r;
assign data_taken 	= data_taken_r;

endmodule