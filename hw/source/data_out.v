/***********************************
Name: 		Jianyu Chen
School:		Delft University of Technology
Date:		7th, July 2018
Function:	Store the decompression 
***********************************/
module data_out(
	input clk,
	input rst_n,
	
	input start,
//	input block_finish,
	input ready,    ///whether dma is ready to receive data
	///signal for writing data
	input[31:0] decompression_length,
	input[15:0] valid_wr_in,
	input[1023:0] lit_in,
	input[143:0] lit_address,
	input[127:0] lit_valid,
	input page_finish,  ///if all the page has already processed 
	/////
	output block_out_finish,  ///all data in block has outputed
	output page_out_finish,
	output cl_finish,   ///all data are cleaned
	output last,  ///whether it is the last 64B of a burst
	output[511:0] data_o,
	output[63:0] byte_valid_o,
	output valid_o
);
wire[1023:0] data_w;
wire[127:0] valid_w,valid_w2;
reg valid_upper,valid_lower;
reg[1023:0] data_out_buff;

reg[25:0] rd_address_w;
reg valid_out_w;

reg block_out_finish_r;
reg[8:0] wr_address;
reg[25:0] rd_address; //[25:10]:block count [9:1] the address of ram from 0 to 512, [0] select upper or lower
//reg[15:0] block_cnt; ///cnt the number of the block
reg[2:0] state;
reg rd_valid;
reg wr_flag;
reg final_valid;
reg cl_finish_flag;
reg valid_inverse;
reg page_out_finish_r;

