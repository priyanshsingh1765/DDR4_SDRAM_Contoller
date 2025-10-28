module Testbench;

reg clkin = 0; 
reg crst_n, crd, cwr;
reg [30: 0] ca;
reg [3:0] cwdat;
wire [3:0] crdat;

wire [3:0] ddq;
wire ddqs_t, ddqs_c;
wire drst_n, clkout_t, clkout_c, cke;
wire [16:0] da;
wire dcs_n, dact_n;
wire [1:0] dbg, dba;
//pins for testing 
wire [3:0] curr_state;
wire [10:0] delay;
wire [15:0] rfsh_ctr;

always 
begin
	#10;
	clkin = ~clkin;
end

//turning the controller on/resetting it
initial 
begin
   crst_n = 0;
	#20;
	crst_n = 1;
end

always 
begin
//	#8041350; //includes only refresh-CPU clashes
	#8145690; //includes refresh-CPU clashes as well as only refresh
	ca[30:29] = 2'b01;
	ca[28:27] = 2'b11;
	ca[26:0]  = 3193;
	crd = 1;
	cwr = 0;
	#600;
	ca[30:29] = 2'b00;
	ca[28:27] = 2'b11;
	ca[26:0]  = 3193;
	crd = 0;
	cwr = 1;
end
ddr4_cont dut (clkin, crst_n, crd, cwr, ca, cwdat, crdat, ddq, ddqs_t, ddqs_c, drst_n, clkout_t, clkout_c, cke, da, dcs_n, dact_n, dbg, dba, curr_state, delay, rfsh_ctr);

endmodule