## 12/2025 
- Completed successful testing of initialization sequence
- Issues with read/write

## 4/02/26
- Refresh tested

## 10/02/26
- Issues with RWCASE - second write prints it correctly but the first write finds it undefined
- Write command - correctly updates the internal bank status registers of the controller
- Printing RWCASE with hit, miss, bad miss is not in sync, rather printing on rwcase events works correctly
- Controller in write state for a longer time than expected - because of the wr being kept high by the CPU
- Activate tested successfully
- 
