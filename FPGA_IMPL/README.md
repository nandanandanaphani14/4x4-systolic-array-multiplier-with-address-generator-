# FPGA_IMPL — ZedBoard implementation of the 4×4 systolic accelerator

How to run the (unmodified) accelerator on a **Digilent ZedBoard** (Zynq-7000,
`xc7z020clg484-1`) using **only on-board switches, buttons and LEDs** — no external peripheral
connectors — plus richer peripheral-free alternatives.

## Contents
| File | What |
|------|------|
| [ZedBoard_Implementation_Guide.html](ZedBoard_Implementation_Guide.html) | **the main how-to** — plan, I/O scheme, resources, Vivado flow, bring-up test, and a step-by-step walkthrough for all four interface options. Animated. |
| [timing.pdf](timing.pdf) | **Timing, from zero** (22 pp) — why STA exists, setup/hold equations, slack, WNS/TNS/WHS/WPWS defined, this design's clock and critical path, the **measured positive-WNS results**, how to read a Vivado timing report, a negative-WNS checklist, and a **WNS interview/viva question bank**. Source: [timing.html](timing.html) |
| [implementation_method.pdf](implementation_method.pdf) | **Methodology and bring-up strategy** (23 pp) — why VIO/ILA was chosen, the two impedance mismatches the harness solves, exact VIO/ILA probe tables, the **data-injection protocol**, the **result-observation strategy**, the Tcl automation dissected, the expected cycle map, **every parameter and report checked at each stage**, and a sign-off checklist. Source: [implementation_method.html](implementation_method.html) |
| [VIO_ILA.pdf](VIO_ILA.pdf) | **Option 2 in full** (41 pp) — debug-harness design, VIO/ILA IP settings, non-invasive netlist probing, **§8A: how the VIO/ILA are auto-wired to the top level (the `dbg_hub`/`BSCANE2` mechanism) and what each build stage does**, dashboard + Tcl operation, the expected cycle map, troubleshooting. Source: [VIO_ILA.html](VIO_ILA.html) |
| [USB_UART.pdf](USB_UART.pdf) | **Option 3 in full** (19 pp) — the 16-step Vivado + Vitis flow, PS configuration, block design, BSP stdio routing, terminal setup, register map, troubleshooting, build checklist. Source: [USB_UART.html](USB_UART.html) |
| [rtl/fpga_top.sv](rtl/fpga_top.sv) | Option 1 console harness: debouncers + loader FSM + result capture + LED mux around `accelerator_system_top` (elaborates clean) |
| [rtl/vio_debug_top.sv](rtl/vio_debug_top.sv) | Option 2 debug top: VIO + ILA + one-shot pulse generators + sticky-done around `accelerator_system_top`. One physical pin (clk). |
| [rtl/accel_axi.sv](rtl/accel_axi.sv) | Option 3/4 AXI4-Lite slave wrapper around `accelerator_system_top`, with sticky-done (elaborates clean) |
| [sw/accel_monitor.c](sw/accel_monitor.c) | Option 3 bare-metal UART monitor (text menu: enter matrices, run, print result) |
| [zedboard_accelerator.xdc](zedboard_accelerator.xdc) | Option 1 pin-constraint template (clk / SW / LED / buttons) — **verify against the Digilent master XDC for your board rev** |
| [vio_debug.xdc](vio_debug.xdc) | Option 2 constraints: clk pin, debug-hub clock frequency, optional `MARK_DEBUG` lines for internal nets |
| [vio_demo.tcl](vio_demo.tcl) | Option 2 Hardware Manager script — loads the T5 golden matrices, runs the job, reads back and checks all 16 results |

## Job length
The controller is a **5-state FSM** — `IDLE(0) → WLOAD(1) → COMPUTE(2) → DRAIN(3) → DONE(4)`. There
is **no FLUSH phase**; COMPUTE follows WLOAD directly.

| Case | Cycles | At 100 MHz |
|------|--------|-----------|
| New weight matrix | `num_vectors + 13` → **17** for a 4×4 | **170 ns** |
| Weights unchanged — **WLOAD skipped automatically** | `num_vectors + 9` → **13** | **130 ns** |

The skip needs nothing from the host: `accelerator_system_top` keeps a `weights_dirty` flag (set by
reset and by any host write to `weight_mem`, cleared on the last WLOAD cycle) and drives
`controller.load_weights` with it. The module's port list is unchanged, so `fpga_top.sv`,
`vio_debug_top.sv` and `accel_axi.sv` all get the speed-up without modification. On the ILA you can
see it directly: the `phase` probe goes 0 → 2 with no 1 in between.

