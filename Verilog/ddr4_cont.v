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
 output integer delay, rfsh_ctr, rec_ctr //RECOVERY_EDIT
);

//timing values for E-die - to be used by FSM wait state
parameter tPW_RESET = 800; //800 is the min spec - actual value dep on the supply Voltage slew rate
parameter internal_init = 400000; //min spec for internal initialization
parameter txpr = 136, tmrd = 8, tmod = 24;
parameter tzqinit = 1024, tzqoper = 512, tzqcs = 128;
parameter trp = 11;
parameter trcd = 11, CL = 11, CWL = 11, tbl8 = 4;
parameter trfc = 128, trefi = 6240; //+trfc because of upcount in waiting state
parameter trrds = 4, trrdl = 5;
parameter twr = 12, trtp = 6; //RECOVERY_EDIT

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

//RECOVERY_EDIT
integer recovery_ctr;
reg [3:0] prev_bank; //bg,ba - prev bank where a read/write was done

//next state logic
always @ (*)
	begin
		case (state)
			waiting: next_state <= (delay == 0) ? ret:waiting;
			
			idle:    begin
						if((rfsh_ctr < 9*trefi) & (crd | cwr))//higher priority to CPU read/write cmds
						   if(active_address[ca[30:29]][ca[28:27]] == ca[26:10] & bank_precharged[ca[30:29]][ca[28:27]] == 0)
								next_state <= crd ? read:write; // direct read/write for Row hit
							else
								next_state <= waiting;//Row miss - need to activate or precharge
								
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
					 
		init0:    delay <= tPW_RESET;
		
		init1: 	 begin 
					 delay <= internal_init;
					 mrs_ctr <= 0;
					 rfsh_ctr <= 0;
					 end
					 
		init_mrs: begin 
					 delay <= (mrs_ctr == 7) ? tmod:((mrs_ctr == 0) ? txpr:tmrd);
					 mrs_ctr <= mrs_ctr + 1;
					 bank_precharged[0] <= 4'b0000;
					 bank_precharged[1] <= 4'b0000;
					 bank_precharged[2] <= 4'b0000;
					 bank_precharged[3] <= 4'b0000;
					 end
		
		init_zq:  begin
					 delay <= all_precharged ? tzqinit:trp;
					 bank_precharged[0] <= 4'b1111;
					 bank_precharged[1] <= 4'b1111; 
					 bank_precharged[2] <= 4'b1111;
					 bank_precharged[3] <= 4'b1111;
					 end
		
		idle:     begin
					 if((rfsh_ctr < 9*trefi) & (crd | cwr))//read/write given higher priority over refresh for upto 9trefi
						 begin
						 rfsh_ctr <= rfsh_ctr + 1;
						 if(active_address[ca[30:29]][ca[28:27]] != ca[26:10] | bank_precharged[ca[30:29]][ca[28:27]] == 1)//Row miss => got to wait for precharge/activation
						 begin
							 delay <= bank_precharged[ca[30:29]][ca[28:27]] ? trcd:(((prev_bank == ca[30:27]) & (recovery_ctr != 0)) ? (recovery_ctr - 1):trp);//RECOVERY_EDIT
							 bank_precharged[ca[30:29]][ca[28:27]] <= ((prev_bank == ca[30:27]) & (recovery_ctr != 0)) ? bank_precharged[ca[30:29]][ca[28:27]]:1;//RECOVERY_EDIT
						 end
						 end
						 
					 else if(rfsh_ctr >= trefi)
						 begin
							 if(~all_precharged)//all banks not precharged, precharge first
								 begin
									if((prev_bank == ca[30:27]) & (recovery_ctr != 0)) //RECOVERY_EDIT
										begin
										 delay <= recovery_ctr - 1;
										end
									else
										begin
										 rfsh_ctr <= 0;
										 delay <= trp;
										 bank_precharged[0] <= 4'b1111;
										 bank_precharged[1] <= 4'b1111;
										 bank_precharged[2] <= 4'b1111;
										 bank_precharged[3] <= 4'b1111;
										end
								 end
							  else
								 rfsh_ctr <= 0;
					    end
					 else 
					    rfsh_ctr <= rfsh_ctr + 1;	 
					 end
		
		read:     begin
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 rfsh_ctr <= rfsh_ctr + 1;
					 end
		
		write:    begin
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 rfsh_ctr <= rfsh_ctr + 1;
					 end
	   
		refresh:  begin
					 delay <= trfc;
					 end
					 
		default: delay <= delay;
	endcase
end				 

//RECOVERY COUNTER LOGIC //RECOVERY_EDIT
always @ (posedge clkin)
begin
	case(state)
	   init0: recovery_ctr <= 0;
		read: recovery_ctr <= CL + tbl8 + trtp;
		write: recovery_ctr <= CL + tbl8 + twr;
		default: begin
						if(recovery_ctr > 0)
							recovery_ctr <= recovery_ctr - 1;
				   end
   endcase
end

//output and ret logic
always @ (posedge clkin) // Will need event control using state as using clk edge control delays output by one cycle
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
					 case (mrs_ctr) //finish these !!!!!!
						1: begin //mr3
							da[13:0] <= 0;
							end
						2: begin //mr6
							da[13:0] <= 2063;
							end
						3: begin //mr5
							da[13:0] <= 0;
							end
						4: begin //mr4
							da[13:0] <= 4096;
							end
						5: begin //mr2
							da[13:0] <= 136;
							end
						6: begin //mr1
							da[13:0] <= 1;
							end
						7: begin //mr0
							da[13:0] <= 1053;
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
						 dcs_n <= ((prev_bank == ca[30:27]) & (recovery_ctr != 0)); //RECOVERY_EDIT
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
					   if (~((prev_bank == ca[30:27]) & (recovery_ctr != 0))) //RECOVERY_EDIT
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
						else
							begin
								ret <= idle;
								dcs_n <= 1;
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
					 prev_bank <= ca[30:27]; //RECOVERY_EDIT
					 end 
					 
		write:    begin
					 ret <= idle;
					 dcs_n <= 0;
					 dact_n <= 1;
					 {da[16:14], da[10]} <= 4'b1000;
					 da[9:0] <= ca[9:0];
					 dbg <= ca[30:29];
					 dba <= ca[28:27];
					 prev_bank <= ca[30:27]; //RECOVERY_EDIT
					 end
		
		refresh:  begin
					 ret <= idle;
					 dcs_n <= 0;
					 dact_n <= 1;
					 da[16:14] <= 4'b001;
					 end
					 
		default:  dcs_n <= 1;	
	endcase
end

//pins for testing 
assign curr_state = state;
always @ * //RECOVERY_EDIT
 rec_ctr = recovery_ctr;
endmodule 