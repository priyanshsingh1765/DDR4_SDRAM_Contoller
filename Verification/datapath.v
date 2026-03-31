module datapath
#(parameter CWL = 9, tbl8 = 4)
(input clkin, clk_90, crst_n,
 input [31:0] cwdat,
 input [3:0] cont_state,
 
 output reg [3:0] ddq,
 output ddqs_t_o, ddqs_c_o
// output [5:0] wctr, tctr,
// output [1:0] dp_state_o
);

parameter idle = 0, waiting = 1, toggle = 2; 
reg [1:0] dp_state, next_state;
integer wait_ctr, toggle_ctr, toggle_ctr_dq;
reg ddqs_t, ddqs_c, wait_pedge;
reg start_flag;
//reg clk_90;

////90 deg clock
//always @ (clkin)
//begin
//	if(crst_n == 0)
//		clk_90 <= 1;
//	else
//		begin
//			#5;
//			clk_90 <= ~clk_90;
//		end
//end

//dp fsm
always @ *
	begin
		case(dp_state)
			idle: 	next_state = (cont_state == 7) ? waiting:idle;
			waiting: next_state = (wait_ctr == 0) ? toggle:waiting;
			toggle:  next_state = (toggle_ctr == 0) ? idle:toggle;
		endcase
	end
	
always @ (posedge clkin)
	dp_state <= crst_n ? next_state:idle;

//counter assignment
always @ (posedge clkin)
	begin
		case(dp_state)
			idle: 	wait_ctr <= CWL - 1; //not CWL - 1 as  
			waiting: begin
							wait_ctr <= wait_ctr - 1;
							toggle_ctr <= tbl8 - 1;
						end	
			toggle:  toggle_ctr <= toggle_ctr - 1;
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
					idle: 	begin
									ddqs_t <= 1;
									ddqs_c <= 1;
								end
					waiting: begin
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
					toggle:  begin
									ddqs_t <= clkin;
									ddqs_c <= ~clkin;
								end
				endcase
			end
	end	

//start_flag
always @ (negedge clkin)
begin
	if((dp_state == waiting) & (wait_ctr == 0))
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
				if((dp_state == waiting) & (start_flag == 1))
					begin
						ddq <= cwdat[3:0];
						toggle_ctr_dq <= 4;
					end
				else if(dp_state == toggle)
					begin
						ddq <= cwdat[toggle_ctr_dq +: 4];
						toggle_ctr_dq <= toggle_ctr_dq + 4;
					end
			end
	end
	
assign wctr = wait_ctr;
assign tctr = toggle_ctr;
assign {ddqs_t_o, ddqs_c_o} = {ddqs_t, ddqs_c};	
assign dp_state_o = dp_state;
endmodule