#=====================================================================
# vio_demo.tcl -- drive the 4x4 systolic accelerator from the Vivado
#                 Hardware Manager Tcl console, over JTAG, via VIO.
#
# Runs the T5 golden case (identical to the simulation regression):
#
#      A (4x4)              W (4x4)              C = A x W
#   [ 1 0 0 0 ]        [  1  2  3  4 ]        [  1  2  3  4 ]
#   [ 0 1 0 0 ]   x    [  5  6  7  8 ]   =    [  5  6  7  8 ]
#   [ 0 0 1 0 ]        [  9 10 11 12 ]        [  9 10 11 12 ]
#   [ 1 1 1 1 ]        [ 13 14 15 16 ]        [ 28 32 36 40 ]
#
# USAGE (Hardware Manager Tcl console, after Program Device):
#   cd <path>/FPGA_IMPL
#   source vio_demo.tcl
#   accel_demo
#
# Other entry points:
#   accel_probes                 list the probe names Vivado assigned
#   accel_write_w <addr> <hex>   write one weight word  (addr 0..3)
#   accel_write_a <addr> <hex>   write one activation word (addr 0..255)
#   accel_run <nvec>             pulse start for an nvec-vector job
#   accel_read <addr>            read output_mem[addr], print 4 int32 lanes
#=====================================================================

#---------------------------------------------------------------------
# Connect and cache the VIO object.
#
# NOTE: a bare `get_hw_vios` only works when a hw_device is *current*.
# After Program Device that is usually true, but if you clicked around
# in the GUI it may not be -- so select the device explicitly.
#---------------------------------------------------------------------
proc accel_vio {} {
    if {[llength [get_hw_targets -quiet]] == 0} {
        error "No hardware target open. Do: Open Hardware Manager -> Open Target -> Auto Connect."
    }
    # make sure a device is current (xc7z020 is the PL TAP; arm_dap is the PS)
    set dev [lindex [get_hw_devices -quiet xc7z020*] 0]
    if {$dev ne ""} { current_hw_device $dev }

    set vios [get_hw_vios -quiet]
    if {[llength $vios] == 0} {
        error "No VIO core found.  Checklist:\
             \n  1. Program Device completed on xc7z020_1 (not arm_dap_0)\
             \n  2. the .ltx debug probes file was loaded alongside the .bit\
             \n  3. the Hardware pane shows hw_vio_1 under the device\
             \n  4. if it shows 'debug hub not detected', see VIO_ILA.pdf section 16"
    }
    return [lindex $vios 0]
}

#---------------------------------------------------------------------
# Resolve a probe by name.
#
# Vivado names each hw_probe after the net attached to the VIO port, but
# the exact string varies by version -- "vio_w_wdata" in some, a
# hierarchical "vio_debug_top_i/vio_w_wdata" in others.  So:
#   1. try an exact match on the tail of the name (fast, unambiguous)
#   2. fall back to a substring match
#   3. ALWAYS filter by direction, so a radix/value call can never land
#      on the wrong probe
# On ambiguity, list the candidates rather than silently picking one.
#---------------------------------------------------------------------
proc accel_probe {name dir} {
    set vio [accel_vio]
    set all [get_hw_probes -quiet -of_objects $vio]
    set cand {}
    foreach p $all {
        if {[get_property DIRECTION $p] ne $dir} { continue }
        set n [get_property NAME $p]
        set tail [lindex [split $n /] end]
        if {$tail eq $name} { return $p }          ;# exact tail match wins
        if {[string match "*$name*" $n]} { lappend cand $p }
    }
    if {[llength $cand] == 1} { return [lindex $cand 0] }
    if {[llength $cand] == 0} {
        error "No $dir probe matching '$name'.  Run accel_probes to list the real names."
    }
    set names {}
    foreach p $cand { lappend names [get_property NAME $p] }
    error "Ambiguous $dir probe '$name' -> [join $names {, }].  Use a longer name."
}

proc accel_probes {} {
    puts "\n-- probes on [accel_vio] --"
    foreach p [get_hw_probes -of_objects [accel_vio]] {
        puts [format "   %-44s dir=%-6s width=%s" \
              [get_property NAME $p] \
              [get_property DIRECTION $p] \
              [get_property PROBE_WIDTH $p]]
    }
}

#---------------------------------------------------------------------
# Set one probe_out and push it to the device.
# set_property stages the value LOCALLY; commit_hw_vio is what actually
# drives it over JTAG.  Forgetting the commit is the #1 scripting bug.
#---------------------------------------------------------------------
proc accel_set {name value {radix HEX}} {
    set p [accel_probe $name OUTPUT]
    set_property OUTPUT_VALUE_RADIX $radix $p
    set_property OUTPUT_VALUE $value $p
    commit_hw_vio $p
}

#---------------------------------------------------------------------
# Read one probe_in.  refresh_hw_vio PULLS from the device; INPUT_VALUE
# without a preceding refresh is a stale cached snapshot.
#---------------------------------------------------------------------
proc accel_get {name {radix HEX}} {
    set vio [accel_vio]
    refresh_hw_vio $vio
    set p [accel_probe $name INPUT]
    set_property INPUT_VALUE_RADIX $radix $p
    return [get_property INPUT_VALUE $p]
}

#---------------------------------------------------------------------
# One host write to weight_mem[addr]. The *_we probe is edge-detected in
# vio_debug_top (oneshot), so 0->1 gives exactly one clock of host_w_we.
# Drive it back to 0 to re-arm for the next write.
#---------------------------------------------------------------------
proc accel_write_w {addr data} {
    accel_set vio_w_wdata $data
    accel_set vio_w_addr  [format %X $addr]      ;# 2-bit bus: weight_mem is 4 deep
    accel_set vio_w_we_lvl 1 BINARY
    accel_set vio_w_we_lvl 0 BINARY
}

