# Qwen LLM on AMD Multi-GPU — Design Spec

**Date:** 2026-07-08
**Status:** approved

## Overview

Production-ready local Qwen 14B LLM on a dedicated AMD GPU server, accessed
by the Hermes AI agent via Tailscale mesh. Uses llama.cpp with ROCm backend
across 2x RX 6700 XT GPUs, exposed as an OpenAI-compatible HTTP API.

## Hardware

| Component | Spec |
|-----------|------|
| CPU       | AMD Ryzen 4600G (Renoir, 12 threads) |
| GPU       | 2x AMD Radeon RX 6700/6700 XT (Navi 22, gfx1031, ~12GB VRAM each) |
| RAM       | 30 GiB available |
| OS        | Ubuntu 26.04 LTS (Resolute Raccoon), kernel 7.0 |
| Network   | LAN 192.168.1.12, Tailscale mesh |

## Architecture

```
Hermes AI Server                  AMD GPU Server (192.168.1.12)
┌──────────────────┐              ┌─────────────────────────────┐
│ Tier 0: Qwen 14B │──Tailscale──▶│ Container: llama-server      │
│ Tier 1-3: Cloud  │  :8080       │ ROCm backend, HIPBLAS        │
│                  │              │ Model: Qwen 2.5 14B Q4_K_M  │
│                  │              │ 2x RX 6700 XT (tensor split) │
└──────────────────┘              └─────────────────────────────┘
```

- **Inference:** llama.cpp built from source with `GGML_HIPBLAS=ON`
- **Model:** Qwen 2.5 14B Instruct, GGUF Q4_K_M quant (~8.5 GB)
- **GPU split:** `--tensor-split 12,12` dividing layers across both GPUs
- **API:** llama-server provides `/v1/chat/completions` (OpenAI-compatible)
- **Network:** Tailscale mesh; Hermes connects via Tailnet IP, not raw LAN IP
- **Container:** Docker with ROCm host device passthrough, deployed via Coolify

## Key Decisions

1. **llama.cpp over Ollama:** Ollama wraps llama.cpp internally. Building directly
   gives full control over multi-GPU splitting, quantization, and context tuning.
   Ollama's multi-GPU story on AMD is immature.

2. **GGUF over raw PyTorch:** GGUF is the standard for local inference. No Python
   environment needed — the `llama-server` binary is self-contained.

3. **Q4_K_M quantization:** Best quality/speed/size tradeoff. 14B at Q4_K_M uses
   ~8.5 GB, fitting comfortably in 12 GB VRAM with room for KV cache.

4. **Tailscale, not raw LAN:** Tailscale provides a stable IP that survives network
   changes, plus WireGuard encryption between Hermes and the GPU box. Coolify can
   target containers on Tailnet IPs.

5. **ROCm 6.x:** Latest stable ROCm release with full gfx1031 support. Installed
   via AMD's official Ubuntu repository.

## Implementation Phases

### Phase 1: Project Foundation
- Write `AGENTS.md` with project context, conventions, and key decisions
- Create `/memory/` directory for persistent project tracking
- Create `docs/` for the installation guide

### Phase 2: Server Provisioning
- SSH key auth for both `mfirdaus` and `root`
- Install ROCm 6.x drivers
- Install Tailscale, join to Tailnet
- Verification: `rocminfo` shows 2 GPUs, `tailscale status` shows node

### Phase 3: llama.cpp Build & Model Download
- Clone and build llama.cpp with `GGML_HIPBLAS=ON`
- Download Qwen 2.5 14B Instruct GGUF (Q4_K_M)
- Configure systemd service for `llama-server`
- Multi-GPU tensor split across both GPUs

### Phase 4: Test & Benchmark
- Temporary chat completion test script
- Verify `/v1/chat/completions` endpoint
- Benchmark: tokens/sec generation, time-to-first-token
- Document results

### Phase 5: Containerization
- Dockerfile with ROCm base, llama-server binary, and model
- docker-compose.yml for local testing on the AMD box
- Tailscale networking mode

### Phase 6: Documentation
- `docs/install-amd-ubuntu.md` — every step, command, and rationale
- Portable: written so someone with similar AMD hardware can follow along

## Testing Strategy

1. **Smoke test:** POST to `/v1/chat/completions` with a simple prompt, verify 200
2. **Correctness:** Multi-turn conversation, verify coherent responses
3. **Performance:** Measure tokens/sec with a fixed prompt, confirm acceptable speed
4. **Multi-GPU:** Verify both GPUs show utilization during inference via `rocm-smi`

## Future: Coolify Deployment

Once local deployment is verified:
1. Add the AMD server as a Docker host in Coolify (reachable via Tailscale)
2. Deploy the containerized llama-server as a Coolify service
3. Hermes points its tier-0 endpoint to the Coolify service URL