//reg[31:0] decompression_length_r;
reg[25:0] max_address; ///max address for ram -1
always@(posedge clk)begin
	if(start)begin
		if(decompression_length[5:0]==6'b0)begin
			max_address	<= decompression_length[31:6]-26'b1;
		end else begin
			max_address	<= decompression_length[31:6];
		end
	end	
end

always@(posedge clk)begin
	if(~rst_n)begin
		state<=3'd0;
	end
	case(state)
	3'd0:begin  ///idle state
		if(start)begin
			state		<=3'd1;
			rd_valid	<=1'b1;
		end else begin
			rd_valid	<=1'b0;
		end
		
		wr_flag		<=1'b0;
		final_valid	<=1'b0;
		page_out_finish_r<=1'b0;
		cl_finish_flag<=1'b0;
		rd_address	<=26'b0;
		block_out_finish_r<=1'b0;
	end
	3'd1:begin  //read
		block_out_finish_r<=1'b0;
		rd_address	<=rd_address_w;
		rd_valid	<=1'b1;
		if((rd_address[9:0]==10'd1022) & valid_lower & ready)begin
			state<=3'd2;
		end else if((rd_address==max_address) & page_finish & ready)begin //whether output all the data in page
			state<=3'd3;
			final_valid	<=1'b1;			
		end
	end
	3'd2:begin  //clean the input
		if(valid_upper & ready)begin
			state		<=3'd1;
			valid_inverse	<=~valid_inverse;		
			block_out_finish_r<=1'b1;
			rd_address	<=rd_address_w;
		end
	end
	
	3'd3:begin
		if(ready)begin
			state		<=3'd4;
			wr_flag		<=1'b1;
			final_valid	<=1'b0;
			rd_valid	<=1'b0;
		end
		wr_address	<=3'd0;
	end
	3'd4:begin  ////clean all the valid bit in BRAM
		wr_address	<=wr_address+9'd1;
		valid_inverse	<=1'b0;
		rd_valid	<=1'b0;
		if(wr_address==9'd511)begin
			state		<=3'd0;
			page_out_finish_r<=1'b1;
			cl_finish_flag	<=1'b1;
		end else begin
			wr_flag			<=1'b1;
		end
	end
	default:state		<=3'd0;
	endcase
end

reg[9:0] rd_address_lowerl;
always@(*)begin
	if(((rd_address[0]==1'b0&valid_lower)|(rd_address[0]==1'b1&valid_upper))&ready)begin
		rd_address_w	<=rd_address+26'b1;
		valid_out_w<=1'b1;		
	end else begin
		rd_address_w	<=rd_address;
		valid_out_w<=1'b0;
	end
	
	rd_address_lowerl<=rd_address_w+10'b1;
end


genvar ram_i;
generate
for(ram_i=0;ram_i<16;ram_i=ram_i+1)begin:generate_ram

reg[8:0] rd_address_w2;
always@(*)begin
	if(ram_i<8)begin
		rd_address_w2	<=rd_address_lowerl[9:1];
	end else begin
		rd_address_w2	<=rd_address_w[9:1];
	end
end


reg valid_wr_buff;
reg[63:0] lit_buff;
reg[8:0] lit_address_buff;
reg[7:0] lit_valid_buff;
reg[7:0] lit_byte_valid;
wire[7:0] dina_valid_w;
always@(posedge clk)begin
	valid_wr_buff	<=valid_wr_in[ram_i];
	lit_buff		<=lit_in[64*ram_i+63:64*ram_i];
	lit_address_buff<=lit_address[9*ram_i+8:9*ram_i];
	lit_valid_buff	<=lit_valid[8*ram_i+7:8*ram_i]^{8{valid_inverse}};
	lit_byte_valid	<=lit_valid[8*ram_i+7:8*ram_i];
	data_out_buff	<=data_w;
end
assign dina_valid_w=wr_flag?8'b0:lit_valid_buff;

initial
begin
	valid_wr_buff	<=1'b0;
	lit_buff		<=64'b0;
	lit_address_buff<=9'b0;
	lit_valid_buff	<=8'b0;
	valid_inverse	<=1'b0;
	rd_valid		<=1'b0;
	wr_address		<=9'b0;
end

blockram result_ram0(
	.addra(lit_address_buff),
	.clka(clk),
	.dina({dina_valid_w[7],lit_buff[63:56],dina_valid_w[6],lit_buff[55:48],dina_valid_w[5],lit_buff[47:40],dina_valid_w[4],lit_buff[39:32],dina_valid_w[3],lit_buff[31:24],dina_valid_w[2],lit_buff[23:16],dina_valid_w[1],lit_buff[15:8],dina_valid_w[0],lit_buff[7:0]}),
	.ena(wr_flag|valid_wr_buff),
	.wea(wr_flag?8'hff:lit_byte_valid),
	
	.addrb(rd_address_w2),
	.clkb(clk),
	.doutb({valid_w2[127-8*ram_i-0],data_w[1023-64*ram_i-0:1023-64*ram_i-7],valid_w2[127-8*ram_i-1],data_w[1023-64*ram_i-8:1023-64*ram_i-15],valid_w2[127-8*ram_i-2],data_w[1023-64*ram_i-16:1023-64*ram_i-23],valid_w2[127-8*ram_i-3],data_w[1023-64*ram_i-24:1023-64*ram_i-31],valid_w2[127-8*ram_i-4],data_w[1023-64*ram_i-32:1023-64*ram_i-39],valid_w2[127-8*ram_i-5],data_w[1023-64*ram_i-40:1023-64*ram_i-47],valid_w2[127-8*ram_i-6],data_w[1023-64*ram_i-48:1023-64*ram_i-55],valid_w2[127-8*ram_i-7],data_w[1023-64*ram_i-56:1023-64*ram_i-63]}),
	.enb(1'b1)
);
end

endgenerate

/****generate the last signal for each burst*****/
reg last_r;
always@(posedge clk)begin
	if(~rst_n)begin
		last_r	<=1'b0;
	end else if((rd_address_w[5:0]==6'b11_1111))begin
		last_r	<=1'b1;
	end else begin
		last_r	<=1'b0;
	end
end

reg block_out_finish_buff_r,block_out_finish_buff_r2;
reg page_out_finish_buff_r;
always@(posedge clk)begin
	block_out_finish_buff_r	<=block_out_finish_r;
	block_out_finish_buff_r2<=block_out_finish_buff_r;
	
	page_out_finish_buff_r<=page_out_finish_r;
end

/**********************************/
reg[511:0] data_upper,data_lower;
always@(posedge clk)begin
	valid_upper	<=(valid_w[63:0]==~64'b0);
	valid_lower	<=(valid_w[127:64]==~64'b0);
	
	data_upper	<=data_w[511:0];
	data_lower	<=data_w[1023:512];
end


assign valid_w	=valid_w2^{128{valid_inverse}};
assign block_out_finish=block_out_finish_buff_r2;

assign page_out_finish=page_out_finish_buff_r;
assign cl_finish=cl_finish_flag;
assign data_o		=rd_address[0]?data_upper:data_lower;
assign byte_valid_o	=(~64'b0);
assign valid_o		=((rd_address[0]?valid_upper:valid_lower)&rd_valid)| final_valid;
assign last			=valid_o & (final_valid |last_r);

endmodule