## 12/25 
- Initialization sequence tested ✅
- Issues with read/write

## 4/02/26
- Refresh tested ✅

## 10/02/26
- Issues with RWCASE - second write prints it correctly but the first write finds it undefined
- Write command - correctly updates the internal bank status registers of the controller
- Printing RWCASE with hit, miss, bad miss is not in sync, rather printing on rwcase events works correctly
- Controller in write state for a longer time than expected - because of wr being kept high by the CPU
- Activate tested ✅
- Burst Length set to 8 - MR0 - 1052 (PREVIOUSLY OTF)
## 17/02/26
- Precharge testing ❌ - twr violation - happens in CASE 3 + same bank - precharge should happen twr after the last write transaction - no violation across different banks
- Solving tWR(and hence tRTP) - Options: 1. Through ready bit - but contr. has to first know the address 2. New "not ready" state/self loop in idle state with a counter
- Setting twr to 15ns = 12 cycles => mr0 = 540 rather than 1052
## 18/02
- Implemented recovery solution in ddr4 cont
- Write - Write, Read, Refresh testing ✅
- Read - Write, Read, Refresh testing ✅
## 19/02
- Testing bug - active_adress reg is assigned based on current ca in read/write stage and if ca changes in read/write stage a faulty update happens - correct using a reg for ca
