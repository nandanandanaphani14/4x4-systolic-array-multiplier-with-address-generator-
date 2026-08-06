# Verification Report — 4×4 Weight-Stationary Systolic Accelerator

**Date:** 2026-07-30
**Simulator:** QuestaSim (`D:\SOFTWARES\QUESTASIM\win64\vsim.exe`)
**Scope:** every RTL module in [`design_rtl/`](../design_rtl/), verified individually and then at
three levels of integration.

---

## 1. Headline result

| | |
|---|---|
| Testbenches run | **13 / 13 passed** |
| Individual checks executed | **3 902** |
| Mismatches | **0** |
| Compile errors | 0 |
| Compile warnings | 9 × `vlog-13314` (benign — see §7) |
| Transcript volume | ~2 900 lines across 13 logs |

Raw transcripts: [`sim_logs/`](sim_logs/). Machine-readable roll-up:
[`sim_logs/regression_summary.txt`](sim_logs/regression_summary.txt).

Each transcript carries a header, a test plan, the decoded stimulus, a per-transaction trace, and a
per-section summary table — so a passing run is reviewable, not just green. Format described in
[`../DOCS/testbench_description.md` §1](../DOCS/testbench_description.md#1-common-structure-and-log-format).

Reproduce with:

```powershell
.\test_benches\run_all_testbenches.ps1
```

The script exits non-zero if any testbench fails, so it is usable in CI.

---

## 2. Results table

| # | Testbench | DUT | Level | Checks | Result |
|---|-----------|-----|-------|--------|--------|
| 1 | `tb_delay_pipe` | `delay_pipe` | leaf | 127 | PASS |
| 2 | `tb_processing_element` | `processing_element` (MAC.sv) | leaf | 1 566 | PASS |
| 3 | `tb_a_mem` | `a_mem` | leaf | 538 | PASS |
| 4 | `tb_weight_mem` | `weight_mem` | leaf | 125 | PASS |
| 5 | `tb_output_mem` | `output_mem` (outmem.sv) | leaf | 455 | PASS |
| 6 | `tb_input_skew_buffer` | `input_skew_buffer` (input_buf.sv) | leaf | 366 | PASS |
| 7 | `tb_output_deskew_buffer` | `output_deskew_buffer` (output_skewbuf.sv) | leaf | 188 | PASS |
| 8 | `tb_systolic_array` | `systolic_array` (array.sv) | fabric | 37 | PASS |
| 9 | `tb_array_buf_top` | `array_buf_top` | **wrapper L1** | 76 | PASS |
| 10 | `tb_controller` | `controller` | control | 85 | PASS |
| 11 | `tb_agu` | `agu` | control | 62 | PASS |
| 12 | `tb_accelerator_top` | `accelerator_top` | **wrapper L2** | 76 | PASS |
| 13 | `tb_accelerator_system_top` | `accelerator_system_top` | **wrapper L3** | 201 | PASS |

Check counts are not a quality metric on their own — a memory testbench that sweeps 256 addresses
racks up checks cheaply, while `tb_systolic_array`'s 37 checks each compare a full 32-bit dot
product against an independently computed golden value. §4 describes what each testbench actually
proves.

---

## 3. Verification strategy

### 3.1 Three levels of integration, three separate wrappers

Rather than one monolithic top, the design is closed at three levels, each in its own file and each
with its own testbench. A wrapper instantiates the level below it instead of re-wiring the fabric,
so the levels cannot drift apart.

| Level | Module | File | Adds | Testbench |
|-------|--------|------|------|-----------|
| 1 | `array_buf_top` | `wrapper_array_buf.sv` | skew + array + de-skew | `tb_array_buf_top` |
| 2 | `accelerator_top` | `wrapper_mem_arr_buf.sv` | the three SRAMs | `tb_accelerator_top` |
| 3 | `accelerator_system_top` | `wrapper_full_system.sv` | control FSM + AGU | `tb_accelerator_system_top` |

### 3.2 Golden models are algorithmic, not RTL mirrors

From `tb_systolic_array` upwards the expected values are the mathematical product **C = A × W**
computed by plain nested loops in the testbench. Nothing about the expected *value* is derived from
the RTL, so a bug copied from design into testbench is not possible for the datapath result.

Only the expected *cycle* is derived from the pipeline structure, and each latency constant is
verified independently at the level below:

```
level 1  result latency = ROWS + COLS - 2         = 6 cycles after the dense vector
level 2  result latency = 1 + ROWS + COLS - 2     = 7 cycles after the address (SRAM adds 1)
         store  latency = result latency + 1      = 8 cycles after the address
```

The leaf testbenches (`tb_delay_pipe`, `tb_processing_element`) do use a cycle-accurate reference
model, because for a single register or a single MAC the model *is* the specification. Both are
backed by directed vectors with hand-computed constants (e.g. `100 + 3×5 = 115`,
`(−128)×(−128) = 16384`) that do not depend on the model at all.

### 3.3 Timing convention

Every testbench uses one of two explicit sampling conventions, stated in the header of each file:

- **Registered outputs** — drive just after a posedge, let the *next* posedge consume it, then
  sample. Used by the PE, the memories, the array and all wrappers.
- **Delay lines and address buses** — drive just after a posedge, sample *before* the next posedge.
  A combinational path (`DELAY=0`, or an address bus feeding an SRAM) and a 1-deep register look
  identical if sampled after the edge; sampling before the edge separates them.

This is not incidental. Two of the three defects found during this work were violations of it
(§5).

### 3.4 Negative checks

Passing tests prove the design does something; negative checks prove the testbench would notice if
it did not:

- `tb_systolic_array` / `tb_array_buf_top` assert that a result is **not** present one cycle early.
- `tb_agu` fails on a *missing* write strobe as well as an unexpected one, and counts total strobes
  against the vector count.
- `tb_accelerator_system_top` hammers the host write ports throughout a live job and requires the
  results to be bit-identical to a clean run.
- `tb_output_deskew_buffer` requires all columns to be empty until the last column has been fed.

---

## 4. What each testbench proves

### 4.1 `tb_delay_pipe` — 127 checks
Random 40-cycle stream through three parallel instances (`DELAY` = 0, 1, 3). Confirms `DELAY=0` is a
true combinational wire and not a register, per-cycle delay accuracy for `DELAY` > 0, synchronous
reset flushing the pipe, and a single pulse walking the pipe stage by stage after reset. The
`DELAY=0` case is checked to *ignore* reset, since it has no state.

### 4.2 `tb_processing_element` — 1 566 checks
Two independent layers:

- **Directed**, with hand-computed constants: `weight=3, a=5, psum=100 → 115`; negative weight
  `(−4)×7 = −28`; both operands most-negative `(−128)×(−128) = +16384`; mixed sign
  `50 + 127×(−2) = −204`; `valid_in=0` bypass passes `psum_in` through untouched; during `wload`,
  `psum_out` exposes the stored weight sign-extended (`−3 → 0xFFFFFFFD`).
- **Randomised**: 500 cycles of random `{wload, valid_in, a_in, psum_in}` against a cycle-accurate
  reference model, checking `a_out`, `valid_out` and `psum_out` every cycle.

Also covers reset clearing all four registers, reset asserted mid-stream, and correct operation
immediately after reset release.

### 4.3 `tb_a_mem` / `tb_weight_mem` / `tb_output_mem` — 538 / 125 / 455 checks
All three are the same single-port synchronous RAM primitive at different widths and depths. Each
testbench covers full-array write/read-back, one-cycle read latency, `we=0` leaving memory
untouched, address independence, data patterns (all-zero, all-one, walking one/zero), and randomised
interleaved traffic against a reference array.

Two behaviours matter downstream and are checked explicitly:

- **Read-during-write returns pre-write data.** `mem[addr] <= wdata` and `rdata <= mem[addr]` are
  both non-blocking, so a read collides with a write to the same address returns the *old* contents.
- **Lane integrity.** `weight_mem` is checked byte-lane by byte-lane (lane *c* = column *c* weight)
  and `output_mem` 32-bit lane by lane (lane *c* = column *c* result), because the wrappers rely on
  exactly that packing.

`tb_weight_mem` additionally verifies that its 2-bit address wraps (address 4 aliases to 0).

### 4.4 `tb_input_skew_buffer` — 366 checks
Random 40-cycle stream verifying row *r* is delayed by exactly *r* clocks, and that the **valid bit
travels with its data** — data and valid never separate. A directed test walks a single dense vector
through as a diagonal wavefront, checking that row *r* presents its element at offset *r* and that
rows already passed have gone quiet. Back-to-back streaming and reset flushing are also covered.

### 4.5 `tb_output_deskew_buffer` — 188 checks
Verifies column *c* is delayed by `COLS-1-c`. The key test is **alignment**: the staircase the array
actually emits (column *c* finishing *c* cycles after column 0) is fed in, and all four columns are
required to emerge on a single cycle — and to be empty on every cycle before that. Extreme signed
values (`0x80000000`, `0x7FFFFFFF`, `−1`) are checked to pass through bit-exact. Column `COLS-1` is
verified to be a plain wire that ignores reset.

### 4.6 `tb_systolic_array` — 37 checks
First fully algorithmic golden model. A random, non-symmetric 4×4 weight matrix is shifted in, then
eight activation vectors are streamed — five back-to-back, then an 8-cycle gap, then three more —
and every one of the 32 resulting dot products is compared against `C = A × W`.

Because *W* is random and non-symmetric, **any** permutation of the weight rows would fail. This is
what proves the non-obvious loading rule: while `wload=1` the vertical bus is a downward shift
register, so the row driven **first** travels furthest and lands in the **bottom** array row.
Weight rows must be fed `W[ROWS-1]` first.

Also verified: the per-column staircase timing is exactly `(ROWS-1)+c`; the array is fully flushed
(all zeros) after the weight-load phase; and a result does not appear a cycle early.

### 4.7 `tb_array_buf_top` — 76 checks (wrapper level 1)
Same golden model, but with the skew and de-skew buffers inside the DUT, so the whole result vector
must now appear **aligned on a single cycle** at `ROWS+COLS-2` = 6 cycles. The testbench also taps
the pre-de-skew bus and confirms the staircase is still there — proving that it is the de-skew
buffer doing the alignment, not the golden model being permissive.

### 4.8 `tb_controller` — 85 checks
Phase lengths are measured by *counting clocks with each enable high*, not by inspecting the state
encoding:

| Phase | Length | Verified |
|-------|--------|----------|
| `WLOAD` | `ROWS` = 4 | yes |
| `FLUSH` | `FLUSH_CYCLES` = `ROWS+2` = 6 | yes |
| `COMPUTE` | `num_vectors` | yes, for 0, 1, 3, 4, 6, 8, 16 |
| `DRAIN` | `STORE_LATENCY` = 8 | yes |
| `DONE` | 1 cycle | yes |
| **total job** | `num_vectors + 19` | yes |

The total job length is measured independently of the phase counters — every clock from the edge
that consumes `start` to the `done` pulse — so the `num_vectors + 19` figure quoted in the
documentation is verified rather than merely derived.

Also verified: phase enables are mutually exclusive at all times; `start` is ignored while busy
(hammered throughout a job — phase lengths unchanged, no second job starts); `done` is a
single-cycle pulse and `busy` is already low when it fires; back-to-back jobs of different lengths;
reset mid-job returns to `IDLE` and the FSM still accepts a fresh job afterwards.

**`num_vectors = 0` is verified not to hang** — the FSM skips `COMPUTE` and still reaches `DONE`.

### 4.9 `tb_agu` — 62 checks
Driven by testbench-generated phase enables rather than the real FSM, so a controller bug cannot
mask an AGU bug. Verifies weight addresses count **down** `ROWS-1…0` (the ordering that makes weight
row *r* land in array row *r*), that the counter re-arms between jobs, that activation addresses
count up from `act_base`, and that both `act_base` and `out_base` are honoured.

The central check is the write-strobe scoreboard: every activation address issued schedules an
expected `{out_we, out_addr}` exactly `STORE_LATENCY` cycles later, and the testbench flags
**extra**, **missing** and **misaddressed** strobes separately. Across the run: one write per
vector, none spurious, none dropped.

### 4.10 `tb_accelerator_top` — 76 checks (wrapper level 2)
End-to-end through the memories, sequenced by the testbench acting as host: preload `a_mem` and
`weight_mem`, shift in weights, flush, stream vectors (burst + gap + burst), store results, then
read `output_mem` back and compare against `C = A × W` lane by lane. Also checks the live `result`
bus at `addr + 7`, that the datapath is quiet after the flush, and that the activation preload is
still intact at the end of the run.

### 4.11 `tb_accelerator_system_top` — 201 checks (wrapper level 3)
The testbench now acts purely as the *Host / Testbench Interface* box of the architecture diagram:
it loads matrices, pulses `start`, waits for `done`, and reads results. **It never drives an address
or a strobe during a run** — the FSM and AGU do all sequencing. Four jobs are run:

1. Clean 8-vector job → results match `C = A × W`.
2. Identical job while the host **hammers both write ports with garbage throughout**
   (`0xDEADBEEF` into `weight_mem`, `0xBAADF00D` into `a_mem`). Results are bit-identical to run 1,
   proving the `busy`-based port arbitration masks host writes. Run 1's output block is re-read
   afterwards and is unchanged, proving `out_base` isolation.
3. `act_base` pointed at a second activation block → produces that block's product.
4. A 3-vector job → exactly three output words written; the fourth word is sampled before and after
   and is untouched.

A fifth pass cross-checks that every golden row was visible on the live `result` bus during the run,
not only in memory.

---

## 5. Defects found and fixed

### 5.1 Logic defects

Three logic defects were found. **All three were in testbench code, not in the RTL.** No RTL bug was
found by this regression.

| # | Where | Symptom | Cause | Fix |
|---|-------|---------|-------|-----|
| 1 | `tb_output_mem` | 2 mismatches on packed signed lanes | Expected value `128'(-32'sd1)` sign-extends to 128 bits, but the actual `rd[32+:32]` part-select is unsigned and zero-extends | Write expected lane values as unsigned bit patterns (`32'hFFFF_FFFF`) |
| 2 | `tb_agu` | All address checks off by one | Sampled the address bus *after* the edge that consumes it, reading the counter's next value | Sample before the edge: drive → sample → advance clock |
| 3 | `tb_controller` | `WLOAD` measured as 3 instead of 4 | Phase counters cleared *after* the start pulse, discarding the first `WLOAD` cycle (the posedge that consumes `start` is already cycle 1 of `WLOAD`) | Clear counters before pulsing `start` |

Defects 2 and 3 are the same underlying mistake — assuming a signal sampled after a clock edge
represents that edge's input. This is why §3.3 states the sampling convention explicitly in every
testbench header.

### 5.2 Infrastructure issues found while adding verbose logging

Two further issues surfaced when the testbenches were rewritten to produce detailed transcripts.
Neither is an RTL defect, but both would have misled a reader, so they are recorded here.

| # | Where | Symptom | Cause | Fix |
|---|-------|---------|-------|-----|
| 4 | `tb_agu` | `vsim` crashed with `(SIGSEGV) Bad handle or reference` | A `string` declared as a local variable in an `automatic` task and passed to `$display("%s")` — QuestaSim 2021.1 mishandles it | Declare that string at module scope, with a comment explaining why |
| 5 | `run_all_testbenches.ps1` | Reported nonsense check counts (`tb_systolic_array` shown as 1 check instead of 37) while every testbench still correctly reported PASS | The script grepped the *last* line matching `N checks, M errors`; the new per-section progress lines match that pattern too, so a section total was picked up instead of the grand total | Each testbench now prints one explicit `TOTALS: N checks, M errors` line, and the script matches that specifically |

Issue 5 is worth dwelling on: the *pass/fail verdict was never wrong*, only the reported volume. A
summary that silently under-reports its own coverage is exactly the kind of thing a green dashboard
hides, which is why the counts are cross-checked against the transcripts in §1.

### 5.3 What the rewrite did not change

The verbose rewrite touched only reporting. Every testbench produced **exactly** the same check count
afterwards as before — 127, 1566, 538, 125, 455, 366, 188, 37, 76, 85, 62, 76, 201. That invariant is
the evidence that no check was accidentally dropped, weakened or duplicated while the display code
was added.

That no RTL bug was found is a real result for a design of this size, but it is a statement about
these tests, not a proof of correctness. §6 lists what was deliberately not covered.

---

## 6. Coverage boundaries — what is *not* verified

Stated plainly so the report is not read as stronger than it is.

**Not exercised by any test here**

- **Arithmetic overflow.** `psum` is 32 bits with no saturation. With int8 operands and a 4-deep
  column, the worst case is `4 × 128 × 128 = 65 536`, so overflow is unreachable for this array
  size — but nothing guards it, and a larger `ROWS` or wider inputs would silently wrap.
- **Uninitialised memory reads.** All three SRAMs power up as `X`. Every testbench reads only
  addresses it has written. The design has no mechanism to prevent a read of an unwritten address.
- **Parameter sweeps.** Everything is verified at `ROWS = COLS = 4`. `systolic_array`'s port widths
  are hard-coded `[7:0]` / `[31:0]` rather than parameterised, so `DATA_W`/`PSUM_W` on the wrappers
  are effectively fixed at 8/32. Other `ROWS`/`COLS` values are untested.
- **Per-row valid.** `valid_in` is broadcast to all four rows from a single bit. Independent per-row
  valid is structurally supported by the PEs but is never driven that way.
- **Clock-domain and reset-domain issues.** Single clock, synchronous reset, no CDC anywhere.
- **Back-pressure.** There is none in the architecture; the host must respect the latency numbers.

**Out of scope of simulation entirely**

- No synthesis, no timing closure, no gate-level or post-layout simulation. `vlog` passing is not
  evidence the design builds — port-connection type checking happens at elaboration, not
  compilation.
- No formal property verification.
- No functional-coverage collection or coverage closure. "13/13 passed" is a pass rate, not a
  coverage number.
- No power or area analysis.

---

## 7. Compile notes

Nine `vlog-13314` warnings appear:

```
Defaulting port '<name>' kind to 'var' rather than 'wire' due to
default compile option setting of -svinputport=relaxed
```

These are notes about unpacked-array input ports (`a_in_left`, `valid_in_left`, `psum_in_top`,
`dense_a_in`, `dense_valid_in`, `psum_in`) and are benign — SystemVerilog defaults unpacked array
ports to `var`, which is what is wanted here. They are not suppressed, so a genuinely new warning
would still be visible.

---

## 8. Files

```
design_rtl/          13 RTL files  (8 original + controller + agu + 3 wrappers)
test_benches/        13 testbenches + run_all_testbenches.ps1
indi_ver_rep/
├── verification_report.md          this file
└── sim_logs/
    ├── compile.log
    ├── regression_summary.txt
    └── <tb_name>.log               one full transcript per testbench
```

See [`../DOCS/description_index.md`](../DOCS/description_index.md) for per-file descriptions of both
the design and the testbenches.
