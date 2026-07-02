# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is

This is the **Rockchip RKLLM SDK** (`rknn-llm`), a toolkit for deploying LLMs/VLMs to
Rockchip NPU SoCs (RK3588/RK3576/RK3562/RV1126B). It is an SDK, not a web app. Work is
split across two machines:

- **RKLLM-Toolkit** (`rkllm-toolkit/`) — Python SDK that converts/quantizes HuggingFace or
  GGUF models into the `.rkllm` format. **Runs on the host (x86_64 Linux).** This is the
  only component that can be built/run/tested in Cursor Cloud.
- **RKLLM Runtime + demos** (`rkllm-runtime/`, `examples/`) — prebuilt native libs
  (`librkllmrt.so`) and C/C++/Python demos that run **on a physical Rockchip NPU board**
  over ADB. There is **no x86 inference path or emulator**, so end-to-end inference,
  cross-compilation, and the Flask/Gradio server demos (`examples/rkllm_server_demo`,
  port 8080) **cannot be exercised in this environment** — they require real hardware.

There is **no test suite, no linter config, and no Makefile** in this repo. Validation of
the host component is done by running a model conversion.

### Environment

- A Python 3.12 virtualenv is created at `.venv` by the startup update script (installs
  `rkllm-toolkit/packages/requirements.txt` + the `cp312` wheel). Use `.venv/bin/python`.
- **`BUILD_CUDA_EXT=0` must be exported before any pip install on Python 3.12** (the
  `auto_gptq` build needs it). The update script already does this.
- The toolkit installs the CUDA build of torch but runs fine on CPU (no GPU present); pass
  `device='cpu'` to `load_huggingface`.

### Running the toolkit (host smoke test / "hello world")

The core flow is: `load_huggingface` → `build` → `export_rkllm`:

```python
from rkllm.api import RKLLM
llm = RKLLM()
llm.load_huggingface(model=MODEL_DIR, device='cpu', dtype='float32', load_weight=True)
llm.build(do_quantization=True, quantized_dtype='w8a8', target_platform='RK3588',
          num_npu_core=3, dataset='examples/rkllm_api_demo/export/data_quant.json',
          max_context=512)
llm.export_rkllm('out_rk3588.rkllm')
```

A valid `.rkllm` file begins with the magic bytes `da ee b3 36`. See
`examples/rkllm_api_demo/export/export_rkllm.py` for the canonical conversion script (it
points at an external DeepSeek model you must download separately).

### Gotchas discovered during setup

- The shipped custom-architecture demo `rkllm-toolkit/examples/custom_demo/modeling_custom.py`
  targets **transformers ~4.36** and fails to import under the installed **transformers
  5.8.0** (e.g. `is_torch_fx_available`). For a host smoke test, build a random-weight
  model from a natively-supported architecture (e.g. `Qwen2ForCausalLM`) instead of
  executing that custom modeling code.
- For `w8a8` quantized export, each attention K/V projection dim
  (`num_key_value_heads * head_dim`) must be **>= 96**, otherwise `export_rkllm` fails with
  `dimension ... must be greater than or equal to 96`. Size tiny test models accordingly
  (e.g. `hidden_size=256, num_attention_heads=4` → `head_dim=64`).
- Quantized builds tokenize the calibration `dataset` with the model's tokenizer, so a tiny
  test model needs a tokenizer whose vocab matches `config.vocab_size`.
