# CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo
# Released under the MIT license https://opensource.org/licenses/mit

set top_dir [pwd]
set proj_name main
set part_name xc7a35tcsg324-1
set src_files [concat $top_dir/config.vh [glob -nocomplain $top_dir/src/*.v $top_dir/src/**/*.v]]
set nproc [exec nproc]

# Default values
set ncores 4
set imem_size ""
set dmem_size ""
set freq 140

create_project -force $proj_name $top_dir/vivado -part $part_name
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Parse command-line arguments
for {set i 0} {$i < $argc} {incr i} {
    if {[lindex $argv $i] eq "--ncores"} {
        incr i
        if {$i < $argc} {
            set ncores [lindex $argv $i]
            puts "NCORES set to: $ncores"
        } else {
            puts "Error: --ncores requires a value"
            exit 1
        }
    } elseif {[lindex $argv $i] eq "--imem_size"} {
        incr i
        if {$i < $argc} {
            set imem_size [lindex $argv $i]
            puts "IMEM_SIZE set to: $imem_size"
        } else {
            puts "Error: --imem_size requires a value"
            exit 1
        }
    } elseif {[lindex $argv $i] eq "--dmem_size"} {
        incr i
        if {$i < $argc} {
            set dmem_size [lindex $argv $i]
            puts "DMEM_SIZE set to: $dmem_size"
        } else {
            puts "Error: --dmem_size requires a value"
            exit 1
        }
    } elseif {[lindex $argv $i] eq "--clk_freq"} {
        incr i
        if {$i < $argc} {
            set freq [lindex $argv $i]
            puts "CLK_FREQ_MHZ set to: $freq"
        } else {
            puts "Error: --clk_freq requires a value"
            exit 1
        }
    } elseif {[lindex $argv $i] eq "--hls"} {
        puts "HLS mode enabled. Adding HLS source files."
        set src_files [concat $src_files [glob -nocomplain $top_dir/cfu/*.v]]
        set tcl_files [glob -nocomplain $top_dir/cfu/*.tcl]
        foreach tcl_file $tcl_files {source $tcl_file}
        set_property verilog_define [list "NCORES=$ncores" "USE_HLS"] [get_filesets sources_1]
        update_compile_order -fileset sources_1
    }
}

# Set defines
set defines [list "NCORES=$ncores"]
if {$imem_size ne ""} {
    lappend defines "IMEM_SIZE=$imem_size"
}
if {$dmem_size ne ""} {
    lappend defines "DMEM_SIZE=$dmem_size"
}
if {[lsearch $defines "USE_HLS"] < 0 && [get_property verilog_define [get_filesets sources_1]] ne ""} {
    # keep any HLS define already set in the HLS branch
    foreach d [get_property verilog_define [get_filesets sources_1]] {
        if {[lsearch $defines $d] < 0} {lappend defines $d}
    }
}
set_property verilog_define $defines [get_filesets sources_1]

add_files -force -scan_for_includes $src_files
add_files -fileset constrs_1 $top_dir/main.xdc

if {[regexp {CRITICAL WARNING:} [check_syntax -return_string -fileset sources_1]]} {
    puts "Syntax check failed. Exiting..."
    exit 1
}

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $freq \
    CONFIG.JITTER_SEL {Min_O_Jitter} \
    CONFIG.MMCM_BANDWIDTH {HIGH} \
] [get_ips clk_wiz_0]

generate_target all [get_files  $top_dir/vivado/$proj_name.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci]
create_ip_run [get_ips clk_wiz_0]

update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream -jobs $nproc
wait_on_run impl_1

open_run impl_1
report_utilization -hierarchical
report_timing
close_project
