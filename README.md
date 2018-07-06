# FPGA-Snappy-Decompressor
A new kind of hardware decompressor for Snappy decompression. It is a new kind of decompressor architecture which can process more than one literal token and copy token parallelly.

Directory
---
IP: xci Vivado IP files for the decompressor\
Source: Verilog files for the decompressor\
Demo: VHDL file to connect the decompressor to IBM CAPI platform and run a demo\
Software: software to test the decompressor on IBM CAPI platform\
Compression software: a modified version of C-language implementation from Google. It will reduce the data dependency thus get higher decompression speed, while has almost no change on compression ratio\
Document: some document for the decompressor\
(if you want to use decompressor on other platform, only files in IP and Source are needed)

Working platform
----
Currently, the decompressor is used on IBM CAPI with SNAP interface. See: https://github.com/open-power/snap \
The demo will work based on this platform: fetch data from memory, do decompression and send decompression result back

Recommanded compression software
----
If you use the decompression software from Google, the perfromance of this decompression maybe bad for some special data with extremly high data dependency. In this case, it is recommended to use a modified compression software: https://github.com/ChenJianyunp/snappy-c \
In this version, the compression algerithm is slightly changed, but the compression result is still in standard Snappy format. And it will cause almost no change on the compression ratio, while greatly reduce the data dependency and make the parallel decompression more efficient.

Contact
----
If you have some questions or recommendations for this project, please contact Jianyu Chen at this email address: chenjy0046@gmail.com

Parameter of implementation on Vivado:
----
The working frequency of this decompressor on KU115 FPGA (core speed -2) can achive 250MHz when connects to IBM CAPI interface with the following place and route strategy:\
place strategy: Congestion_SpreadLogic_medium\
route: strategy:  AlternateCLBRouting\
On default strategy, the timing constrain will fail due to congestion
