# TB Folder Index (`SIMPLE_ACCEL_TB`)

This branch holds the **test plan** ([README.md](README.md)) — a bottom-up hierarchy: test individual
elements, then the system at rising abstraction levels.

The plan is captured and mapped to the re-verification testbenches in context chunk
[15_test_plan](../../context_mkdwn/15_test_plan.md).

| Test plan level | Context chunk |
|-----------------|---------------|
| Processing element | [01_processing_element](../../context_mkdwn/01_processing_element.md) |
| 4×4 grid of PE | [02_systolic_array](../../context_mkdwn/02_systolic_array.md) |
| Memories | [06_memories](../../context_mkdwn/06_memories.md) |
| Delay pipe / input skew / output de-skew | [03_delay_pipe](../../context_mkdwn/03_delay_pipe.md), [04_input_skew_buffer](../../context_mkdwn/04_input_skew_buffer.md), [05_output_deskew_buffer](../../context_mkdwn/05_output_deskew_buffer.md) |
| Address generator unit | [08_agu](../../context_mkdwn/08_agu.md) |
| Control unit | [07_controller_fsm](../../context_mkdwn/07_controller_fsm.md) |
| Golden reference vectors | [13_worked_example](../../context_mkdwn/13_worked_example.md) |

> The actual re-verification testbenches, run logs, and recheck report live in the created
> [`verification_recheck/`](../../verification_recheck/index.md) folder.

_This index.md is the only file added to this folder; the existing README was not modified._
