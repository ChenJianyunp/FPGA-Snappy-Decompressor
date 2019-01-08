module decompressor_input_manage
#( 
	parameter NUM_DECOMPRESSOR = 3,
	NUM_DECOMPRESSOR_LOG = 2,
	DEC_INDEX = 0
)
(
	input clk,
	input rst_n,
	
	input job_valid,		
	input[15:0] job_id_in,  
	input[63:0] des_address, 
	input[31:6] decompression_length, 
	
	input update_valid, 
	input[63:0] des_address_update, 
	input[31:6] dec_decompression_length_update, 
	
	output[63:0] des_address_out,
	output[31:6] decompression_length_out,
	output[15:0] job_id_out,
	
	//signal to the decompressor
	input[511:0] data_in,
	input data_valid_in,
	input[15:0] data_id,
	input[31:0] decompression_length_original,
	input[31:0] compression_length_original,
	output[511:0] data_out,
	output data_valid_out,

	output[31:0] decompression_length_original_out,
	output[31:0] compression_length_original_out,
	output start_out,
	
	
	input[NUM_DECOMPRESSOR-1:0] decompressors_idle
);

wire is_selected;
reg[DEC_INDEX:0] is_selected_temp;
integer i;
always@(*)begin
	for(i = 0; i < DEC_INDEX + 1; i = i+1)begin
		if(i == DEC_INDEX)begin is_selected_temp[i] <= ~decompressors_idle[i]; end
		else begin is_selected_temp[i] <= decompressors_idle[i]; end 
	end
end
assign is_selected = (is_selected_temp == 0);

reg[15:0] job_id_r;
reg[63:0] des_address_r;
reg[31:0] decompression_length_r;
reg dec_valid;
always@(posedge clk)begin
	if(job_valid)begin
		if(is_selected)begin
			job_id_r 						<= job_id_in;
			des_address_r					<= des_address;
			decompression_length_r[31:6]	<= decompression_length[31:6];
		end
	end else begin
		if(update_valid)begin
			des_address_r					<=	des_address_update;
			decompression_length_r[31:6] 	<= 	dec_decompression_length_update[31:6];
		end
	end
end

reg[511:0] data_r;
always@(posedge clk)begin
	if(job_id_r == data_id)begin
		dec_valid <= data_valid_in;
	end else begin
		dec_valid <= 1'b0;
	end
	data_r	<= data_in;
end

reg[511:0] data_r2;
reg dec_valid2;
always@(posedge clk)begin
	dec_valid2 	<= dec_valid;
	data_r2		<= data_r;
end


assign des_address_out 					= des_address_r;
assign decompression_length_out[31:6]	= decompression_length_r[31:6];
assign job_id_out 						= job_id_r;

//buffer the start signal and lengths information
reg[31:0] compression_length_buff;
reg[31:0] decompression_length_buff;
reg start_buff;
always@(posedge clk)begin
	compression_length_buff		<= compression_length_original;
	decompression_length_buff	<= decompression_length_original;
			
	if(job_valid)begin
		if(is_selected)begin
			start_buff		<= 1'b1;
		end else begin
			start_buff		<= 1'b0;
		end
	end else begin
		start_buff		<= 1'b0;
	end
end

assign start_out = start_buff;
assign compression_length_original_out = compression_length_buff;
assign decompression_length_original_out = decompression_length_buff;

assign data_out 		= data_r2;
assign data_valid_out	= dec_valid2;

endmodule