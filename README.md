# FPGA-Snappy-Decompressor (Work-in)
An FPGA-based hardware Snappy decompressor. This is a new kind of decompressor architecture that can process multiple literal token and copy token in parallel.

Current State
---
Simulation: xsim+snap(POWER9+CAPI2.0+ADM9V3) under 250MHz\
Measurement: POWER9+CAPI2.0+ADM9V3 under 250MHz\
Future: 1) Move to OpenCAPI Platform; 2) Multiple engines

Working platform
----
Currently, the decompressor is used on IBM CAPI 2.0 with SNAP interface. See: https://github.com/open-power/snap \
The demo will work based on this platform: fetch data from memory, do decompression and send decompression result back

Extra Steps (will fix in a future IP-free version)
----
Currently, this project utilizes some IP cores which needs extra steps to do the simulation and to build the image.
1) Copy all the IPs(.xci files) in the user_ip folder to your IP folder.
2) Update these IPs if necessary.
3) Build the project together with the IPs.

Directory and file
---
user_ip: xci Vivado IP files for the decompressor\
source: Verilog files for the decompressor\
interface: VHDL file to connect the decompressor to IBM CAPI platform and run a demo\
sw: software to test the decompressor on IBM CAPI platform\
Doc: documents for the decompressor\
(if you want to use the decompressor on other platform, only files in user_ip and source are needed)

Recommended compression software
----
If you use the decompression software from Google, the perfromance of this decompression maybe bad for some special data with extremly high data dependency. In this case, it is recommended to use a modified compression software: https://github.com/ChenJianyunp/snappy-c \
In this version, the compression algerithm is slightly changed, but the compression result is still in standard Snappy format. And it will cause almost no change on the compression ratio, while greatly reduce the data dependency and make the parallel decompression more efficient.

Parameters of implementation on Vivado:
----
Currently, this decompressor pass the test building on ADM-9V3 FPGA card (FPGA: XCVU3P-2 - FFVC1517) in a clock speed of 250MHz. Please choose the the following place and route strategy:\
place strategy: Congestion_SpreadLogic_medium\
route: strategy:  AlternateCLBRouting\
On default strategy, the timing constrain may fail due to congestion

Publication
------
A work-in-paper is accepted in the coference CODES+ISSS, see: https://ieeexplore.ieee.org/document/8525953

Contact
----
If you have some questions or recommendations for this project, please contact Jianyu Chen(chenjy0046@gmail.com) or Jian Fang(fangjian.alpc@gmail.com)

Update log
----
| Jianyu Chen | 18-11-2018: Fix a bug on the length of garbage_cnt\
| Jianyu Chen | 25-11-2018: Fix a bug of overflow on page_fifo\
| Jianyu Chen | 26-11-2018: Fix a bug loss the last slice\
| Jian Fang   | 22-01-2019: Fix a bug in handshake of AXI protocol (1.read/write length; 2.FSM for input that less than 4KB)\
| Jian Fang   | 01-02-2019: Fix a bug on app_ready signal\
| Jian Fang   | 01-02-2019: Fix a bug on write responses(bresp signal, need to wait until the last bresp back for the write data)\
| Jianyu Chen | 04-02-2019: Fix the bug in the calculation of token length of 3Byte literal token\
| Jianyu Chen | 05-02-2019: Fix a bug when calculate the length of a literal token within a slice\
| Jianyu Chen | 05-02-2019: Fix the bug in checking the empty of decompressor when the file is very small\
| Jian Fang   | 05-03-2019: Fix the bug of input/output of 'data_in' and 'wr_en' signals in the parser fifo (both lit and copy)\
| Jianyu Chen | 28-03-2019: Fix the bug on the wrong literature size on parser
