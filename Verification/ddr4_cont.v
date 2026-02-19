module ddr4_cont(
 input clkin, crst_n, crd, cwr,
 input [30: 0] ca,
 input [3:0] cwdat,
 output reg [3:0] crdat,
 
 inout reg [3:0] ddq,
 inout reg ddqs_t, ddqs_c,
 output reg drst_n, clkout_t, clkout_c, cke,
 output reg [16:0] da,
 output reg dcs_n, dact_n,
 output reg [1:0] dbg, dba,
 //pins for testing 
 output [3:0] curr_state,
 output integer delay, rfsh_ctr,
 output integer rwcase,
 input [13:0] mode_reg_addr
);

//timing values for E-die - to be used by FSM wait state
parameter tPW_RESET = 160; //800 is the min spec - actual value dep on the supply Voltage slew rate
parameter internal_init = 80;//400000; //min spec for internal initialization
parameter txpr = 737;//136; - made 930 for memtesting (includes tDLLK) 
parameter tmrd = 24, tmod = 24; //tmrd must be 8 as per spec, but made 24 here as thats what the mem model TB has
parameter tzqinit = 1024, tzqoper = 512, tzqcs = 128;
parameter trp = 11;
parameter trcd = 11, CL = 9, CWL = 9, tbl8 = 4; //latencies changed to 9 for mem testing
parameter trfc = 128, trefi = 6240; //+trfc because of upcount in waiting state
parameter trrds = 4, trrdl = 4;

//FSM states
parameter init0 = 0, init1 = 1, init_mrs = 2, init_zq = 3; //initialization sequence
parameter waiting = 4;
parameter idle = 5, read = 6, write = 7, refresh = 8;

//signals used
reg [3:0] state, next_state, ret;
//integer delay, rfsh_ctr, mrs_ctr; //to be used by the wait state
integer mrs_ctr; 

//status of the banks
reg [3:0] bank_precharged [3:0]; //individual bank precharged
wire all_precharged; //all banks precharged
reg [16:0] active_address [3:0] [3:0];//bg->ba->row

