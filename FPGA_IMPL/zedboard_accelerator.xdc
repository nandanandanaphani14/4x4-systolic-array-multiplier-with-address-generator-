##=====================================================================
## zedboard_accelerator.xdc  --  constraints for fpga_top on the ZedBoard
## Target part: xc7z020clg484-1  (Zynq-7000, ZedBoard rev C/D)
##
## !!! VERIFY PIN/IOSTANDARD AGAINST THE OFFICIAL DIGILENT MASTER XDC !!!
## Board revisions differ. The safest workflow is to download the Digilent
## "zedboard_master.xdc", uncomment the CLK / SW / LD / BTN lines you need,
## and rename the ports to match fpga_top (clk, sw[*], btnc/u/d/l/r, led[*]).
## The values below match the widely-used Digilent master for rev C/D.
##=====================================================================

## ---- 100 MHz on-board clock (Bank 13, GCLK) -------------------------
set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

## ---- 8 slide switches  SW0..SW7 ------------------------------------
set_property -dict {PACKAGE_PIN F22 IOSTANDARD LVCMOS25} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS25} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS25} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS25} [get_ports {sw[3]}]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS25} [get_ports {sw[4]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS25} [get_ports {sw[5]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS25} [get_ports {sw[6]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS25} [get_ports {sw[7]}]

## ---- 8 LEDs  LD0..LD7 ----------------------------------------------
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]

## ---- 5 push-buttons  (C U D L R) -----------------------------------
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports btnc]   ;# center = COMMIT
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS25} [get_ports btnu]   ;# up     = START
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS25} [get_ports btnd]   ;# down   = RESET
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS25} [get_ports btnl]   ;# left   = reserved
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS25} [get_ports btnr]   ;# right  = reserved

## ---- Build hygiene --------------------------------------------------
## This is a PL-only (no Processing System) design. Silence the harmless
## unconstrained-PS / unused-pin DRCs so bitstream generation completes.
set_property BITSTREAM.GENERAL.UNCONSTRAINEDPINS {Allow} [current_design]
