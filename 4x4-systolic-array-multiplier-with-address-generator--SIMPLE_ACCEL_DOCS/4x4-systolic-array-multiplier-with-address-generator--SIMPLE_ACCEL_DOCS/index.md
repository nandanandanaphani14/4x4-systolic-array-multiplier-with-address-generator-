# DOCS Folder Index (`SIMPLE_ACCEL_DOCS`)

User documentation for the accelerator. The architecture doc is the authoritative source distilled
into the context chunks in [`../../context_mkdwn/`](../../context_mkdwn/index.md).

| Doc | Content | Distilled into chunks |
|-----|---------|-----------------------|
| [architecture_and_dataflow.html](architecture_and_dataflow.html) / .pdf | full architecture, cycle-level dataflow, timing derivations, animations | 00–14 (esp. [12_dataflow_and_timing](../../context_mkdwn/12_dataflow_and_timing.md), [13_worked_example](../../context_mkdwn/13_worked_example.md)) |
| [beginners_guide.html](beginners_guide.html) / .pdf | same design from zero, line-by-line walkthroughs | [00_system_overview](../../context_mkdwn/00_system_overview.md), [01_processing_element](../../context_mkdwn/01_processing_element.md) |
| [Home.md](Home.md) | **GitHub wiki page** — whole-project reference: architecture, dataflow, host protocol, verification, FPGA implementation, timing results, troubleshooting, FAQ, glossary | 00–15 (all) |
| [README.md](README.md) | folder purpose | — |

Section → chunk highlights:
- Architecture: the three levels → [09](../../context_mkdwn/09_wrapper_L1_array_buf.md)/[10](../../context_mkdwn/10_wrapper_L2_accel_top.md)/[11](../../context_mkdwn/11_wrapper_L3_system_top.md)
- Word formats and data layout → [06_memories](../../context_mkdwn/06_memories.md)
- Timing derivations → [12_dataflow_and_timing](../../context_mkdwn/12_dataflow_and_timing.md)
- Known limitations → [14_coverage_boundaries](../../context_mkdwn/14_coverage_boundaries.md)

_This index.md is the only file added to this folder; existing docs were not modified._
