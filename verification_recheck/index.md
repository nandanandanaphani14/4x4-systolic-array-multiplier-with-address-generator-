# verification_recheck — Index

Independent functional re-verification of the systolic-array accelerator (QuestaSim 2021.1,
2026-08-03). The original RTL and the original `SIMPLE_ACCEL_TB_REPORTS/` baseline are untouched;
everything here is newly created.

**Result: 11/11 testbenches PASS · 3 680 checks · 0 mismatches · 0 RTL defects.**

> **Re-run 2026-08-06 after two controller changes.** The **FLUSH phase was removed** and **WLOAD is
> now skipped when the weight matrix has not changed**, so job length went from `N + 19` (23 clocks
> for a 4×4) to **`N + 13` = 17 clocks**, or **`N + 9` = 13 clocks** reusing weights. The FSM is now
> 5 states, encoded `IDLE=0 WLOAD=1 COMPUTE=2 DRAIN=3 DONE=4`.
>
> `tb_controller` (78→94 checks) and `tb_accelerator_system_top` (187→199) were extended to cover
> both paths, including a **state trace** that asserts the exact phase sequence per job —
> `WLOAD→COMPUTE→DRAIN→DONE` when loading, `COMPUTE→DRAIN→DONE` when skipping. That is the direct
> proof that IDLE goes straight to COMPUTE; a cycle count alone could not distinguish "WLOAD never
> entered" from "WLOAD entered for zero cycles". All logs in [`logs/`](logs/) are from this run.

## Contents
| Path | What |
|------|------|
| [verification_recheck_report.md](verification_recheck_report.md) | full report: strategy, per-TB proof, defects, coverage |
| [testbenches/](testbenches/) | 11 testbenches + `tb_common.svh` harness + `run_all_testbenches.ps1` |
| [logs/](logs/) | `compile.log`, `regression_summary.txt`, one `tb_*.log` per testbench |
| [sim/](sim/) | generated QuestaSim work library |
| [doc_backup_original/](doc_backup_original/) | pre-edit copies of the architecture HTML/PDF |

## Testbench → DUT → context chunk
| Testbench | DUT | Context |
|-----------|-----|---------|
| tb_delay_pipe | delay_pipe | [03](../context_mkdwn/03_delay_pipe.md) |
| tb_processing_element | processing_element | [01](../context_mkdwn/01_processing_element.md) |
| tb_memories | a_mem/weight_mem/output_mem | [06](../context_mkdwn/06_memories.md) |
| tb_input_skew_buffer | input_skew_buffer | [04](../context_mkdwn/04_input_skew_buffer.md) |
| tb_output_deskew_buffer | output_deskew_buffer | [05](../context_mkdwn/05_output_deskew_buffer.md) |
| tb_systolic_array | systolic_array | [02](../context_mkdwn/02_systolic_array.md) |
| tb_array_buf_top | array_buf_top (L1) | [09](../context_mkdwn/09_wrapper_L1_array_buf.md) |
| tb_controller | controller | [07](../context_mkdwn/07_controller_fsm.md) |
| tb_agu | agu | [08](../context_mkdwn/08_agu.md) |
| tb_accelerator_top | accelerator_top (L2) | [10](../context_mkdwn/10_wrapper_L2_accel_top.md) |
| tb_accelerator_system_top | accelerator_system_top (L3) | [11](../context_mkdwn/11_wrapper_L3_system_top.md) |

Reproduce: `.\testbenches\run_all_testbenches.ps1` (exits non-zero on any failure).

See also: master context index [`../context_mkdwn/index.md`](../context_mkdwn/index.md) and the
animated [`TESTBENCHES_visualised.html`](../4x4-systolic-array-multiplier-with-address-generator--SIMPLE_ACCEL_DOCS/4x4-systolic-array-multiplier-with-address-generator--SIMPLE_ACCEL_DOCS/TESTBENCHES_visualised.html).
