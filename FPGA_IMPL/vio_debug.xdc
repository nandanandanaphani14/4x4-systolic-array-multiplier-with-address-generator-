##=====================================================================
## vio_debug.xdc  --  constraints for vio_debug_top on the ZedBoard
## Target part: xc7z020clg484-1  (Zynq-7000, ZedBoard rev C/D)
##
## Method 2 (VIO + ILA) uses exactly ONE physical pin: the 100 MHz PL
## oscillator.  Everything else travels over the JTAG programming cable.
##
## !!! VERIFY THE CLOCK PIN AGAINST THE DIGILENT MASTER XDC FOR YOUR REV !!!
##=====================================================================

## ---- 100 MHz on-board PL clock (Bank 13, GCLK) ----------------------
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

## ---- Build hygiene --------------------------------------------------
## PL-only (no Processing System) design: silence the harmless
## unconstrained-PS / unused-pin DRCs so bitstream generation completes.
set_property BITSTREAM.GENERAL.UNCONSTRAINEDPINS {Allow} [current_design]

## ---- Debug hub ------------------------------------------------------
## Tell the auto-inserted debug hub what its clock frequency is.  Getting
## this wrong is the #1 cause of "The debug hub core was not detected"
## in the Hardware Manager.  Apply AFTER opt_design / in the implemented
## design (Vivado also accepts it here for most flows).
if {[llength [get_debug_cores -quiet dbg_hub]]} {
    set_property C_CLK_INPUT_FREQ_HZ   100000000 [get_debug_cores dbg_hub]
    set_property C_ENABLE_CLK_DIVIDER  false     [get_debug_cores dbg_hub]
    set_property C_USER_SCAN_CHAIN     1         [get_debug_cores dbg_hub]
    connect_debug_port dbg_hub/clk [get_nets clk]
}

##=====================================================================
## OPTIONAL -- probe INTERNAL nets with an ILA without touching the RTL.
##
## The 13 design files must never be edited, so (* mark_debug *) cannot
## go in the source.  Setting MARK_DEBUG from the XDC is the equivalent,
## non-invasive move: run synthesis once, open the Synthesized Design,
## find the real net names, then uncomment and adjust the lines below and
## re-run synthesis.
##
## Prerequisite: set synthesis -flatten_hierarchy to "none" so these
## hierarchical net names survive.  (QoR cost is irrelevant here -- this
## design has enormous timing margin at 100 MHz.)
##
## Find the exact names first:
##   get_nets -hierarchical *agu_wload*
##   get_nets -hierarchical *agu_valid_in*
##   get_nets -hierarchical *psum*
##=====================================================================
# set_property MARK_DEBUG true [get_nets u_acc/agu_wload]
# set_property MARK_DEBUG true [get_nets u_acc/agu_valid_in]
# set_property MARK_DEBUG true [get_nets u_acc/agu_out_we]
# set_property MARK_DEBUG true [get_nets {u_acc/agu_w_addr[*]}]
# set_property MARK_DEBUG true [get_nets {u_acc/agu_act_addr[*]}]
# set_property MARK_DEBUG true [get_nets {u_acc/agu_out_addr[*]}]