## The idea in one paragraph
A job finishes in ~170 ns at 100 MHz — too fast to watch — and 8 switches / 8 LEDs cannot hold a 4×4
matrix. So `fpga_top.sv` adds a small **console FSM**: enter each int8 byte on the switches, commit
with the center button (pointer auto-advances), press UP to run the job at full speed, and read the
latched 4×4 result one byte at a time (switches select which byte, LEDs show it). The accelerator RTL
is **not modified** — the harness drives its `host_*` ports exactly as the testbench did in simulation.

## Interface options (all peripheral-free) — each has a full step-by-step in the guide §9
1. **Switches + LEDs** — `fpga_top.sv` + XDC. Self-contained board demo.
2. **Vivado VIO + ILA over JTAG** — drive/observe from the PC over the programming cable; the only way
   to watch the pipeline cycle-by-cycle on real hardware.
3. **USB-UART text console** — type matrices / read results in a serial terminal. On the ZedBoard the
   USB-UART is a **PS** resource (UART1, MIO48/49), so this uses a minimal PS + `accel_axi.sv` +
   `accel_monitor.c`.
4. **Full PS/AXI integration** — scale the same base with AXI-DMA, a done-interrupt, or a Linux/UIO driver.

---

# Step-by-step implementation flow (all four methods)

Common prerequisites for every method: Vivado (2019.1 or later), the ZedBoard, and the USB cable in
JTAG mode (JP2). Target part **`xc7z020clg484-1`**. The 13 RTL design files live in
`…SIMPLE_ACCEL_RTL/` and are **never modified** — every method only *adds* a wrapper around
`accelerator_system_top`.

The four methods share a `Sources → Synthesis → Implementation → Bitstream → Program` spine; they
differ in which wrapper is the top and how you feed data in / read data out.

| Method | Top module | Extra tooling | You interact via |
|--------|-----------|---------------|------------------|
| 1 · Switches + LEDs | `fpga_top` | none | on-board SW / BTN / LED |
| 2 · VIO + ILA | thin debug top / `fpga_top` | Hardware Manager | Vivado dashboard over JTAG |
| 3 · UART console | BD wrapper (`accel_axi` + PS7) | Vitis + serial terminal | typed text over USB-UART |
| 4 · Full PS/AXI | BD wrapper (+ DMA/IRQ) | Vitis / PetaLinux | driver / app |

---

## Method 1 — Switches + LEDs (pure PL, no PC tools at run time)

**Top:** `fpga_top` · **Files:** 13 RTL + `rtl/fpga_top.sv` + `zedboard_accelerator.xdc`

1. **Create project** — Vivado → *Create Project* → **RTL Project** (do not specify sources yet) →
   *Next* → **Parts** tab → select `xc7z020clg484-1` (or *Boards* → ZedBoard if board files are
   installed) → *Finish*.
2. **Add design sources** — *Flow Navigator → Add Sources → Add or create design sources → Add Files*:
   select all 13 `.sv` files in `…SIMPLE_ACCEL_RTL/` **and** `FPGA_IMPL/rtl/fpga_top.sv` → *Finish*.
3. **Set top** — in the *Sources* pane, right-click **`fpga_top`** → *Set as Top* (it goes bold).
4. **Add constraints** — *Add Sources → Add or create constraints* → add
   `FPGA_IMPL/zedboard_accelerator.xdc`. **Open it and verify** every `PACKAGE_PIN` / `IOSTANDARD`
   against the official Digilent ZedBoard master XDC for your board revision.
5. **Synthesize** — *Run Synthesis* → *OK*. Fix any port-name mismatch between the XDC and
   `fpga_top` ports (`clk, sw[7:0], btnc/u/d/l/r, led[7:0]`).
6. **Implement** — *Run Implementation* → *OK*. Check the *Timing* summary shows **positive WNS**
   (this design has ample margin at 100 MHz).
7. **Generate bitstream** — *Generate Bitstream* → *OK*. (PL-only Zynq builds fine; the XDC allows the
   unconstrained-PS DRC.)
8. **Program** — *Open Hardware Manager → Open Target → Auto Connect* → right-click the device →
   *Program Device* → select the `.bit` → *Program*.
9. **Operate the board** (no PC needed now):
   - **Load weights** (16 bytes, row-major `W[r][c]`): set `SW[7:0]` to a signed byte, press **BTNC**
     (COMMIT); repeat 16×. The pointer auto-advances; after 16 it moves to activations.
   - **Load activations** (16 bytes, row-major `A[i][r]`): same, 16 commits.
   - **Run**: press **BTNU** (START). The job completes in ~170 ns; the result is latched.
   - **Read**: set `SW[5:4]` = result row (0–3), `SW[3:0]` = byte in that row's 128-bit word; the LEDs
     show that byte. **BTND** = RESET (restart entry).

