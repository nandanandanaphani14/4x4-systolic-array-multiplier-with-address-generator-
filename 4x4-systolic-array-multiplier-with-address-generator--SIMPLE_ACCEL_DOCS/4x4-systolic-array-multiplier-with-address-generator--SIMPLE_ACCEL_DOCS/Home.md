# 4×4 Weight-Stationary Systolic-Array Multiplier — Project Wiki

> **GitHub Wiki home page.** Copy this file into the repository wiki as `Home.md`, or paste each
> `##` section into its own wiki page and use the [Wiki map](#wiki-map) below as the sidebar.
> Every number on this page is measured or derived from the RTL — none of it is estimated.

An integer matrix-multiply accelerator in SystemVerilog: a 4×4 weight-stationary systolic array with an
on-chip address generator and control FSM, verified in simulation and brought up on a Digilent ZedBoard
(Zynq-7000, `xc7z020clg484-1`).

| | |
|---|---|
| **Computes** | `C = A × W` — `W` is a stationary 4×4 `int8` weight matrix, `A` is a stream of activation vectors, `C` accumulates in `int32` |
| **Throughput** | one activation vector per clock once the pipe is full |
| **Job length** | `num_vectors + 13` clocks (**17 clocks = 170 ns** at 100 MHz for a 4×4 × 4×4 product) |
| **Verification** | **11/11 testbenches · 3 680 checks · 0 mismatches · 0 RTL defects** (QuestaSim) |
| **Timing** | **WNS +0.714 ns**, WHS +0.045 ns, WPWS +3.750 ns, **0 failing endpoints of 5 181** — all constraints met at 100 MHz |
| **Resources** | 1 564 LUT (2.94 %) · 792 FF (0.74 %) · 2.5 BRAM (1.79 %) · **0 DSP** |
| **Host interface** | No AXI in the core — plain memory write ports + `start`/`done`. AXI-Lite is an optional wrapper. |

---

## Wiki map

| Page | Contents |
|------|----------|
| [1. What this design is](#1-what-this-design-is) | the algorithm, why systolic, why weight-stationary |
| [2. Repository layout](#2-repository-layout) | every folder and what lives in it |
| [3. Architecture](#3-architecture) | the three abstraction levels, module inventory |
| [4. The processing element](#4-the-processing-element) | the only module with arithmetic |
| [5. The array and the two skew buffers](#5-the-array-and-the-two-skew-buffers) | interconnect, staircase latency, de-skew |
| [6. Memories and data layout](#6-memories-and-data-layout) | word/lane packing — get this wrong and matrices transpose silently |
| [7. Control — FSM and AGU](#7-control--fsm-and-agu) | phases, durations, address generation |
| [8. Dataflow and timing derivations](#8-dataflow-and-timing-derivations) | the latency chain, every constant |
| [9. The three load-bearing rules](#9-the-three-load-bearing-rules) | break any of these and it fails silently |
| [10. Host protocol](#10-host-protocol) | how to drive the accelerator |
| [11. Worked example — the T5 golden case](#11-worked-example--the-t5-golden-case) | the numbers used everywhere |
| [12. Verification](#12-verification) | strategy, results, principles |
| [13. Coverage boundaries](#13-coverage-boundaries) | what is **not** verified |
| [14. FPGA implementation](#14-fpga-implementation) | four methods; the VIO/ILA bring-up rig |
| [15. Timing closure results](#15-timing-closure-results) | WNS/WHS/WPWS, critical path, what to do if it fails |
| [16. How to reproduce everything](#16-how-to-reproduce-everything) | exact commands |
| [17. Troubleshooting](#17-troubleshooting) | symptom → cause → fix |
| [18. FAQ](#18-faq) | the questions people actually ask |
| [19. Glossary](#19-glossary) | terms used across the docs |

---

## 1. What this design is

A **systolic array** is a grid of tiny identical processing elements (PEs) that talk **only to their
immediate neighbours**, passing data rhythmically one hop per clock. There are no global buses and no
long combinational paths across the fabric — which is exactly why the structure runs fast and scales.

This one is **weight-stationary**: the weight matrix is loaded into the 16 PEs once and *stays there*.
Activations flow through it. The economics:

- weight traffic = `ROWS × COLS` bytes **per job**
- activation traffic = `ROWS` bytes **per vector**

so a single weight load can be amortised over up to 256 activation vectors (the depth of `a_mem`).
Paying the weight-load cost once and reusing it over many activation rows *is* the point of the
weight-stationary dataflow.

**What it computes:** `C[i][c] = Σ_r A[i][r] · W[r][c]` — `int8 × int8` products accumulated in `int32`.
Streaming four activation vectors makes `A` itself a 4×4 matrix, so the job is an ordinary
4×4 · 4×4 = 4×4 matrix product, one result row per activation row.

---

## 2. Repository layout

| Folder | Contents |
|--------|----------|
| `…SIMPLE_ACCEL_RTL/` | **The design.** 13 SystemVerilog files. Frozen — never edited by any implementation method. |
| `…SIMPLE_ACCEL_TB/` | Original testbench branch and the test-plan README. |
| `…SIMPLE_ACCEL_TB_REPORTS/` | Original verification baseline (untouched). |
| `…SIMPLE_ACCEL_DOCS/` | User documentation: architecture + dataflow, beginner's guide, animated testbench visualisation, **this wiki**. |
| `context_mkdwn/` | 16 segmented context chunks (00–15) — small, self-contained fact sets for targeted retrieval, cross-linked with `[[chunk-name]]`. |
| `verification_recheck/` | Independent re-verification: 11 testbenches, harness, logs, full report. |
| `FPGA_IMPL/` | ZedBoard implementation: wrappers, constraints, Tcl automation, and the implementation/timing documents. |
| `synthesis_screenshots/` | Captured Vivado dialogs and the Design Timing Summary. |

### Key documents

| Document | What it covers |
|----------|----------------|
| `FPGA_IMPL/README.md` | All four implementation methods, step by step |
| `FPGA_IMPL/timing.pdf` | **Timing from zero**: setup/hold, slack, WNS/TNS/WHS/WPWS, the critical path, measured results, an interview/viva question bank |
| `FPGA_IMPL/implementation_method.pdf` | **Methodology**: why VIO/ILA, the harness design, data-injection and result-observation strategy, every report checked, sign-off checklist |
| `FPGA_IMPL/VIO_ILA.pdf` | Method 2 reference, including §8A on how debug cores are auto-wired and how the build is staged |
| `FPGA_IMPL/USB_UART.pdf` | Method 3 reference — the 16-step Vivado + Vitis flow |
| `…SIMPLE_ACCEL_DOCS/architecture_and_dataflow.pdf` | Full architecture with cycle-level animations |
| `…SIMPLE_ACCEL_DOCS/beginners_guide.pdf` | The same design from zero, line by line |
| `verification_recheck/verification_recheck_report.md` | Strategy, per-testbench proof, defects, coverage |

---

## 3. Architecture

Three abstraction levels. Each wrapper **instantiates** the level below rather than re-wiring it, so
the levels cannot drift apart.

```
L3  accelerator_system_top   (wrapper_full_system.sv)
    ├── controller           phase FSM
    ├── agu                  addresses + write-strobe pipe
    ├── port arbitration     busy=0 → host owns the ports; busy=1 → AGU owns them
    └── L2  accelerator_top  (wrapper_mem_arr_buf.sv)
            ├── a_mem        256 × 32   activation stream
            ├── weight_mem     4 × 32   one stationary matrix
            ├── output_mem   256 × 128  int32 results
            └── L1  array_buf_top  (wrapper_array_buf.sv)
                    ├── input_skew_buffer     dense → diagonal
                    ├── systolic_array        4 × 4 = 16 processing_element
                    └── output_deskew_buffer  diagonal → aligned
```

| Level | Module | The host must supply |
|-------|--------|----------------------|
| **L1** `array_buf_top` | pure datapath | one dense vector per clock, by hand |
| **L2** `accelerator_top` | L1 + three SRAMs | addresses and control, sequenced by hand |
| **L3** `accelerator_system_top` | L2 + controller + AGU | only `start`, then wait for `done` |

### Module inventory

| File | Module | Role |
|------|--------|------|
| `MAC.sv` | `processing_element` | int8×int8 MAC, weight-stationary PE |
| `array.sv` | `systolic_array` | 4×4 grid of PEs — pure interconnect, no arithmetic |
| `delay_pipe.sv` | `delay_pipe` | parameterised N-deep shift register (`DELAY=0` ⇒ a wire) |
| `input_buf.sv` | `input_skew_buffer` | row *r* delayed by *r* — dense → diagonal |
| `output_skewbuf.sv` | `output_deskew_buffer` | column *c* delayed by `COLS-1-c` — realign |
| `a_mem.sv` | `a_mem` | activation SRAM, 1-cycle registered read |
| `weight_mem.sv` | `weight_mem` | weight SRAM |
| `outmem.sv` | `output_mem` | result SRAM, 128-bit word |
| `controller.sv` | `controller` | phase FSM: IDLE → WLOAD → COMPUTE → DRAIN → DONE (WLOAD skipped when weights unchanged) |
| `agu.sv` | `agu` | address generator + write-strobe pipeline |
| `wrapper_array_buf.sv` | `array_buf_top` | **L1** |
| `wrapper_mem_arr_buf.sv` | `accelerator_top` | **L2** |
| `wrapper_full_system.sv` | `accelerator_system_top` | **L3** |

---

## 4. The processing element

`MAC.sv` — the **only** module in the design that contains arithmetic. Sixteen instances form the array.

**Registers:** `weight_q[7:0]`, `a_q[7:0]`, `valid_q`, `psum_q[31:0]` — all cleared by synchronous `!rst_n`.

```systemverilog
// combinational
product_ext = 32'(weight_q * a_in);   // signed × signed, sign-extended
adder_out   = psum_in + product_ext;

// sequential
if (wload) weight_q <= psum_in[7:0];        // capture weight off the shared vertical bus
a_q     <= a_in;
valid_q <= valid_in;
psum_q  <= valid_in ? adder_out : psum_in;  // accumulate OR pass-through

// outputs
a_out     = a_q;
valid_out = valid_q;
psum_out  = wload ? 32'(weight_q) : psum_q; // COMBINATIONAL mux — load-bearing
```

### Three load-bearing facts

1. **The vertical bus is time-multiplexed** — it carries *weights* while `wload=1` and *partial sums*
   during compute. Only the low 8 bits of `psum_in` are captured as a weight.
2. **During `wload`, `psum_out` is combinational off `weight_q`.** This turns each array column into a
   downward **shift register**, so the value fed *first* travels *furthest* — down to the bottom row.
   This is the entire basis of the bottom-first weight-load rule.
3. **`valid_in = 0` is a bypass, not a stall.** Partial sums march south one row per clock regardless;
   a bubble produces junk that flushes itself out. There is no back-pressure anywhere in the design.

### Known-good directed vectors

`weight=3, a=5, psum_in=100 → 115` · `(−4)×7 = −28` · `(−128)×(−128) = +16384` ·
`50 + 127×(−2) = −204` · during `wload`, weight `−3` appears on `psum_out` as `0xFFFFFFFD`

---

## 5. The array and the two skew buffers

`array.sv` declares three meshes, instantiates 16 PEs and binds the boundaries. It contains **no
arithmetic at all**.

```
a_net    [0:ROWS-1][0:COLS]     // horizontal, west → east
valid_net[0:ROWS-1][0:COLS]     // travels alongside a_net
psum_net [0:ROWS][0:COLS-1]     // vertical, north → south
```

Boundaries: west `a_net[r][0] = a_in_left[r]` · north `psum_net[0][c] = psum_in_top[c]` ·
south out `psum_out_bottom[c] = psum_net[ROWS][c]`.
Named generate blocks give the hierarchical name `u_array.row_gen[r].col_gen[c].pe_inst`.

### The staircase, and why two buffers exist

A dense vector consumed at cycle *n* produces column *c*'s result just after cycle **`n + (ROWS−1) + c`**.
The `+c` is the horizontal-travel **staircase**: column 0 finishes first, column 3 three cycles later.

- **`input_skew_buffer`** delays row *r* by *r*, turning a dense vector into the diagonal wavefront the
  array needs.
- **`output_deskew_buffer`** delays column *c* by `COLS−1−c`, cancelling the staircase exactly.

`(3+c) + (3−c) = 6` for **every** column — so all four lanes of a result row emerge aligned on one
clock. Watching that alignment happen is one of the most satisfying things to see on an ILA capture.

---

## 6. Memories and data layout

One single-port synchronous RAM primitive at three geometries:

```systemverilog
always_ff @(posedge clk) begin
  if (we) mem[addr] <= wdata;
  rdata <= mem[addr];          // unconditional, registered read
end
```

| Module | Depth × width | ADDR_W | Word contents |
|--------|---------------|--------|---------------|
| `a_mem` | 256 × 32 | 8 | 4 × int8, lane *r* = activation for array **row** *r* |
| `weight_mem` | 4 × 32 | 2 | 4 × int8, lane *c* = weight for array **column** *c*; addr *r* = weight row *r* |
| `output_mem` | 256 × 128 | 8 | 4 × int32, lane *c* = result of array **column** *c* |

### Three load-bearing properties

1. **One address port, shared read/write.** A write cycle is not a read cycle → this is what forces the
   port arbitration at L3.
2. **One clock of read latency** (registered `rdata`) → this is why `accelerator_top` re-times
   `wload`/`valid_in` internally.
3. **Read-before-write on address collision** — a read colliding with a write to the same address
   returns the **old** contents.

### Word / lane layout — getting a lane wrong transposes a matrix silently

```
a_mem word     [31:24][23:16][15:8][7:0]     = row3  row2  row1  row0
weight_mem[r]  [31:24][23:16][15:8][7:0]     = col3  col2  col1  col0   (weights of row r)
output_mem     [127:96][95:64][63:32][31:0]  = col3  col2  col1  col0   (int32 results)
```

**Lane 0 is the LOW byte.** There is no reset — reads of unwritten addresses return `X` in simulation.

### Why `weight_mem` is 4×32 but `a_mem` is 256×32

Not arbitrary — it is the weight-stationary dataflow made physical. `weight_mem` holds **one whole
matrix, once**: four rows, four 32-bit words, `ADDR_W=2`. A 4×4 int8 matrix *is* 4×32 bits, so a deeper
weight memory would be dead silicon. `a_mem` holds a whole **stream**: up to 256 activation vectors
multiplied against a single weight load. `output_mem` mirrors `a_mem`'s depth — one result vector per
activation vector.

---

## 7. Control — FSM and AGU

### `controller` — phase durations only, no addresses

| State | Enc | Length | Note |
|-------|-----|--------|------|
| `PH_IDLE` | 0 | — | wait for `start`; latch `num_vectors` into `vec_n` |
| `PH_WLOAD` | 1 | `ROWS` = **4** | shift the weight matrix in |
| `PH_COMPUTE` | 3 | `num_vectors` | one activation vector per clock |
| `PH_DRAIN` | 4 | `STORE_LATENCY` = **8** | the last result is still in flight |
| `PH_DONE` | 5 | **1** | `done` pulses; `busy` is already low |

`busy = (state != IDLE) && (state != DONE)` · `done = (state == DONE)` · phase enables are one-hot.

**Load-bearing behaviours**

- **`num_vectors = 0` must not hang.** Both entries into COMPUTE are guarded: WLOAD exits to
  `(vec_n==0) ? PH_DRAIN : PH_COMPUTE`, and so does IDLE on the weight-skip path. Without the
  guard, COMPUTE would compare `cnt == 8'hFF` and sit for 256 cycles issuing garbage writes.
- **`start` is sampled only in IDLE** — a stray mid-job pulse changes nothing.
- **`done` is a single-cycle pulse**, and `busy` is already low when it fires.
- Reset mid-job → IDLE, and the FSM still accepts a fresh job afterwards.

### `agu` — addresses only, no policy

**Weight address counts DOWN** (this is what implements the bottom-first rule):

```
if (!wload_phase) w_cnt <= ROWS-1;      // re-armed while idle
else              w_cnt <= w_cnt - 1;   // 3, 2, 1, 0
```

Re-arming while idle means the first WLOAD cycle already presents `ROWS-1`, and a second job restarts
from `ROWS-1`.

**Activation address counts UP:** `act_addr = act_base + act_cnt`, `valid_in = compute_phase`.

**The output write strobe is a delay line, not an equation:**

```
out_we_pipe[0]   <= compute_phase;
out_addr_pipe[0] <= out_base + act_cnt;
out_*_pipe[i]    <= out_*_pipe[i-1];      // STORE_LATENCY (= 8) deep
out_we   = out_we_pipe[STORE_LATENCY-1];
out_addr = out_addr_pipe[STORE_LATENCY-1];
```

Because it is a delay line, **the strobe structurally cannot drift from the data it belongs to**.
Changing the datapath depth means changing one parameter.

### Port arbitration (L3)

```
busy = 0 : host owns all three ports (preload matrices, read results).
           output_mem host side is read-only.
busy = 1 : AGU owns all three ports; host write strobes are forced to 0.
```

This masks stray host writes during a live job. `agu_wload`/`agu_valid_in` bypass the mux and feed
`accelerator_top` directly, which re-times them internally.

---

## 8. Dataflow and timing derivations

**Notation:** cycle *n* is the *n*-th posedge. A signal **issued** at *n* is the value just *before*
edge *n*; **observed** at *n* is the value just *after*. Conflating the two caused 2 of the 3 historical
testbench defects.

### The latency chain

| # | Step | Adds | Running total |
|---|------|------|---------------|
| 1 | Down a PE column (one register per row) | `ROWS−1` = 3 | 3 |
| 2 | East to column *c* | `+c` | 3+c |
| 3 | De-skew pipe (`COLS−1−c`) | `+(3−c)` | **6** — independent of *c* |
| 4 | `a_mem` read latency | +1 | **7** = `RESULT_LATENCY` |
| 5 | Write strobe, one cycle after data is observable | +1 | **8** = `STORE_LATENCY` |

### Constant summary

| Constant | Value (4×4) | Formula | Declared in |
|----------|-------------|---------|-------------|
| Array column latency | 3+c | `(ROWS−1)+c` | `array.sv` (emergent) |
| De-skew delay | 3−c | `COLS−1−c` | `output_skewbuf.sv` |
| L1 result latency | 6 | `ROWS+COLS−2` | `wrapper_array_buf.sv` |
| L2 result latency | 7 | `1+ROWS+COLS−2` | `wrapper_mem_arr_buf.sv` |
| L2 store latency | 8 | `RESULT_LATENCY+1` | `wrapper_mem_arr_buf.sv` |
| AGU write-pipe depth | 8 | `STORE_LATENCY` | `agu.sv` |
| Controller DRAIN | 8 | `STORE_LATENCY` | `controller.sv` |
| **Job length, weights loaded** | **N+13** | `ROWS + N + STORE_LATENCY + 1` | emergent |
| **Job length, weights reused** | **N+9** | `N + STORE_LATENCY + 1` | emergent |

### Phase timeline for a 4-vector job

| Cycle | Phase | Length | What happens |
|-------|-------|--------|--------------|
| 0 | IDLE → WLOAD | 1 | `start` pulses; `busy` rises |
| 1–4 | **WLOAD** | 4 | weight rows driven into the north edge **bottom-first**: W[3], W[2], W[1], W[0] |
| 5–8 | **COMPUTE** | N=4 | one dense vector per clock, `valid=1` |
| 9–16 | **DRAIN** | 8 | last vector still in flight; results land here (first `out_we` at 13) |
| 17 | **DONE** | 1 | `done` pulses one clock; `busy` already low |

Reusing the already-loaded weights drops WLOAD entirely: COMPUTE 1–4, DRAIN 5–12, DONE at **13**.

**There is no FLUSH phase.** Earlier revisions inserted `ROWS + 2 = 6` cycles between WLOAD and
COMPUTE to push weight residue out of the `psum_q` registers. It was never load-bearing and has been
removed, cutting 6 cycles from every job:

- **Accumulation was never at risk.** In `MAC.sv`, `adder_out = psum_in + product` — a PE's own
  `psum_q` is only ever an *output* of the adder, never an input, so stale content is overwritten
  rather than accumulated into.
- **The residue could never reach memory.** It drains out of the array at one row per cycle and clears
  the de-skewed result bus on cycle 12, while the first `out_we` — the AGU write-strobe pipe, keyed off
  `compute_phase` and `STORE_LATENCY` deep — does not fire until cycle 13.

The honest caveat: the margin is now **zero**, so anyone adding a pipeline stage in the
skew → array → de-skew → pack path must re-derive that table.

---

## 9. The three load-bearing rules

> Break any of these and the design still runs, still pulses `done`, and still writes
> plausible-looking numbers. These are the failures that hide.

1. **Weight rows load bottom-first.** Feed `W[ROWS-1]` first; the AGU counts `w_addr` down 3, 2, 1, 0.
   A wrong order computes against a **vertically flipped W**. Only a golden-model check against a
   **non-symmetric** W catches it.
2. **Control travels with its address.** Issue `wload`/`valid_in` in the same cycle as the address;
   `accelerator_top` re-times by one clock internally. **Never pre-delay at the caller.**
3. **Fixed latency, no back-pressure.** There is no ready/valid handshake anywhere. The host must
   respect the numbers in [§8](#8-dataflow-and-timing-derivations).

**A note on rule 1 for hosts:** the *host* writes `weight_mem[0..3]` in **natural** order. The
bottom-first shift is the AGU's job. Do not pre-reverse the rows — if you do, rows 0–2 of the result
come out wrong while row 3 still looks right, because an all-ones activation row produces column sums
that are insensitive to row permutation. That is exactly why this bug hides.

---

## 10. Host protocol

1. Hold `rst_n` low, then release.
2. While `!busy`: write activation vectors and weight rows through the `host_*` ports.
3. Pulse `start` with `num_vectors` / `act_base` / `out_base` valid.
4. Wait for the `done` pulse (single cycle; `busy` is already low).
5. While `!busy`: read results via `host_o_addr` / `o_rdata`.

### Port list — `accelerator_system_top`

| Port | Dir | Width | Meaning |
|------|-----|-------|---------|
| `clk`, `rst_n` | in | 1 | clock, synchronous active-low reset |
| `start` | in | 1 | single-cycle launch pulse; ignored while `busy` |
| `num_vectors` | in | 8 | activation vectors this job |
| `act_base` | in | 8 | base address in `a_mem` |
| `out_base` | in | 8 | base address in `output_mem` |
| `host_a_we` / `host_a_addr` / `host_a_wdata` | in | 1 / 8 / 32 | activation write port |
| `host_w_we` / `host_w_addr` / `host_w_wdata` | in | 1 / 2 / 32 | weight write port |
| `host_o_addr` | in | 8 | result read address |
| `o_rdata` | out | 128 | result word — 4 × int32 lanes |
| `phase` | out | 3 | FSM state |
| `busy`, `done` | out | 1 | status; `done` is a 1-cycle pulse |
| `result` | out | 4 × int32 | the live result bus out of the de-skew buffer |

### Rules the host must obey

- **Write only while `busy == 0`.** Writes are masked otherwise.
- **`start` only while `busy == 0`.** Otherwise it is silently ignored.
- **Write weight rows in natural order 0,1,2,3.**
- **Write every address you intend to read** — the memories have no reset.
- **`num_vectors = 0` is legal** and does not hang.

---

## 11. Worked example — the T5 golden case

The canonical vector: used by `tb_accelerator_system_top` section T5 in simulation **and** replayed
unchanged on hardware, so a hardware match is a direct simulation-to-silicon equivalence result.

```
     A (4×4)              W (4×4)                 C = A × W
  [ 1 0 0 0 ]        [  1  2  3  4 ]           [  1  2  3  4 ]   ← A row0 selects W row0
  [ 0 1 0 0 ]   ×    [  5  6  7  8 ]     =     [  5  6  7  8 ]   ← A row1 selects W row1
  [ 0 0 1 0 ]        [  9 10 11 12 ]           [  9 10 11 12 ]   ← A row2 selects W row2
  [ 1 1 1 1 ]        [ 13 14 15 16 ]           [ 28 32 36 40 ]   ← A row3 = column sums
```

**Packing:**

| `weight_mem` | | `a_mem` | |
|---|---|---|---|
| addr 0 ← `0x04030201` | W row0 = 1 2 3 4 | addr 0 ← `0x00000001` | A row0 = 1 0 0 0 |
| addr 1 ← `0x08070605` | W row1 = 5 6 7 8 | addr 1 ← `0x00000100` | A row1 = 0 1 0 0 |
| addr 2 ← `0x0C0B0A09` | W row2 = 9…12 | addr 2 ← `0x00010000` | A row2 = 0 0 1 0 |
| addr 3 ← `0x100F0E0D` | W row3 = 13…16 | addr 3 ← `0x01010101` | A row3 = 1 1 1 1 |

**Why this vector was chosen:** every failure mode announces itself distinctly. The identity rows mean
rows 0–2 of the result should literally reproduce the weight rows — so a transpose or a lane swap is
obvious at a glance. The all-ones row 3 gives hand-checkable column sums `28 32 36 40` and is the one
row insensitive to weight-row ordering.

### A second, fully non-symmetric example

```
W = [  2 -1  3  0 ]      A0 = [ 1  2  3  4 ]      C0 = [ -5  17  10  -3 ]
    [  1  4 -2  5 ]      A1 = [ 5 -1  0  2 ]      C1 = [  9  -7  21 -13 ]
    [ -3  2  1  1 ]      A2 = [-2  3  1  1 ]      C2 = [ -4  17  -9  12 ]
    [  0  1  2 -4 ]
```

Checkpoints for a 3-vector job: `bottom[0] = −5` after cycle 14 (`= 11 + (ROWS−1) + 0`); all four lanes
of C0 align after cycle 17 (`= 11 + ROWS + COLS − 2`).

---

## 12. Verification

**Result: 11/11 testbenches PASS · 3 680 checks · 0 mismatches · 0 RTL defects** (QuestaSim 2021.1).

### Strategy — bottom-up along the module hierarchy

```
PROCESSING ELEMENT → 4×4 GRID → MEMORIES → DELAY/SKEW BUFFERS → AGU → CONTROL UNIT → L1 → L2 → L3
```

| Level | DUT | Testbench |
|-------|-----|-----------|
| leaf | `processing_element` | `tb_processing_element` |
| leaf | `delay_pipe` | `tb_delay_pipe` |
| leaf | `a_mem` / `weight_mem` / `output_mem` | `tb_memories` |
| leaf | `input_skew_buffer` | `tb_input_skew_buffer` |
| leaf | `output_deskew_buffer` | `tb_output_deskew_buffer` |
| fabric | `systolic_array` | `tb_systolic_array` |
| L1 | `array_buf_top` | `tb_array_buf_top` |
| control | `controller` | `tb_controller` |
| control | `agu` | `tb_agu` |
| L2 | `accelerator_top` | `tb_accelerator_top` |
| L3 | `accelerator_system_top` | `tb_accelerator_system_top` |

### Verification principles

- **Algorithmic golden model.** From `tb_systolic_array` upward, expected values are computed as
  `C = A × W` in the testbench — they owe nothing to the RTL.
- **Non-symmetric random W**, so *any* weight-row permutation fails. This is what catches the silent
  load-order bug.
- **Negative checks** — the result must not appear a cycle early; the datapath must be quiet before
  compute; short runs must not touch neighbouring output words.
- **Explicit sampling convention** stated per testbench (registered outputs vs delay-line/address bus).
- **Independence of control from datapath** — `tb_agu` drives phase enables from the testbench, so a
  controller bug cannot mask an AGU bug.

### Notable adversarial test

`tb_accelerator_system_top` (201 checks) runs four jobs, one of which **hammers both host write ports
with garbage** (`0xDEADBEEF` / `0xBAADF00D`) throughout the run. Results are bit-identical — proving the
port arbitration really does mask host writes while `busy` is high. It also checks `act_base`/`out_base`
isolation and a 3-vector short run.

### Historical defects — all three were in testbench code, none in the RTL

1. `tb_output_mem`: `128'(-32'sd1)` sign-extends, but the part-select `rd[32+:32]` is unsigned and
   zero-extends.
2. `tb_agu`: sampled the address bus *after* the consuming edge — off by one.
3. `tb_controller`: cleared the phase counters after the start pulse, measuring WLOAD as 3 instead of 4.

**Reproduce:** `.\testbenches\run_all_testbenches.ps1` (exits non-zero on any failure).

---

## 13. Coverage boundaries

> Stated plainly so a green regression is not read as stronger than it is.

**Not exercised by any test**

- **Arithmetic overflow.** `psum` is 32-bit with no saturation. Worst case at 4×4 int8 is
  `4 × 128 × 128 = 65 536` — unreachable here, but nothing guards a larger `ROWS` or wider inputs.
- **Uninitialised memory reads.** All three SRAMs power up `X`; tests only read written addresses.
- **Parameter sweeps.** Everything runs at `ROWS = COLS = 4`. `systolic_array` ports are hard-coded
  `[7:0]` / `[31:0]`, so `DATA_W` / `PSUM_W` are effectively fixed at 8 / 32.
- **Per-row valid.** `valid_in` is one bit broadcast to all rows; independent per-row valid is
  structurally supported but never driven.
- **CDC / reset-domain crossings.** Single clock, synchronous reset, no CDC.
- **Back-pressure.** None in the architecture by design.
- **No load engine** — `agu_load.sv` was anticipated but never built; the host preloads memories directly.

**Out of scope of simulation entirely**

- No gate-level or post-layout simulation. *(Synthesis and timing closure were done separately —
  see [§15](#15-timing-closure-results).)*
- No formal property verification.
- No functional-coverage collection. **"N/N passed" is a pass rate, not a coverage number.**
- No power analysis.

---

## 14. FPGA implementation

Target: **Digilent ZedBoard**, Zynq-7000 `xc7z020clg484-1`, Vivado 2019.1+. All four methods share a
`Sources → Synthesis → Implementation → Bitstream → Program` spine and **none of them modifies the RTL** —
each only *adds a wrapper* around `accelerator_system_top`.

| # | Method | Top module | Extra tooling | You interact via |
|---|--------|-----------|---------------|------------------|
| 1 | Switches + LEDs | `fpga_top` | none | on-board SW / BTN / LED |
| 2 | **VIO + ILA over JTAG** | `vio_debug_top` | Vivado only | Hardware Manager dashboards + Tcl |
| 3 | USB-UART console | BD wrapper (`accel_axi` + PS7) | Vitis + terminal | typed text |
| 4 | Full PS/AXI | BD wrapper + DMA/IRQ | Vitis / PetaLinux | driver or app |

### Why VIO + ILA is the primary bring-up path

A job finishes in **170 ns** — far too fast for any human-rate interface to observe — and 8 switches
with 8 LEDs cannot hold a 4×4 matrix. Method 2 needs **one physical pin** (the clock), injects data and
reads results from the PC over the programming cable, is fully scriptable in Tcl, and is **the only
method that can watch the pipeline cycle-by-cycle on real silicon**.

### The two problems the debug harness has to solve

Both come from bridging a human-rate observer to a 100 MHz pipeline, and both recur in *any* such rig:

1. **VIO drives levels; the accelerator wants pulses.** A `probe_out` held high for ~1 ms is 100 000
   clocks — the FSM would relaunch the 17-cycle job about 4 000 times per click. Fixed by a `oneshot`
   edge detector that converts every 0→1 transition into exactly one clock. *Operational consequence:
   every write is a 0→1→0 sequence.*
2. **`done` is a 10 ns pulse; the VIO samples at human rate.** You will never catch it. Fixed by
   `done_sticky` (latched, auto-cleared by the next `start`) and `done_count` (increments by exactly 1
   per launch — the cheapest possible health probe).

### Harness contents — `FPGA_IMPL/`

| File | What |
|------|------|
| `rtl/vio_debug_top.sv` | Method 2 harness: POR + 3 × `oneshot` + unmodified accelerator + sticky-done + VIO + ILA |
| `rtl/fpga_top.sv` | Method 1 console FSM: debouncers, loader FSM, result capture, LED mux |
| `rtl/accel_axi.sv` | Method 3/4 AXI4-Lite slave wrapper with sticky-done |
| `sw/accel_monitor.c` | Method 3 bare-metal UART monitor (text menu) |
| `vio_debug.xdc` | Method 2 constraints: clock pin, debug-hub frequency, optional `MARK_DEBUG` lines |
| `zedboard_accelerator.xdc` | Method 1 pin template — **verify against the Digilent master XDC for your board revision** |
| `vio_demo.tcl` | Hardware Manager script: loads T5, runs the job, reads back and checks all 16 results |

### How the debug cores get wired in — the short version

You instantiate `vio_0` and `ila_0` in the harness and connect their `probe*` ports. You never
instantiate the **debug hub** — during `opt_design` Vivado finds debug cores with an unconnected
hub interface, inserts `dbg_hub`, wires every core to it, and connects it to the device JTAG chain
through a `BSCANE2` primitive on user scan chain 1. No package pins are consumed, because the JTAG pins
are dedicated configuration pins. At bitstream time Vivado also writes a **`.ltx`** probes file mapping
probe indices to net names — **program with both the `.bit` and the `.ltx`** or the dashboards will not
appear. Full detail in `VIO_ILA.pdf` §8A.

### Running the demo

```tcl
cd <path>/FPGA_IMPL
source vio_demo.tcl
accel_demo
```

```
  C = A x W :
    [      1      2      3      4 ]   OK
    [      5      6      7      8 ]   OK
    [      9     10     11     12 ]   OK
    [     28     32     36     40 ]   OK

  PASS -- hardware matches the simulation golden model.
```

**Board setup:** cable on **J17** (not J14) · JP7–JP11 all to GND (JTAG mode) · `PGOOD` lit ·
program `xc7z020_1`, not `arm_dap_0`.

### `accel_axi` register map (Method 3/4)

Byte address = index × 4:

`0 NUMVEC(W) · 1 ACT_BASE(W) · 2 OUT_BASE(W) · 3 W_WDATA(W) · 4 W_COMMIT(W) · 5 A_WDATA(W) ·
6 A_COMMIT(W) · 7 START(W) · 8 O_ADDR(W) · 9 STATUS(R: busy, done, phase) · 10–13 ORD0–3(R)`

Note the same architectural pattern as the VIO harness — a **commit register** that turns a bus write
into a one-cycle strobe, and a **sticky-done** bit. Those two pieces of glue are inherent to bridging a
slow host to a fast pipeline, not specific to VIO.

---

## 15. Timing closure results

Constraint: `create_clock -name sys_clk -period 10.000 [get_ports clk]` — **100 MHz**, single clock
domain, synchronous reset.

| Build | WNS | WHS | WPWS | Endpoints | Verdict |
|-------|-----|-----|------|-----------|---------|
| Accelerator alone (out-of-context synthesis, no debug logic) | **+1.279 ns** | +0.263 ns | +3.750 ns | 0 failing of 1 305 | ~12.8 % margin |
| **ZedBoard debug build** (`vio_debug_top` + VIO + ILA + `dbg_hub`) | **+0.714 ns** | +0.045 ns | +3.750 ns | **0 failing of 5 181** | **All user specified timing constraints are met.** |

TNS = THS = TPWS = **0.000 ns** in both. Estimated F<sub>max</sub> ≈ **108 MHz** for the debug build
(`1 / (10.000 − 0.714) ns`).

### Utilisation

| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slice LUTs | 1 564 | 53 200 | 2.94 |
| Slice Registers | 792 | 106 400 | 0.74 |
| Block RAM Tile | 2.5 | 140 | 1.79 |
| **DSPs** | **0** | 220 | 0.00 |
| LUT as Memory | 40 | 17 400 | 0.23 |

### The critical path

The multiply-accumulate inside `processing_element`: `psum_q` → combinational `wload` output mux →
routing to the PE below → 32-bit signed adder (whose other operand is the 8×8 signed product
`weight_q * a_in`) → `valid_in` accumulate/bypass mux → next `psum_q`.

**0 DSPs are used** — all sixteen 8×8 multipliers were mapped into LUT fabric, which is why the LUT
count is 1 564. Forcing DSP48E1 inference with `(* use_dsp = "yes" *)` is the single highest-value
change if the clock is ever raised.

### Why the design closes timing comfortably

Systolic architecture (short, local, register-to-register links only — no combinational path spans the
array) · every PE output registered · deeply pipelined by construction · narrow datapath (int8 × int8 →
int32) · tiny control logic · **no back-pressure or handshakes**, which removes a whole category of
backwards-running combinational paths · very low utilisation, so routing is uncongested · a relaxed
100 MHz target on a 7-series part.

### What eroded the margin, and what to do if it fails

The debug cores cost ~0.565 ns of setup slack — the ILA's capture BRAMs, two 128-bit probes, and the
hub all compete for routing near the logic they observe. If timing fails: reduce ILA depth 1024 → 256
(saves ≈ 6 BRAM36), drop wide probes you are not reading, drop `-flatten_hierarchy none`, force DSP
inference. **Last resort — and legitimate here: none of the four interface methods depends on
throughput.** Add an MMCM and clock the fabric at 50 MHz; just remember to update
`C_CLK_INPUT_FREQ_HZ` on `dbg_hub` to match, or you trade a timing failure for a "debug hub not
detected".

> Full treatment — setup/hold equations, slack, WNS vs TNS, how to read a Vivado timing report line by
> line, a negative-WNS checklist, and an interview/viva question bank — is in **`FPGA_IMPL/timing.pdf`**.

---

## 16. How to reproduce everything

### Simulation regression

```powershell
cd verification_recheck\testbenches
.\run_all_testbenches.ps1        # exits non-zero on any failure
```

### Out-of-context synthesis (accelerator alone)

```tcl
create_project -in_memory -part xc7z020clg484-1
foreach f [glob <RTL_DIR>/*.sv] { read_verilog -sv $f }
read_xdc clk_only.xdc              ;# only: create_clock -period 10.000 [get_ports clk]
synth_design -top accelerator_system_top -part xc7z020clg484-1 -mode out_of_context
report_utilization
report_timing_summary
```

### Full ZedBoard debug build

```tcl
create_project -in_memory -part xc7z020clg484-1
read_verilog -sv [glob <RTL_DIR>/*.sv]
read_verilog -sv FPGA_IMPL/rtl/vio_debug_top.sv
read_ip vio_0/vio_0.xci ; read_ip ila_0/ila_0.xci
synth_ip [get_ips]
read_xdc FPGA_IMPL/vio_debug.xdc

synth_design -top vio_debug_top -part xc7z020clg484-1
opt_design                    ;# ← dbg_hub is auto-inserted HERE
place_design
phys_opt_design
route_design

report_timing_summary -file timing_summary_routed.rpt    ;# sign-off numbers
report_utilization    -file utilization_routed.rpt
report_drc            -file drc_routed.rpt

write_bitstream    -force vio_debug_top.bit
write_debug_probes -force vio_debug_top.ltx
```

### Checks worth running every time

```tcl
check_timing                   # unconstrained clocks/endpoints — run this FIRST
report_clocks                  # exactly 1 clock, period 10.000
get_debug_cores                # must list dbg_hub, u_vio, u_ila
get_cells -hier u_os_start     # the oneshot instances must have survived
report_timing -delay_type max -nworst 10   # confirm the critical path is the PE MAC
```

---

## 17. Troubleshooting

| Symptom | Most likely cause | Fix |
|---------|-------------------|-----|
| "The debug hub core was not detected" | The hub does not know its clock frequency, or JTAG is too fast | Set `C_CLK_INPUT_FREQ_HZ 100000000` and `C_ENABLE_CLK_DIVIDER false`; lower the JTAG frequency to ≤ 6 MHz |
| No `hw_vio_1` / `hw_ila_1` | The `.ltx` was not loaded with the bitstream | Re-program and set *Debug probes file* to `impl_1/vio_debug_top.ltx` |
| Device does not appear at all | Cable, port, or jumpers | Use **J17**, JP7–JP11 to GND, `PGOOD` lit, reinstall Vivado cable drivers |
| `busy` reads 1 forever | Reset never released, or `start` stuck high | POR is 65 536 clocks ≈ 655 µs, so this is **never** a "wait longer" problem — check `vio_start_lvl` is 0 and the `oneshot` instances survived |
| `done_count` jumps by thousands per click | The one-shot was optimised away or bypassed | Confirm `start_p` is driven by a **flop**, not directly by the VIO |
| `done_sticky` never sets | `start` arrived while `busy` was high, so it was ignored | Read `busy` first; it must be 0 |
| **All results read 0** | Host writes masked because `busy` was 1, or the writes never pulsed | Re-load with `busy == 0`; trigger the ILA on `w_we_p == 1` and confirm exactly four 1-clock spikes |
| Result is transposed or lane-scrambled | Wrong lane order in the packed word | **Lane 0 is the LOW byte** — see [§6](#6-memories-and-data-layout) |
| **Row 3 correct (`28 32 36 40`) but rows 0–2 wrong** | Weight rows written in reverse order by the host | Write `weight_mem[0..3]` in **natural** order — the bottom-first shift is the AGU's job |
| Small result reads with shifted lanes | Vivado dropped leading zeros in the hex string | Left-pad to 32 hex characters before slicing |
| Negative results read as ≈ 4 billion | Missing int32 sign extension | Subtract `0x1_0000_0000` from any lane ≥ `0x80000000` |
| Tcl script "runs" but nothing changes on the board | Missing `commit_hw_vio` | `set_property` only stages locally |
| Readback never changes | Missing `refresh_hw_vio` | You are reading a stale cached snapshot |
| Results read as `X` in simulation | The memories have no reset | Expected — write every address you intend to read |
| Timing fails after adding debug cores | ILA depth and wide probes cost routing | See [§15](#15-timing-closure-results) |

---

## 18. FAQ

**Why is there no AXI interface in the core?**
Deliberate. The accelerator exposes plain memory write ports plus `start`/`done`, so it can be driven by
a testbench, by switches, by a VIO, or by an AXI wrapper without the core knowing or caring. `accel_axi.sv`
adds AXI4-Lite when you want it.

**Why does the weight memory hold only four words?**
Because a 4×4 int8 matrix *is* 4 × 32 bits, and the weights are stationary — loaded once per job, never
re-fetched. A deeper weight memory would be dead silicon. See [§6](#6-memories-and-data-layout).

**Why is `a_mem` 256 deep?**
So one weight load can be amortised over up to 256 activation vectors. That amortisation is the entire
economic point of a weight-stationary array.

**What happens if I set `num_vectors = 0`?**
Nothing bad. WLOAD exits straight to DRAIN (and so does IDLE when the weight load is skipped). Without that guard the compute counter would compare against
`8'hFF` and sit for 256 cycles issuing garbage writes.

**Can I pulse `start` again while a job is running?**
Yes, and it does nothing — `start` is sampled only in IDLE.

**Why does the design use 0 DSPs?**
Vivado mapped all sixteen 8×8 signed multipliers into LUT fabric. It meets 100 MHz that way, but it is
why the LUT count is 1 564 and why forcing DSP inference is the first lever if you raise the clock.

**Simulation passes 3 680 checks — doesn't that prove the hardware works?**
No. Simulation proves the **logic** is right; RTL simulation is zero-delay and can never detect a setup
violation. Timing closure proves the **silicon** can run it at 100 MHz. Both are required, and they are
independent. That is exactly why the hardware bring-up replays the same T5 vector through the VIO —
a match there proves the function *and* the timing together.

**Why replay the same vector on hardware instead of writing new hardware tests?**
Because it makes the hardware run *comparable* to the simulation run rather than a new, separate
experiment. Combined with the frozen RTL, any mismatch on the board is then unambiguously a hardware or
setup problem — which is what makes it debuggable.

**What is the maximum frequency?**
Estimated ≈ 108 MHz for the debug build from `1 / (10.000 − WNS)`. Treat that as an extrapolation, not
a promise — the tools optimise *to the constraint*, so the only way to know is to re-run implementation
at the new period.

**Can this scale beyond 4×4?**
The wrappers are parameterised in spirit, but `systolic_array` ports are hard-coded `[7:0]` / `[31:0]`,
so `DATA_W`/`PSUM_W` are effectively fixed at 8/32, and nothing has been verified outside
`ROWS = COLS = 4`. A larger array would also need overflow analysis — `psum` has no saturation.

---

## 19. Glossary

| Term | Meaning |
|------|---------|
| **Systolic array** | A grid of identical PEs communicating only with immediate neighbours, one hop per clock |
| **Weight-stationary** | Weights are loaded once and stay in the PEs; activations flow through |
| **PE** | Processing element — the `int8 × int8 → int32` MAC unit; 16 of them here |
| **psum** | Partial sum — the accumulating value marching south through a column |
| **Skew / de-skew** | Converting a dense vector into the array's diagonal wavefront, and back again |
| **Staircase latency** | Column *c* finishes at `n + (ROWS−1) + c` — the `+c` is horizontal travel time |
| **`RESULT_LATENCY` (7)** | Cycles from issuing an activation address to the result being observable |
| **`STORE_LATENCY` (8)** | `RESULT_LATENCY + 1` — when the write strobe fires; also the DRAIN length |
| **AGU** | Address generator unit — counts addresses, holds no policy |
| **Bottom-first** | The weight-load rule: feed `W[ROWS-1]` first so it travels furthest |
| **Back-pressure** | Flow control via ready/valid. **This design has none** — fixed latency instead |
| **VIO** | Virtual Input/Output — a Vivado debug core that drives and reads fabric signals over JTAG |
| **ILA** | Integrated Logic Analyzer — a Vivado debug core that captures a waveform on-chip |
| **`dbg_hub`** | The debug hub Vivado auto-inserts to bridge JTAG to the debug cores |
| **`.ltx`** | The probes file mapping debug-core probe indices to net names; needed at programming time |
| **`MARK_DEBUG`** | A property that preserves a net and marks it for debug — settable from XDC, no RTL edit |
| **STA** | Static Timing Analysis — exhaustive, vectorless delay checking of every path |
| **Slack** | Required time − arrival time. Positive = passes |
| **WNS** | Worst Negative Slack — the minimum setup slack in the design. **The headline timing number** |
| **TNS** | Total Negative Slack — the sum over all failing setup endpoints; 0.000 when nothing fails |
| **WHS / WPWS** | Worst Hold Slack / Worst Pulse Width Slack — both must also be positive |
| **F<sub>max</sub>** | `1 / (T_period − WNS)` — an extrapolation, not a guarantee |

---

## Cross-references

- **Segmented context chunks:** [`context_mkdwn/index.md`](../../context_mkdwn/index.md) — 16 chunks
  (00–15), each a small self-contained fact set, cross-linked with `[[chunk-name]]`
- **Verification report:** [`verification_recheck/`](../../verification_recheck/index.md)
- **FPGA implementation:** [`FPGA_IMPL/README.md`](../../FPGA_IMPL/README.md)
- **Architecture deep-dive:** [`architecture_and_dataflow.pdf`](architecture_and_dataflow.pdf)
- **Beginner's guide:** [`beginners_guide.pdf`](beginners_guide.pdf)
- **Animated testbench walkthrough:** [`TESTBENCHES_visualised.html`](TESTBENCHES_visualised.html)
