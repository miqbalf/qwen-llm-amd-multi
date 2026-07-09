# AGENTS.md — Qwen LLM AMD Multi-GPU

## What This Is

Production local LLM deployment for Qwen 2.5 14B on a dedicated AMD GPU
server. The server houses 2x RX 6700 XT GPUs (Navi 22, gfx1031, 12 GB VRAM
each) running ROCm + llama.cpp. Inference is served as an OpenAI-compatible
HTTP API consumed by the Hermes AI agent over Tailscale.

## Architecture

```
Hermes AI (other server) ──Tailscale──▶ llama-server :8080 (this server)
                                           │
                                           ├─ GPU 0: RX 6700 XT (12 GB)
                                           └─ GPU 1: RX 6700 XT (12 GB)
                                           Model: Qwen 2.5 14B Q4_K_M (~8.5 GB)
```

## Server

- **Host:** <server-lan-ip> (LAN), Tailscale node for stable addressing
- **OS:** Ubuntu 26.04 LTS (Resolute Raccoon), kernel 7.0.0-27
- **User:** mfirdaus (SSH key auth), sudo-capable
- **GPU driver:** amdgpu (kernel), ROCm 6.x (userspace)
- **Inference path:** `/opt/llm/`

## Key Decisions

See `memory/key-decisions.md` for rationale on each.

1. **llama.cpp over Ollama** — direct control over multi-GPU split and ROCm flags
2. **GGUF over PyTorch** — self-contained binary, no Python dependency hell
3. **Q4_K_M quantization** — best speed/quality tradeoff for 14B on 12 GB cards
4. **Tailscale mesh, not raw LAN** — stable IP, WireGuard encryption
5. **systemd for process management** — native, zero-dependency auto-restart

## Working With This Project

### Before Any Change
1. Read `memory/MEMORY.md` for current state
2. Check `memory/session-log.md` for recent activity
3. SSH to server to verify current state matches memory

### Making Server Changes
1. SSH: `ssh mfirdaus@<server-lan-ip>` (key auth, no password)
2. Root: `sudo -i` (password required — key auth configured in Task 4)
3. GPU status: `rocm-smi` or `watch -n1 rocm-smi`
4. Service: `sudo systemctl status llama-server`

### Testing
- Smoke: `python3 scripts/test-chat.py`
- Benchmark: `python3 scripts/benchmark.py`
- Raw: `curl -X POST http://<tailscale-ip>:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"hi"}]}'`

### No Secrets Rule
Tailscale auth keys, API tokens, passwords — never commit to this repo.
Use `.env` files on the server directly.

## Docs

- `docs/install-amd-ubuntu.md` — full setup guide for similar hardware
- `docs/superpowers/specs/` — design specs
- `docs/superpowers/plans/` — implementation plans