> Sanity demo (matches testbench T5): weights `1..16` row-major, activations
> `1 0 0 0 / 0 1 0 0 / 0 0 1 0 / 1 1 1 1` → result row 3 = `28 32 36 40`
> (`SW[5:4]=11, SW[3:0]=0000` → LEDs `00011100` = 28).

---

## Method 2 — Vivado VIO + ILA over JTAG (drive/observe from the PC)

> Full detail — including the debug-harness design, exact IP probe tables, netlist probing without
> editing the RTL, the expected cycle map and troubleshooting — is in **[VIO_ILA.pdf](VIO_ILA.pdf)**.
> The summary below is the short form.

**Top:** a thin debug top (or reuse `fpga_top`) · **Extra:** on-chip ILA/VIO debug cores. Nothing on
the board is touched — the programming cable carries the data.

### 2a · ILA — capture the run as a waveform
1. Build any working design (Method 1's `fpga_top`, or Method 3's BD) so there is something to run.
2. In the *Synthesized/Elaborated Design*, in the *Netlist* pane right-click the nets to observe —
   e.g. `u_acc/.../psum_out_bottom`, `result`, `phase`, `busy`, `start` — and choose **Mark Debug**
   (or *Add Sources → IP → ILA* from the IP catalog).
3. *Tools → Set Up Debug* → *Next* → confirm the debug **clock domain = `clk`** → set **sample depth**
   1024 → *Finish*. Re-run *Synthesis → Implementation → Generate Bitstream*.
4. *Program Device*. An **hw_ila_1** dashboard appears in Hardware Manager.
5. In the *Trigger Setup* pane add `start` and set the condition `start == 1`. Click **Run Trigger**
   (arm). Cause a run (press BTNU, or drive it from UART/VIO). The ILA captures the whole ~170 ns job —
   you can see the weight load, the diagonal wavefront, and each column's result at `n+3+c`.

### 2b · VIO — inject inputs and read outputs (no switches)
1. Create a thin top that instantiates `accelerator_system_top` **and** a **VIO** IP.
   Map VIO `probe_out` → `start, num_vectors[8], act_base[8], out_base[8], host_w_wdata[32],
   host_w_addr[2], host_w_we, host_a_wdata[32], host_a_addr[8], host_a_we, host_o_addr[8]`; map
   `probe_in` ← `busy, done, phase[3], o_rdata[128]`.
2. Constrain only `clk` (pin Y9). *Synthesis → Implementation → Bitstream → Program*.
3. Open the **hw_vio_1** dashboard, *Add Probes* for all signals.
4. Load a weight word: set `host_w_wdata` and `host_w_addr`, then toggle `host_w_we` 1→0 (right-click →
   *Toggle*). Repeat for 4 weight + 4 activation words, then pulse `start`.
5. Read results: set `host_o_addr` 0…3 and read `o_rdata` (128-bit) on the dashboard = the four int32
   result columns per row. (Scriptable from the Tcl console via `set_property OUTPUT_VALUE …`.)

---

## Method 3 — USB-UART text console (minimal PS + AXI-Lite)

> Full detail — the 16-step Vivado + Vitis flow with PS configuration, block design, BSP stdio routing,
> terminal setup, register map and a build checklist — is in **[USB_UART.pdf](USB_UART.pdf)**.
> The summary below is the short form.

**Top:** the block-design HDL wrapper · **Files:** 13 RTL + `rtl/accel_axi.sv` + `sw/accel_monitor.c`

> ⚠ On the ZedBoard the USB-UART bridge is on the **PS** (UART1, MIO48/49), *not* the PL. So the
> peripheral-free text console uses a minimal PS that owns the UART, with `accel_axi` bridging the
> ARM core to the accelerator. Data path:
> `terminal → USB → PS UART1 → ARM (accel_monitor.c) → AXI-Lite → accel_axi → accelerator (PL)`.

1. **Add sources** — new/existing Vivado project (part `xc7z020clg484-1`); *Add Sources* → the 13 RTL
   files **and** `rtl/accel_axi.sv`.
2. **Block design** — *Flow Navigator → Create Block Design* (name e.g. `system`).
3. **Add the PS** — *+ (Add IP)* → **ZYNQ7 Processing System** → click **Run Block Automation** →
   **Apply Board Preset** (ZedBoard). In *Re-customize IP → MIO Configuration → I/O Peripherals*
   confirm **UART1** is enabled (MIO48/49); under *Clock Configuration* keep **FCLK_CLK0** (100 MHz).
