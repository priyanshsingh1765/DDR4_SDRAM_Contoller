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
 output [2:0] curr_state,
 output integer delay
);

//timing values for E-die - to be used by FSM wait state
parameter tPW_RESET = 800; //800 is the min spec - actual value dep on the supply Voltage slew rate
parameter internal_init = 400000; //min spec for internal initialization
parameter txpr = 136, tmrd = 8, tmod = 24;
parameter tzqinit = 1024, tzqoper = 512, tzqcs = 128;
parameter trp = 11;
parameter trcd = 11, CL = 11, CWL = 11, tbl8 = 4;
parameter trfc = 128, trefi = 6240;
parameter trrds = 4, trrdl = 5;

//FSM states
parameter init0 = 0, init1 = 1, init_mrs = 2, init_zq = 3; //initialization sequence
parameter waiting = 4;
parameter idle = 5, read = 6, write = 7;

//signals used
reg [2:0] state, next_state, ret;
//integer delay, mrs_ctr; //to be used by the wait state
integer mrs_ctr; 

//status of the banks
reg all_precharged; //all banks precharged
reg [3:0] bank_precharged [3:0]; //individual bank precharged
reg [16:0] active_address [3:0] [3:0];//bg->ba->row

//next state logic
always @ (*)
	begin
		case (state)
			waiting: next_state <= (delay == 0) ? ret:waiting;
			
			idle:    begin
						if(active_address[ca[30:29]][ca[28:27]] == ca[26:10] & bank_precharged[ca[30:29]][ca[28:27]] == 0 & (crd | cwr))
						   next_state <= crd ? read:write; // direct read/write for Row hit
						else
							next_state <= waiting; //Row miss
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
		waiting:  delay <= delay - 1;
		
		init0:    delay <= tPW_RESET;
		
		init1: 	 begin 
					 delay <= internal_init;
					 mrs_ctr <= 0;
					 end
					 
		init_mrs: begin 
					 delay <= (mrs_ctr == 7) ? tmod:((mrs_ctr == 0) ? txpr:tmrd);
					 mrs_ctr <= mrs_ctr + 1;
					 all_precharged <= 0;
					 end
		
		init_zq:  begin
					 delay <= all_precharged ? tzqinit:trp;
					 all_precharged <= 1;
					 bank_precharged[0] <= 4'b1111;
					 bank_precharged[1] <= 4'b1111;
					 bank_precharged[2] <= 4'b1111;
					 bank_precharged[3] <= 4'b1111;
					 end
		
		idle:     begin
					 if((crd | cwr) & (active_address[ca[30:29]][ca[28:27]] != ca[26:10] | bank_precharged[ca[30:29]][ca[28:27]] == 1))//Row miss => got to wait for precharge/activation
						 begin
						 delay <= bank_precharged[ca[30:29]][ca[28:27]] ? trcd:trp;
						 bank_precharged[ca[30:29]][ca[28:27]] <= 1;
						 end
					 end
		
		read:     begin
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 end
		
		write:    begin
					 delay <= CL + tbl8;
					 bank_precharged[ca[30:29]][ca[28:27]] <= 0;
					 active_address[ca[30:29]][ca[28:27]] <= ca[26:10];
					 end
					 
		default: delay <= delay;
	endcase
end				 
		
//output and ret logic
always @ (posedge clkin)
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
							da[16:14] <= 3'b000;
							end
						2: begin //mr6
							da[16:14] <= 3'b000;
							end
						3: begin //mr5
							da[16:14] <= 3'b000;
							end
						4: begin //mr4
							da[16:14] <= 3'b000;
							end
						5: begin //mr2
							da[16:14] <= 3'b000;
							end
						6: begin //mr1
							da[16:14] <= 3'b000;
							end
						7: begin //mr0
							da[16:14] <= 3'b000;
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
					 ret <= bank_precharged[ca[30:29]][ca[28:27]] ? (crd ? read:(cwr ? write: idle)):idle;
					 
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
					 
		default:  dcs_n <= 1;	
	endcase
end

//pins for testing
assign curr_state = state;
endmodule
					 
					 
					 
					  	
		
		
		




