module read_result_fifo(
	input clk,
	input srst,
	
//	.almost_full(),
	output full,
	output[88:0] din,
	output wr_en,
	
	output empty,
	output[88:0] dout,
	input rd_en,
	
	output valid,
	output prog_full,
	output wr_rst_busy,
	output rd_rst_busy
);

reg [88:0]fifo_out;
reg [88:0]ram[7:0];
reg [3:0]read_ptr,write_ptr,counter;
wire fifo_half,fifo_full;

always@(posedge clk)
  if(srst)
    begin
    read_ptr<=0;
    write_ptr<=0;
    counter<=0;
    fifo_out<=0;
    end
  else
    case({rd_en,wr_en})
      2'b00:
            counter=counter;     
      2'b01:                        
            begin
              ram[write_ptr]=din;
              counter=counter+1;
              write_ptr=(write_ptr==7)?0:write_ptr+1;
            end
      2'b10:                       
            begin
              fifo_out=ram[read_ptr];
              counter=counter-1;
              read_ptr=(read_ptr==7)?0:read_ptr+1;
            end
      2'b11:                  
            begin
				ram[write_ptr]=din;
                fifo_out=ram[read_ptr];
                write_ptr=(write_ptr==7)?0:write_ptr+1;
                read_ptr=(read_ptr==7)?0:read_ptr+1;
            end
        endcase

assign empty=(counter==0); 
assign fifo_half=(counter>=3);
assign fifo_full=(counter==8);
assign dout=fifo_out;
assign prog_full=fifo_half;
assign full=fifo_full;

endmodule

module working_fifo(
	input clk,
	input rst_n,
	
	input wr,
	
	input[25:0] rd_length_in,
	input[63:0] src_addr_in,
	input[15:0] job_id_in,
	output[1:0] count,
	
	output[25:0] rd_length_out,
	output[63:0] src_addr_out,
	output[15:0] job_id_out,
	
	input rd,
	output valid_out
);
reg rdreq;
reg valid_reg;
wire empty;
always@(*)begin
	if((~empty) & (~valid_reg) | rd)begin
		rdreq	<= 1'b1;
	end else begin
		rdreq	<= 1'b0;
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
		valid_reg <=1'b0;
	end else if(empty==1'b0 & valid_reg==1'b0)begin
		valid_reg <=1'b1;
	end else if(rd)begin
		valid_reg <= ~empty;
	end
end

wire[3:0] data_count;

working_fifo_ip your_instance_name (
  .clk(clk),                  // input wire clk
  .srst(~rst_n),                // input wire srst
  .din({rd_length_in, src_addr_in, job_id_in}),                  // input wire [108 : 0] din
  .wr_en(wr),              // input wire wr_en
  .rd_en(rdreq),              // input wire rd_en
  .dout({rd_length_out, src_addr_out, job_id_out}),                // output wire [108 : 0] dout
  .full(),                // output wire full
  .empty(empty),              // output wire empty
  .data_count(data_count),    // output wire [3 : 0] data_count
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);

assign count = data_count[1:0] + valid_reg;
assign valid_out	= valid_reg;
endmodule 

module rd_fifo(
	input clk,
	input rst_n,
	
	input wr,
	input[15:0] job_id_in,
	input almost_full,
	
	output[15:0] job_id_out,
	input rd
);

reg rdreq;
reg valid_reg;
wire empty;
always@(*)begin
	if((~empty) & (~valid_reg) | rd)begin
		rdreq	<= 1'b1;
	end else begin
		rdreq	<= 1'b0;
	end
end

always@(posedge clk)begin
	if(~rst_n)begin
		valid_reg <=1'b0;
	end else if(empty==1'b0 & valid_reg==1'b0)begin
		valid_reg <=1'b1;
	end else if(rd)begin
		valid_reg <= ~empty;
	end
end

rd_fifo_ip your_instance_name (
  .clk(clk),                  // input wire clk
  .srst(~rst_n),                // input wire srst
  .din(job_id_in),                  // input wire [15 : 0] din
  .wr_en(wr),              // input wire wr_en
  .rd_en(rdreq),              // input wire rd_en
  .dout(job_id_out),                // output wire [15 : 0] dout
  .full(),                // output wire full
  .empty(empty),              // output wire empty
  .prog_full(almost_full),      // output wire prog_full
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);
//assign valid_out	= valid_reg;
endmodule 
