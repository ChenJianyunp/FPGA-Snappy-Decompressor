# FPGA-Snappy-Decompressor (Work-in)
A new kind of hardware decompressor for Snappy decompression. It is a new kind of decompressor architecture which can process more than one literal token and copy token parallelly.

Directory and file
---
user_ip: xci Vivado IP files for the decompressor\
source: Verilog files for the decompressor\
interface: VHDL file to connect the decompressor to IBM CAPI platform and run a demo\
sw: software to test the decompressor on IBM CAPI platform\
Doc: documents for the decompressor\
(if you want to use the decompressor on other platform, only files in user_ip and source are needed)

Publication
------
A work-in-paper is accepted in the coference CODES+ISSS, see: https://ieeexplore.ieee.org/document/8525953

Working platform
----
Currently, the decompressor is used on IBM CAPI with SNAP interface. See: https://github.com/open-power/snap \
The demo will work based on this platform: fetch data from memory, do decompression and send decompression result back

Recommended compression software
----
If you use the decompression software from Google, the perfromance of this decompression maybe bad for some special data with extremly high data dependency. In this case, it is recommended to use a modified compression software: https://github.com/ChenJianyunp/snappy-c \
In this version, the compression algerithm is slightly changed, but the compression result is still in standard Snappy format. And it will cause almost no change on the compression ratio, while greatly reduce the data dependency and make the parallel decompression more efficient.

Contact
----
If you have some questions or recommendations for this project, please contact Jianyu Chen at this email address: chenjy0046@gmail.com

Parameters of implementation on Vivado:
----
The working frequency of this decompressor on KU115 FPGA (core speed -2) can achieve 250MHz when connects to IBM CAPI interface with the following place and route strategy:\
place strategy: Congestion_SpreadLogic_medium\
route: strategy:  AlternateCLBRouting\
On default strategy, the timing constrain may fail due to congestion

Update log
----
18-11-2018: Fix a bug on the length of garbage_cnt\
25-11-2018: Fix a bug of overflow on page_fifo\
26-11-2018: Fix a bug loss the last slice
