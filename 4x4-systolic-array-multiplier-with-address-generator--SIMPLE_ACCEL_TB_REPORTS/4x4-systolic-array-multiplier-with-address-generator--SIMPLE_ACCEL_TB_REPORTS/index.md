# TB Reports Folder Index (`SIMPLE_ACCEL_TB_REPORTS`)

> ## ⚠ SUPERSEDED — historical baseline, do not use for current cycle counts
>
> Everything in this folder describes the RTL **as it was on 2026-07-30**, before two changes to
> `controller.sv`:
>
> 1. the **FLUSH phase was removed** (was `ROWS + 2 = 6` cycles between WLOAD and COMPUTE);
> 2. **WLOAD is now skipped** when the weight matrix has not changed since the last job.
>
> So these transcripts still show a 6-state FSM, phase encodings `COMPUTE=3 / DRAIN=4 / DONE=5`, and a
> job length of `num_vectors + 19` (23 clocks for a 4×4). The current figures are **`N + 13` = 17
> clocks**, or **`N + 9` = 13 clocks** reusing weights, with a 5-state FSM encoded
> `IDLE=0 WLOAD=1 COMPUTE=2 DRAIN=3 DONE=4`.
>
> These logs are **deliberately not regenerated**: they are the historical record, and their
> testbench suite (`tb_a_mem`, `tb_weight_mem`, `tb_output_mem`, 13 testbenches) no longer exists —
> it was consolidated into the 11-testbench suite in `verification_recheck/`. Rewriting them would
> fabricate a run that never happened.
>
> **For current results see [`../../verification_recheck/`](../../verification_recheck/index.md):**
> 11/11 PASS, 3 680 checks, 0 mismatches.

The **original** verification transcripts and report (QuestaSim 2021.1, run 2026-07-30, 13/13 PASS,
3 902 checks). For the **independent re-verification** performed later, see
[`../../verification_recheck/`](../../verification_recheck/index.md).

| Artifact | Content |
|----------|---------|
| [verification_report.md](verification_report.md) | full strategy, results table, defects, coverage boundaries |
| [regression_summary.txt](regression_summary.txt) | machine-readable roll-up |
| [compile.log](compile.log) | compile transcript |
| `tb_*.log` | one transcript per original testbench |

Map to context chunks: strategy & coverage → [14_coverage_boundaries](../../context_mkdwn/14_coverage_boundaries.md);
latency constants checked → [12_dataflow_and_timing](../../context_mkdwn/12_dataflow_and_timing.md);
per-DUT detail → chunks [01](../../context_mkdwn/01_processing_element.md)–[11](../../context_mkdwn/11_wrapper_L3_system_top.md).

_This index.md is the only file added to this folder; existing reports/logs were not modified._