4. **Add the accelerator** — in the BD canvas right-click → *Add Module* → **`accel_axi`**.
5. **Connect AXI** — click **Run Connection Automation** → select all. Vivado inserts an
   **AXI Interconnect** and a **Processor System Reset**, wires `M_AXI_GP0 → accel_axi/S_AXI`, and ties
   `FCLK_CLK0` to `S_AXI_ACLK` and the interconnect clocks; `S_AXI_ARESETN` = peripheral reset.
6. **Assign address** — *Window → Address Editor* → verify `accel_axi` gets a base (default
   `0x43C0_0000`). Note it — it becomes `XPAR_ACCEL_AXI_0_S_AXI_BASEADDR`.
7. **Validate & wrap** — *Validate Design* (F6) → in *Sources* right-click the `.bd` →
   **Create HDL Wrapper** (let Vivado manage) → *Set as Top*.
8. **Bitstream** — *Generate Bitstream*. No PL pin XDC is needed (PS owns the clock and UART pins).
9. **Export hardware** — *File → Export → Export Hardware* → **Include bitstream** → writes an `.xsa`.
10. **Vitis platform** — open **Vitis** → *Create Platform Project* from the `.xsa` → build it.
11. **Vitis application** — *Create Application Project* on that platform → **Empty Application (C)**,
    standalone/bare-metal. Copy `FPGA_IMPL/sw/accel_monitor.c` into the app's `src/`. In the app's BSP
    settings set **stdin = stdout = `ps7_uart_1`**. Set `ACCEL_BASE` if your base ≠ `0x43C00000`.
12. **Serial terminal** — plug in USB. *Device Manager* → note the **USB Serial Port (COMx)**. Open
    PuTTY/Tera Term on that port, **115200 baud, 8-N-1, no flow control**.
13. **Run** — in Vitis: *Program FPGA* (loads the bitstream), then *Run* the app. The monitor menu
    appears in the terminal.
14. **Use it** — `d` (load demo) → `r` (run) → `p` (print) prints:
    ```
      C = A x W :
        [      1      2      3      4 ]
        [      5      6      7      8 ]
        [      9     10     11     12 ]
        [     28     32     36     40 ]
    ```
    For your own data: `w` + 16 signed ints (`W[r][c]`), `a` + 16 signed ints (`A[i][r]`), `r`, `p`.

**`accel_axi` register map** (byte address = index×4): `0 NUMVEC(W) · 1 ACT_BASE(W) · 2 OUT_BASE(W) ·
3 W_WDATA(W) · 4 W_COMMIT(W,→host_w_we) · 5 A_WDATA(W) · 6 A_COMMIT(W,→host_a_we) · 7 START(W) ·
8 O_ADDR(W) · 9 STATUS(R: busy,done,phase) · 10–13 ORD0–3(R: result columns)`.

---

## Method 4 — Full PS / AXI integration (scaling up)

Method 3 stands up the PS+AXI base; Method 4 is what you add for real workloads (still no external
peripherals). Do Method 3 first, then:

1. **Stream vectors with AXI-DMA** — add an AXI-DMA (or an AXI-Stream port on `accel_axi`) so the PS
   DMAs a block of activation vectors into `a_mem` and reads the result block back, instead of one
   word per register write; drive a long job with `num_vectors`.
2. **Interrupt on done** — route the accelerator `done` to a PL→PS interrupt (`IRQ_F2P`) and enable
   it in the PS7 GIC, so the monitor is event-driven instead of polling the sticky-done bit.
3. **Run under Linux** — with PetaLinux, expose `accel_axi` as a **UIO** device, `mmap` the register
   block from a user-space C/Python program, and print over the same console (now `ttyPS0`).
4. **Benchmark** — feed up to 256 activation vectors (the depth of `a_mem`) and time the job; once the
   pipe is full it is one vector per clock.

---

## Notes
- Both wrappers (`fpga_top.sv`, `accel_axi.sv`) **elaborate clean** against the design (checked with
  QuestaSim `vopt`). They can also be simulated by wrapping them in a small testbench (pulse the
  debounced buttons for `fpga_top`; drive AXI transactions for `accel_axi`).
- If timing ever fails after edits, add an **MMCM** and clock the fabric at 50 MHz — none of the
  interfaces depend on throughput.
- Design reference: [`../context_mkdwn/`](../context_mkdwn/index.md). Functional baseline:
  **11/11 testbenches, 3 680 checks, 0 mismatches** ([`../verification_recheck/`](../verification_recheck/index.md)).
