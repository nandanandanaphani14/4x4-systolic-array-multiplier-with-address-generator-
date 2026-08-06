# RTL Folder Index (`SIMPLE_ACCEL_RTL`)

Design files for the 4×4 weight-stationary systolic accelerator. Each RTL file maps to a context
chunk in [`../../context_mkdwn/`](../../context_mkdwn/index.md) for retrieval.

> Note: several files carry a module name that differs from the filename.

| RTL file | Module | Context chunk |
|----------|--------|---------------|
| [MAC.sv](MAC.sv) | `processing_element` | [01_processing_element](../../context_mkdwn/01_processing_element.md) |
| [array.sv](array.sv) | `systolic_array` | [02_systolic_array](../../context_mkdwn/02_systolic_array.md) |
| [delay_pipe.sv](delay_pipe.sv) | `delay_pipe` | [03_delay_pipe](../../context_mkdwn/03_delay_pipe.md) |
| [input_buf.sv](input_buf.sv) | `input_skew_buffer` | [04_input_skew_buffer](../../context_mkdwn/04_input_skew_buffer.md) |
| [output_skewbuf.sv](output_skewbuf.sv) | `output_deskew_buffer` | [05_output_deskew_buffer](../../context_mkdwn/05_output_deskew_buffer.md) |
| [a_mem.sv](a_mem.sv) | `a_mem` | [06_memories](../../context_mkdwn/06_memories.md) |
| [weight_mem.sv](weight_mem.sv) | `weight_mem` | [06_memories](../../context_mkdwn/06_memories.md) |
| [outmem.sv](outmem.sv) | `output_mem` | [06_memories](../../context_mkdwn/06_memories.md) |
| [controller.sv](controller.sv) | `controller` | [07_controller_fsm](../../context_mkdwn/07_controller_fsm.md) |
| [agu.sv](agu.sv) | `agu` | [08_agu](../../context_mkdwn/08_agu.md) |
| [wrapper_array_buf.sv](wrapper_array_buf.sv) | `array_buf_top` (L1) | [09_wrapper_L1_array_buf](../../context_mkdwn/09_wrapper_L1_array_buf.md) |
| [wrapper_mem_arr_buf.sv](wrapper_mem_arr_buf.sv) | `accelerator_top` (L2) | [10_wrapper_L2_accel_top](../../context_mkdwn/10_wrapper_L2_accel_top.md) |
| [wrapper_full_system.sv](wrapper_full_system.sv) | `accelerator_system_top` (L3) | [11_wrapper_L3_system_top](../../context_mkdwn/11_wrapper_L3_system_top.md) |

Timing/dataflow that spans files: [12_dataflow_and_timing](../../context_mkdwn/12_dataflow_and_timing.md).

_This index.md is the only file added to this folder; no existing RTL was modified._
