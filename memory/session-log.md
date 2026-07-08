---
name: session-log
description: Chronological log of all server changes and outcomes
metadata:
  type: project
---

# Session Log

## 2026-07-08 — Initial Setup

- **SSH verified:** Key auth working to mfirdaus@192.168.1.12
- **Hardware discovered:** 2x RX 6700 XT (not 5700XT as originally thought)
- **OS:** Ubuntu 26.04 LTS, kernel 7.0.0-27
- **State:** Clean server, no ROCm, no Tailscale, no Docker
- **Repo cloned:** ~/qwen-llm-amd-multi at initial commit
- **Design spec written:** docs/superpowers/specs/2026-07-08-qwen-llm-amd-design.md
- **Plan written:** docs/superpowers/plans/2026-07-08-qwen-llm-amd-implementation.md
- **AGENTS.md created:** Project context and conventions
- **Memory initialized:** server-hardware, key-decisions, session-log

## 2026-07-09 — Server Provisioning & Deployment

### Infrastructure
- **Root SSH:** Key auth configured for root@192.168.1.12
- **ROCm installed:** v7.1.0 from Ubuntu 26.04 native repos. Later upgraded to AMD ROCm 7.2.4 (rocBLAS 5.2.0) from AMD official repo
- **Tailscale:** Node `udinpc-amd-llm` at `100.106.139.126` joined to Tailnet
- **Coolify exit node:** web-docker at `100.111.240.47` (hetzner)

### llama.cpp Build
- Source: `ggerganov/llama.cpp` at `/opt/llm/llama.cpp`
- Build type: HIP (ROCm) backend with `GGML_HIP=ON`
- **Critical fix:** `-DCMAKE_HIP_ARCHITECTURES=gfx1030` (not gfx1031)
- AMD ROCm 7.2.4 installed for newer rocBLAS 5.2.0

### GPU Compatibility (Key Finding)
- gfx1031 (RX 6700 XT) is NOT in ROCm's rocBLAS TensileLibrary
- **Solution:** Build targeting `gfx1030` + runtime `HSA_OVERRIDE_GFX_VERSION=10.3.0`
- gfx1030 kernels work on gfx1031 hardware (both RDNA 2)
- `--flash-attn` crashes on gfx1030/gfx1031 — must use `off`
- Created gfx1031 TensileLibrary files from gfx1030 copies (88 files)

### Model
- Qwen 2.5 14B Instruct Q4_K_M GGUF (~9 GB) from bartowski on HuggingFace
- Downloaded via wget directly, stored at `/opt/llm/models/`

### systemd Service
- Unit: `/etc/systemd/system/llama-server.service`
- Dual GPU: `--tensor-split 12,12`, `HIP_VISIBLE_DEVICES=0,1`
- Context: 8192, threads: 6, batch: 512
- Binding: `0.0.0.0:8080` (accessible via LAN and Tailscale)

### Benchmark Results
- **Speed:** 31.5 tok/s (stable, 5/5 prompts passed)
- **GPU 0:** 47% VRAM, 48°C, 43W
- **GPU 1:** 49% VRAM, 49°C, 40W
- **Prompt processing:** ~86ms for 36-39 tokens
- **Model loaded:** memory peak 427 MB RAM, ~9 GB VRAM split across GPUs