# NOTE the address widths are deliberately different:
#   vio_w_addr is 2 bits  -> weight_mem is 4 x 32   (one matrix, held once)
#   vio_a_addr is 8 bits  -> a_mem      is 256 x 32 (a STREAM of vectors)
# Both take 4 writes for this 4x4 demo, but the activation bus is 8 bits
# because the same weight load can be reused against up to 256 vectors.
proc accel_write_a {addr data} {
    accel_set vio_a_wdata $data
    accel_set vio_a_addr  [format %X $addr]      ;# 8-bit bus: a_mem is 256 deep
    accel_set vio_a_we_lvl 1 BINARY
    accel_set vio_a_we_lvl 0 BINARY
}

#---------------------------------------------------------------------
# Launch a job. The whole thing takes nvec+13 clocks = 170 ns for nvec=4,
# so by the time the next JTAG transaction lands it is long finished --
# done_sticky is what you actually poll.
#---------------------------------------------------------------------
proc accel_run {{nvec 4} {actbase 0} {outbase 0}} {
    accel_set vio_num_vectors [format %X $nvec]
    accel_set vio_act_base    [format %X $actbase]
    accel_set vio_out_base    [format %X $outbase]
    set before [accel_get done_count]
    accel_set vio_start_lvl 1 BINARY
    accel_set vio_start_lvl 0 BINARY
    for {set i 0} {$i < 20} {incr i} {
        if {[accel_get done_sticky BINARY] == 1} {
            puts "  job done  (done_count [accel_get done_count] , was $before)"
            return
        }
    }
    error "Timed out waiting for done_sticky. Check that rst_n released\
           (POR is 65536 clocks) and that num_vectors is not 0."
}

#---------------------------------------------------------------------
# Read output_mem[addr] and unpack the 128-bit word into 4 signed int32
# lanes.  Lane c = C[addr][c].
#---------------------------------------------------------------------
proc accel_read {addr} {
    accel_set vio_o_addr [format %X $addr]
    # host_o_addr -> o_rdata has 1 clock of SRAM read latency; a JTAG
    # round trip is ~6 orders of magnitude longer, so no wait is needed.
    set raw [accel_get o_rdata]

    # Normalise: strip any separators, then LEFT-pad to 32 hex chars.
    # (Vivado drops leading zeros, so a small result comes back short.)
    set hex [string map {_ {} " " {}} $raw]
    while {[string length $hex] < 32} { set hex "0$hex" }

    # The word is MSB-first, so character positions map to lanes as:
    #   chars  0..7  = o_rdata[127:96] = col 3
    #   chars  8..15 = o_rdata[ 95:64] = col 2
    #   chars 16..23 = o_rdata[ 63:32] = col 1
    #   chars 24..31 = o_rdata[ 31: 0] = col 0
    # We want col0 FIRST, so walk the chunks from the END backwards.
    set out {}
    for {set i 3} {$i >= 0} {incr i -1} {
        scan [string range $hex [expr {$i*8}] [expr {$i*8+7}]] %x u
        if {$u >= 0x80000000} { set u [expr {$u - 0x100000000}] }   ;# sign-extend int32
        lappend out $u
    }
    return $out
}

#---------------------------------------------------------------------
# The full T5 demo
#---------------------------------------------------------------------
proc accel_demo {} {
    puts "\n=== 4x4 systolic accelerator :: VIO demo (T5 golden case) ==="

    # weight_mem[r] packs lane c = W[r][c], lane0 in the LOW byte.
    # NOTE: the host writes rows in NATURAL order 0,1,2,3.  The
    # "bottom-first" rule is the AGU's job -- it counts w_addr down
    # 3,2,1,0 during WLOAD.  Do not pre-reverse them here.
    puts "  loading weights..."
    accel_write_w 0 04030201    ;#  W row0 = 1 2 3 4
    accel_write_w 1 08070605    ;#  W row1 = 5 6 7 8
    accel_write_w 2 0C0B0A09    ;#  W row2 = 9 10 11 12
    accel_write_w 3 100F0E0D    ;#  W row3 = 13 14 15 16

    # a_mem[i] packs lane r = A[i][r], lane0 in the LOW byte.
    puts "  loading activations..."
    accel_write_a 0 00000001    ;#  A row0 = 1 0 0 0
    accel_write_a 1 00000100    ;#  A row1 = 0 1 0 0
    accel_write_a 2 00010000    ;#  A row2 = 0 0 1 0
    accel_write_a 3 01010101    ;#  A row3 = 1 1 1 1

    puts "  running (num_vectors = 4, 17 clocks = 170 ns)..."
    accel_run 4

    puts "\n  C = A x W :"
    set golden {{1 2 3 4} {5 6 7 8} {9 10 11 12} {28 32 36 40}}
    set fails 0
    for {set row 0} {$row < 4} {incr row} {
        set got [accel_read $row]
        set exp [lindex $golden $row]
        if {$got eq $exp} { set tag "OK" } else { set tag "MISMATCH exp=$exp" ; incr fails }
        puts [format "    \[ %6d %6d %6d %6d \]   %s" \
              [lindex $got 0] [lindex $got 1] [lindex $got 2] [lindex $got 3] $tag]
    }
    if {$fails == 0} {
        puts "\n  PASS -- hardware matches the simulation golden model.\n"
    } else {
        puts "\n  $fails row(s) wrong. See VIO_ILA.pdf section 10 (troubleshooting).\n"
    }
}

puts "vio_demo.tcl loaded.  Run:  accel_demo      (or accel_probes to inspect names)"
