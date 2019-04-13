
## Env Variables

set action_root [lindex $argv 0]
set fpga_part  	[lindex $argv 1]
#set fpga_part    xcvu9p-flgb2104-2l-e
#set action_root ../

set aip_dir 	$action_root/ip
set log_dir     $action_root/../../hardware/logs
set log_file    $log_dir/create_action_ip.log
set src_dir 	$aip_dir/action_ip_prj/action_ip_prj.srcs/sources_1/ip

## Create a new Vivado IP Project
puts "\[CREATE_ACTION_IPs...\] start [clock format [clock seconds] -format {%T %a %b %d %Y}]"
#puts "                        FPGACHIP = $fpga_part"
#puts "                        ACTION_ROOT = $action_root"
#puts "                        Creating IP in $src_dir"
create_project action_ip_prj $aip_dir/action_ip_prj -force -part $fpga_part -ip >> $log_file

# Project IP Settings

puts "                        generating IP blockram"
#add_files -norecurse                         $src_dir/blockram/blockram.xci >> $log_file
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.* -module_name blockram  >> $log_file
set_property -dict [list                                              \
        CONFIG.Memory_Type {Simple_Dual_Port_RAM}                     \
        CONFIG.Assume_Synchronous_Clk {true}                          \
        CONFIG.Write_Width_A {72}                                     \
        CONFIG.Write_Depth_A {512}                                    \
        CONFIG.Read_Width_A {72}                                      \
        CONFIG.Operating_Mode_A {READ_FIRST}                          \
        CONFIG.Write_Width_B {72}                                     \
        CONFIG.Read_Width_B {72}                                      \
        CONFIG.Operating_Mode_B {READ_FIRST}                          \
        CONFIG.Enable_B {Use_ENB_Pin}                                 \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false}     \
        CONFIG.Register_PortB_Output_of_Memory_Primitives {false}     \
        CONFIG.Port_B_Clock {100}                                     \
        CONFIG.Port_B_Enable_Rate {100}                               \
        CONFIG.Use_Byte_Write_Enable {true}                           \
        CONFIG.Fill_Remaining_Memory_Locations {true}                 \
        ] [get_ips blockram]

