module control#
(
	parameter NUM_PARSER=6,
	PARSER_ALLONE=6'b111111
)
(
	input clk,
	input rst_n,
	input start,
	
	input tf_empty, //token fifo
	input[NUM_PARSER-1:0] ps_finish,
	input page_input_finish,
	input[NUM_PARSER-1:0] ps_empty, //parser
	input[15:0] ram_empty,//ram 
	
//	input block_out_finish
	output idle, 
	input cl_finish,
	output job_decompressed
	
);

reg all_empty;
reg[5:0] all_empty_delay;
reg page_input_finish_flag;
always@(posedge clk)begin
	if(ps_empty==PARSER_ALLONE & ram_empty==16'hffff)begin
		all_empty<=1'b1;
	end else begin
		all_empty<=1'b0;
	end
	
	if(~rst_n)begin
		page_input_finish_flag<=1'b0;
	end if(page_input_finish) begin
		page_input_finish_flag<=1'b1;
	end
	
	all_empty_delay[5:1] 	<=all_empty_delay[4:0];
	all_empty_delay[0] 		<=all_empty;
end

reg[2:0] state;
reg job_decompressed_r,block_finish_r;
always@(posedge clk)begin
	case(state)
	3'd0:begin
		job_decompressed_r<=1'b0;
		block_finish_r<=1'b0;
		if(~tf_empty)begin
			state<=3'd1;
		end
	end
	3'd1:begin //idle case
		job_decompressed_r<=1'b0;
		block_finish_r<=1'b0;
/*		if(ps_finish!=0)begin
			state<=3'd2;
		end else */if(page_input_finish & tf_empty)begin
			state<=3'd3;
		end
	end
/*	3'd2:begin//wait for the block finish
		if(all_empty_delay==6'b1111_11 & all_empty==1'b1)begin
			state<=3'd4;
			block_finish_r<=1'b1;
		end
	end
	*/
	3'd3:begin //wait until the output of all data
		if(all_empty_delay==6'b1111_11 & all_empty==1'b1 & tf_empty)begin
			job_decompressed_r<=1'b1;
			state<=3'd4;
		end
	end
	
	3'd4:begin//wait for the page clean finished
		if(cl_finish)begin
			state <=3'd5;
			job_decompressed_r<=1'b0;
		end
	end
		
	3'd5:begin //
		block_finish_r<=1'b0;
		state<=3'd0;
	end
	default:state<=3'd0;
	endcase
end

reg idle_r;

always@(posedge clk)begin
	if(~rst_n)begin
		idle_r	<= 1'b1;
	end else if(start)begin
		idle_r	<= 1'b0;
	end else if(cl_finish)begin //whenthe RAMs are cleaned, become idle again
		idle_r	<= 1'b1;
	end
end

assign job_decompressed	= job_decompressed_r;
assign idle 			= idle_r;

endmodule 