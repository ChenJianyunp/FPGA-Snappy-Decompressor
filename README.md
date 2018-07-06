# FPGA-Snappy-Decompressor
A new kind of hardware decompressor for Snappy decompression. It is a new kind of decompressor architecture which can process more than one literal token and copy token parallelly.\

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
The demo will work based on this platform: fetch data from memory, do decompression and send decompression result back\

Contact
----
If you have some questions or recommendations for this project, please contact me.\
Email address: chenjy0046@gmail.com\

Parameter of implementation on Vivado:
----
The working frequency of this decompressor on KU115 FPGA (core speed -2) can achive 250MHz when connects to IBM CAPI interface with the following place and route strategy:\
place strategy: Congestion_SpreadLogic_medium\
route: strategy:  AlternateCLBRouting\
On default strategy, the timing constrain will fail due to congestion\