assign all_precharged = ((bank_precharged[3] & bank_precharged[2] & bank_precharged[1] & bank_precharged[0]) == 4'b1111) ? 1:0;

//next state logic
always @ (*)
	begin
		case (state)
			waiting: next_state <= (delay == 0) ? ret:waiting;
			
			idle:    begin
						if((rfsh_ctr < 9*trefi) & (crd | cwr))//higher priority to CPU read/write cmds
							begin
						   if(active_address[ca[30:29]][ca[28:27]] == ca[26:10] & bank_precharged[ca[30:29]][ca[28:27]] == 0)
								begin
								next_state <= crd ? read:write; // direct read/write for Row hit
								rwcase <= 1;
								$display("bank_precharged = %p", bank_precharged);
								$display("active_address = %p", active_address);
								end
							else
								begin
								if(bank_precharged[ca[30:29]][ca[28:27]] == 1)
								  begin
									rwcase <= 2;
									$display("bank_precharged = %p", bank_precharged);
									$display("active_address = %p", active_address);
								  end
								else
								  begin
									rwcase <= 3;
									$display("bank_precharged = %p", bank_precharged);
									$display("active_address = %p", active_address);
								  end
								next_state <= waiting;//Row miss - need to activate or precharge
								end
						   end
						else if(rfsh_ctr >= trefi) //Need to refresh and no cpu read write command
							next_state <= all_precharged ? refresh:waiting;
							
						else
						   next_state <= idle; //this is a queueless solution as of now, as it assumes cpu maintains crd, cwr until read/write is complete
						end
						
			default: next_state <= waiting;
	   endcase
   end

always @ (posedge clkin)
	begin
		state <= crst_n ? next_state:init0;
   end

//delay, counter, memory bank status logic
always @ (posedge clkin)
begin
	case(state)
		waiting:  begin 
					 delay <= delay - 1;
					 if(ret > 3)
						rfsh_ctr <= rfsh_ctr + 1;
					 end
					 
		init0:    begin
					 $display("Controller State = init0, time = %0t",  $time);	
					 delay <= tPW_RESET;
					 end
		
		init1: 	 begin
					 $display("Controller State = init1, time = %0t",  $time);
					 delay <= internal_init;
					 mrs_ctr <= 0;
					 rfsh_ctr <= 0;
					 end
					 
		init_mrs: begin
					 $display("Controller State = init_mrs, time = %0t",  $time);
					 delay <= (mrs_ctr == 7) ? tmod:((mrs_ctr == 0) ? txpr:tmrd);
					 mrs_ctr <= mrs_ctr + 1;
					 bank_precharged[0] <= 4'b0000;
					 bank_precharged[1] <= 4'b0000;
					 bank_precharged[2] <= 4'b0000;
					 bank_precharged[3] <= 4'b0000;
					 end
		
		init_zq:  begin
					 $display("Controller State = init_zq, time = %0t",  $time);
					 delay <= all_precharged ? tzqinit:trp;
					 bank_precharged[0] <= 4'b1111;
					 bank_precharged[1] <= 4'b1111; 
					 bank_precharged[2] <= 4'b1111;
					 bank_precharged[3] <= 4'b1111;
					 end
		
		idle:     begin
//					 $display("Controller State = idle, time = %0t",  $time);
					 if((rfsh_ctr < 9*trefi) & (crd | cwr))//read/write given higher priority over refresh for upto 9trefi
						 begin
						 rfsh_ctr <= rfsh_ctr + 1;
						 if(active_address[ca[30:29]][ca[28:27]] != ca[26:10] | bank_precharged[ca[30:29]][ca[28:27]] == 1)//Row miss => got to wait for precharge/activation
						 begin
							 delay <= bank_precharged[ca[30:29]][ca[28:27]] ? trcd:trp;
							 bank_precharged[ca[30:29]][ca[28:27]] <= 1;
						 end
						 end
						 
					 else if(rfsh_ctr >= trefi)
						 begin
						 rfsh_ctr <= 0;
					    if(~all_precharged)//all banks not precharged, precharge first
							 begin
							 delay <= trp;
							 bank_precharged[0] <= 4'b1111;
							 bank_precharged[1] <= 4'b1111;
							 bank_precharged[2] <= 4'b1111;
							 bank_precharged[3] <= 4'b1111;
							 end
					    end
						 
					 else 
					    rfsh_ctr <= rfsh_ctr + 1;
						 
					 end
		
		read:     begin
					 $display("Controller State = read, time = %0t",  $time);
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 rfsh_ctr <= rfsh_ctr + 1;
					 end
		
		write:    begin
					 $display("Controller State = write, time = %0t",  $time);
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 rfsh_ctr <= rfsh_ctr + 1;
					 end
	   
		refresh:  begin
					 $display("Controller State = refresh, time = %0t",  $time);
					 $display("bank_precharged = %p", bank_precharged);
					 $display("active_address = %p", active_address);
					 delay <= trfc;
					 end
					 
		default: delay <= delay;
	endcase
end				 

//printing idle state
always @ (state)
	begin
	 if(state == idle)
		$display("Controller State = idle, time = %0t",  $time);
	end
		
//output and ret logic
always @ (state)
begin
	case(state)
		waiting:  dcs_n <= 1; //DES command in waiting state
		
		init0:    begin
					 ret <= init1;
					 drst_n <= 0;
					 dcs_n <= 0;
					 dact_n <= 1;
					 cke <= 0;
					 end
					 
		init1:    begin 
					 ret <= init_mrs;
					 drst_n <= 1;
					 dcs_n <= 0;
					 dact_n <= 1;
					 cke <= 0;
					 clkout_t <= clkin; //will need to remove these two lines
					 clkout_c <= ~clkin;
					 end
					 
		init_mrs: begin
					 cke <= 1;
					 ret <= (mrs_ctr == 7) ? init_zq:init_mrs;
					 dcs_n <= (mrs_ctr == 0) ? 1:0;
					 dact_n <= 1;
					 da[16:14] <= 3'b000;
					 da[13:0] = mode_reg_addr;
					 case (mrs_ctr) //finish these !!!!!!
						1: begin //mr3
						   $display("MRS1 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 0;
							dba = 3;
							$display("mr3: %0d", mode_reg_addr);
							end
						2: begin //mr6
							$display("MRS2 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 1;
							dba = 2;
							$display("mr6: %0d", mode_reg_addr);
							end
						3: begin //mr5
							$display("MRS3 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 1;
							dba = 1;
							$display("mr5: %0d", mode_reg_addr);
							end
						4: begin //mr4
							$display("MRS4 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 1;
							dba = 0;
							$display("mr4: %0d", mode_reg_addr);
							end
						5: begin //mr2
							$display("MRS5 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 0;
							dba = 2;
							$display("mr2: %0d", mode_reg_addr);
							end
						6: begin //mr1
							$display("MRS6 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 0;
							dba = 1;
							$display("mr1: %0d", mode_reg_addr);
							end
						7: begin //mr0
							$display("MRS7 IN CONTROLLER AT TIME = %0t", $time);
							dbg = 0;
							dba = 0;
							$display("mr0: %0d", mode_reg_addr);
							end
						default: dcs_n <= 1;
					 endcase
					 end
		
		init_zq:  begin  
					 ret <= all_precharged ? idle:init_zq;
					 dcs_n <= 0;
					 dact_n <= 1;
					 {da[16:14], da[10]} <= all_precharged ? 4'b1101:4'b0101;//ZQ:precharge_all
					 end
		
		idle:     begin

					 if((rfsh_ctr < 9*trefi) & (crd | cwr)) //give precedence to CPU
					 begin
						ret <= bank_precharged[ca[30:29]][ca[28:27]] ? (crd ? read:write):idle;
						
						if(active_address[ca[30:29]][ca[28:27]] != ca[26:10] | bank_precharged[ca[30:29]][ca[28:27]] == 1)
						begin
						 dcs_n <= 0;
						 dact_n <= bank_precharged[ca[30:29]][ca[28:27]] ? 0:1;
						 {da[16:14], da[10]} <= bank_precharged[ca[30:29]][ca[28:27]] ? {ca[26:24], ca[20]}:4'b0100; //activate:precharge_single
						 {da[13:11], da[9:0]} <= {ca[23:21], ca[19:10]};
						 dbg <= ca[30:29];
						 dba <= ca[28:27];
						end

						else
						dcs_n <= 1; //direct jump to read/write without issuing any precharge/activate command
					 end
					 
					 else if(rfsh_ctr >= trefi) //refresh needed
					 begin
						ret <= refresh; //useful only when not all banks precharged
						
						if(all_precharged)//go directly to refresh state
							dcs_n <= 1;
						else //issue a precharge all
						begin
							dcs_n <= 0;
							dact_n <= 1;
							{da[16:14], da[10]} <= 4'b0101;//precharge_all
						end
					 end
					 
					 else //no refresh needed - stay idle
					  dcs_n <= 1;
					  
					 end
		
		read:     begin
					 ret <= idle;
					 dcs_n <= 0;
					 dact_n <= 1;
					 {da[16:14], da[10]} <= 4'b1010;
					 da[9:0] <= ca[9:0];
					 dbg <= ca[30:29];
					 dba <= ca[28:27];
					 end 
					 
		write:    begin
					 ret <= idle;
					 dcs_n <= 0;
					 dact_n <= 1;
					 {da[16:14], da[10]} <= 4'b1000;
					 da[9:0] <= ca[9:0];
					 dbg <= ca[30:29];
					 dba <= ca[28:27];
					 end
		
		refresh:  begin
					 ret <= idle;
					 dcs_n <= 0;
					 dact_n <= 1;
					 da[16:14] <= 3'b001;
					 end
					 
		default:  dcs_n <= 1;	
	endcase
end

//pins for testing
assign curr_state = state;
endmodule
					 
					 
					 
					  	
		
		
		




