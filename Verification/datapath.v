module datapath
#(parameter CWL = 9, CL = 9, tbl8 = 4)
(input clkin, clk_90, crst_n,
 input [31:0] cwdat,
 output[31:0] crdat,
 input [3:0] cont_state,
 
 inout [3:0] ddq,
 inout ddqs_t_o, ddqs_c_o,
 output reg read_valid
 //output [5:0] wctr, tctr, tctr_dq,
 //output [2:0] dp_state_o
 );

parameter idle = 0, waiting_wr = 1, waiting_rd = 2, toggle_wr = 3, toggle_rd = 4; 
reg [2:0] dp_state, next_state;
integer wait_ctr, toggle_ctr, toggle_ctr_dq;
reg [31:0] crdat_reg;
reg [3:0] ddq_reg;
reg ddqs_t, ddqs_c, wait_pedge;
reg start_flag;

//dp fsm
always @ *
	begin
		case(dp_state)
			idle: 	next_state = (cont_state == 7) ? waiting_wr:((cont_state == 6) ? waiting_rd:idle);
			waiting_wr: next_state = (wait_ctr == 0) ? toggle_wr:waiting_wr;
			waiting_rd: next_state = (wait_ctr == 0) ? toggle_rd:waiting_rd;
			toggle_wr:  next_state = (toggle_ctr == 0) ? idle:toggle_wr;
			toggle_rd:  next_state = (toggle_ctr == 0) ? idle:toggle_rd;
		endcase
	end
	
always @ (posedge clkin)
	dp_state <= crst_n ? next_state:idle;

//counter assignment
always @ (posedge clkin)
	begin
		case(dp_state)
			idle: 	wait_ctr <= (cont_state == 7) ? (CWL-1):(CL-1);
			waiting_wr: begin
								wait_ctr <= wait_ctr - 1;
								toggle_ctr <= tbl8 - 1;
						   end	
			waiting_rd: begin
								wait_ctr <= wait_ctr - 1;
								toggle_ctr <= tbl8 - 1;
						   end	
			toggle_wr:  toggle_ctr <= toggle_ctr - 1;
			toggle_rd:  toggle_ctr <= toggle_ctr - 1;
		endcase
	end	
	
//strobe driver
always @ *
	begin
		if(crst_n == 0)
			begin
				ddqs_t <= 1;
				ddqs_c <= 1;
			end
		else
			begin
				case(dp_state)
					idle: 		begin
										ddqs_t <= 1;
										ddqs_c <= 1;
									end
					waiting_wr: begin
										if(wait_ctr != 0)
											begin
												ddqs_t <= 1;
												ddqs_c <= 1;
											end
										else
											begin
												ddqs_t <= clkin;
												ddqs_c <= ~clkin;
											end
								   end	
					toggle_wr:  begin
										ddqs_t <= clkin;
										ddqs_c <= ~clkin;
									end
				endcase
			end
	end	

//start_flag
always @ (negedge clkin)
begin
	if((dp_state == waiting_wr) & (wait_ctr == 0))
		 start_flag <= 1;
	else 
		 start_flag <= 0;
end
	
//dq line
always @ (clk_90)
	begin
		if(crst_n == 0)
			toggle_ctr_dq <= 0;
		else
			begin
				case (dp_state)
					idle: read_valid <= 1'b0;
					waiting_wr: begin
										if(start_flag == 1)
											begin
												ddq_reg <= cwdat[3:0];
												toggle_ctr_dq <= 4;
											end
									end
					waiting_rd: toggle_ctr_dq <= 0;
				   toggle_wr:  begin
										ddq_reg <= cwdat[toggle_ctr_dq +: 4];
										toggle_ctr_dq <= toggle_ctr_dq + 4;
									end
					toggle_rd:  begin
										crdat_reg[toggle_ctr_dq +: 4] <= ddq;
										$display("ddr4_cont:Recieved ddq = %d", ddq);
										toggle_ctr_dq <= toggle_ctr_dq + 4;
										
										if(toggle_ctr_dq == 28)
											read_valid <= 1'b1;
									end
				endcase
			end
	end

//assign {ddqs_t_o, ddqs_c_o} = {ddqs_t, ddqs_c};
assign {ddqs_t_o, ddqs_c_o} = (dp_state == toggle_wr || dp_state == waiting_wr) ? {ddqs_t, ddqs_c} : 2'bzz;
//assign ddq = ddq_reg;
assign ddq = ((dp_state == toggle_wr) || start_flag) ? ddq_reg : {4{1'bz}};
assign wctr = wait_ctr;
assign tctr = toggle_ctr;
assign tctr_dq = toggle_ctr_dq;
assign crdat = crdat_reg;	
assign dp_state_o = dp_state;
endmodule 