# Qwen LLM on AMD Multi-GPU

Production local LLM deployment: **Qwen 2.5 14B** on **2x AMD Radeon RX 6700 XT** with ROCm.

```
Qwen 2.5 14B Q4_K_M  →  31.5 tok/s  →  Dual GPU  →  OpenAI-compatible API
```

## Hardware

| Component | Spec |
|-----------|------|
| GPU | 2x AMD Radeon RX 6700 XT (Navi 22, 12 GB VRAM each) |
| CPU | AMD Ryzen 4600G (12 threads) |
| RAM | 32 GB |
| OS | Ubuntu 26.04 LTS |
| Inference | llama.cpp + ROCm HIP backend |

## Quick Start

```bash
# Smoke test
python3 scripts/test-chat.py

# Benchmark
python3 scripts/benchmark.py
```

## API

OpenAI-compatible endpoint:

```bash
curl http://<server-lan-ip>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}],"max_tokens":100}'
```

## Docs

- [Installation Guide](docs/install-amd-ubuntu.md) — full setup for AMD GPUs
- [Design Spec](docs/superpowers/specs/2026-07-08-qwen-llm-amd-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-07-08-qwen-llm-amd-implementation.md)