set_property generate_synth_checkpoint false [get_files $src_dir/blockram/blockram.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/blockram/blockram.xci] >> $log_file
generate_target all                          [get_files $src_dir/blockram/blockram.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/blockram/blockram.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/blockram/blockram.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file


#add_files -norecurse                         $src_dir/data_fifo/data_fifo.xci >> $log_file
create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.* -module_name data_fifo  >> $log_file
set_property -dict [list                                              \
        CONFIG.Fifo_Implementation {Common_Clock_Block_RAM}           \
        CONFIG.asymmetric_port_width {true}                           \
        CONFIG.Input_Data_Width {512}                                 \
        CONFIG.Input_Depth {512}                                      \
        CONFIG.Output_Data_Width {128}                                \
        CONFIG.Output_Depth {2048}                                    \
        CONFIG.Use_Embedded_Registers {false}                         \
        CONFIG.Almost_Full_Flag {true}                                \
        CONFIG.Valid_Flag {true}                                      \
        CONFIG.Use_Extra_Logic {true}                                 \
        CONFIG.Data_Count_Width {9}                                   \
        CONFIG.Write_Data_Count_Width {10}                            \
        CONFIG.Read_Data_Count_Width {12}                             \
        CONFIG.Programmable_Full_Type {Single_Programmable_Full_Threshold_Constant} \
        CONFIG.Full_Threshold_Assert_Value {500}                      \
        CONFIG.Full_Threshold_Negate_Value {499}                      \
        ] [get_ips data_fifo]

set_property generate_synth_checkpoint false [get_files $src_dir/data_fifo/data_fifo.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/data_fifo/data_fifo.xci] >> $log_file
generate_target all                          [get_files $src_dir/data_fifo/data_fifo.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/data_fifo/data_fifo.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/data_fifo/data_fifo.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file


#add_files -norecurse                         $src_dir/debugram/debugram.xci >> $log_file
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.* -module_name debugram  >> $log_file
set_property -dict [list                                              \
        CONFIG.Memory_Type {Simple_Dual_Port_RAM}                     \
        CONFIG.Assume_Synchronous_Clk {true}                          \
        CONFIG.Write_Width_A {64}                                     \
        CONFIG.Write_Depth_A {512}                                    \
        CONFIG.Read_Width_A {64}                                      \
        CONFIG.Operating_Mode_A {READ_FIRST}                          \
        CONFIG.Write_Width_B {64}                                     \
        CONFIG.Read_Width_B {64}                                      \
        CONFIG.Operating_Mode_B {READ_FIRST}                          \
        CONFIG.Enable_B {Use_ENB_Pin}                                 \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false}     \
        CONFIG.Register_PortB_Output_of_Memory_Primitives {false}     \
        CONFIG.Port_B_Clock {100}                                     \
        CONFIG.Port_B_Enable_Rate {100}                               \
        CONFIG.Use_Byte_Write_Enable {true}                           \
        CONFIG.Byte_Size {8}                                          \
        CONFIG.Write_Width_A {64}                                     \
        CONFIG.Read_Width_A {64}                                      \
        CONFIG.Fill_Remaining_Memory_Locations {true}                 \
        ] [get_ips debugram]

set_property generate_synth_checkpoint false [get_files $src_dir/debugram/debugram.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/debugram/debugram.xci] >> $log_file
generate_target all                          [get_files $src_dir/debugram/debugram.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/debugram/debugram.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/debugram/debugram.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file


#add_files -norecurse                         $src_dir/page_fifo/page_fifo.xci >> $log_file
create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.* -module_name page_fifo  >> $log_file
set_property -dict [list                                              \
        CONFIG.Input_Data_Width {181}                                 \
        CONFIG.Input_Depth {512}                                      \
        CONFIG.Output_Data_Width {181}                                \
        CONFIG.Output_Depth {512}                                     \
        CONFIG.Valid_Flag {true}                                      \
        CONFIG.Data_Count_Width {9}                                   \
        CONFIG.Write_Data_Count_Width {9}                             \
        CONFIG.Read_Data_Count_Width {9}                              \
        CONFIG.Programmable_Full_Type {Single_Programmable_Full_Threshold_Constant} \
        CONFIG.Full_Threshold_Assert_Value {500}                      \
        CONFIG.Full_Threshold_Negate_Value {499}                      \
        ] [get_ips page_fifo]

set_property generate_synth_checkpoint false [get_files $src_dir/page_fifo/page_fifo.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/page_fifo/page_fifo.xci] >> $log_file
generate_target all                          [get_files $src_dir/page_fifo/page_fifo.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/page_fifo/page_fifo.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/page_fifo/page_fifo.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file

#add_files -norecurse                         $src_dir/result_ram/result_ram.xci >> $log_file
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.* -module_name result_ram  >> $log_file
set_property -dict [list                                             \
        CONFIG.Memory_Type {Simple_Dual_Port_RAM}                     \
        CONFIG.Use_Byte_Write_Enable {true}                           \
        CONFIG.Write_Width_A {72}                                     \
        CONFIG.Write_Depth_A {512}                                    \
        CONFIG.Read_Width_A {72}                                      \
        CONFIG.Operating_Mode_A {READ_FIRST}                          \
        CONFIG.Write_Width_B {72}                                     \
        CONFIG.Read_Width_B {72}                                      \
        CONFIG.Enable_B {Use_ENB_Pin}                                 \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false}     \
        CONFIG.Register_PortB_Output_of_Memory_Primitives {false}     \
        CONFIG.Fill_Remaining_Memory_Locations {true}                 \
        CONFIG.Port_B_Clock {100}                                     \
        CONFIG.Port_B_Enable_Rate {100}                               \
        ] [get_ips result_ram]

set_property generate_synth_checkpoint false [get_files $src_dir/result_ram/result_ram.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/result_ram/result_ram.xci] >> $log_file
generate_target all                          [get_files $src_dir/result_ram/result_ram.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/result_ram/result_ram.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/result_ram/result_ram.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file


#add_files -norecurse                         $src_dir/unsolved_fifo/unsolved_fifo.xci >> $log_file
create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.* -module_name unsolved_fifo  >> $log_file
set_property -dict [list                                              \
        CONFIG.Fifo_Implementation {Common_Clock_Block_RAM}           \
        CONFIG.Input_Data_Width {33}                                  \
        CONFIG.Input_Depth {512}                                      \
        CONFIG.Output_Data_Width {33}                                 \
        CONFIG.Output_Depth {512}                                     \
        CONFIG.Use_Embedded_Registers {false}                         \
        CONFIG.Almost_Full_Flag {true}                                \
        CONFIG.Valid_Flag {true}                                      \
        CONFIG.Data_Count {true}                                      \
        CONFIG.Data_Count_Width {9}                                   \
        CONFIG.Write_Data_Count_Width {9}                             \
        CONFIG.Read_Data_Count_Width {9}                              \
        CONFIG.Programmable_Full_Type {Single_Programmable_Full_Threshold_Constant} \
        CONFIG.Full_Threshold_Assert_Value {450}                      \
        CONFIG.Full_Threshold_Negate_Value {449}                      \
        ] [get_ips unsolved_fifo]

set_property generate_synth_checkpoint false [get_files $src_dir/unsolved_fifo/unsolved_fifo.xci] >> $log_file
generate_target {instantiation_template}     [get_files $src_dir/unsolved_fifo/unsolved_fifo.xci] >> $log_file
generate_target all                          [get_files $src_dir/unsolved_fifo/unsolved_fifo.xci] >> $log_file
export_ip_user_files -of_objects             [get_files $src_dir/unsolved_fifo/unsolved_fifo.xci] -no_script -force >> $log_file
export_simulation -of_objects                [get_files $src_dir/unsolved_fifo/unsolved_fifo.xci] -directory $aip_dir/ip_user_files/sim_scripts -force >> $log_file

close_project
puts "\[CREATE_ACTION_IPs...\] done  [clock format [clock seconds] -format {%T %a %b %d %Y}]"
