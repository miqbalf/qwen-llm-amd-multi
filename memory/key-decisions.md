---
name: key-decisions
description: Architecture decisions, rationale, and rejected alternatives
metadata:
  type: project
---

# Key Decisions

## 1. llama.cpp over Ollama

**Decision:** Use llama.cpp built from source with ROCm backend.
**Why:** Ollama wraps llama.cpp internally. Building directly gives full
control over multi-GPU tensor splitting, quantization selection, context
length tuning, and ROCm flags. Ollama's AMD multi-GPU handling is immature
and poorly documented.
**Rejected:** Ollama — easier setup but opaque multi-GPU behavior.
**Rejected:** vLLM — production-grade but heavy, complex ROCm setup, overkill
for single-tenant use.

## 2. GGUF Q4_K_M Quantization

**Decision:** Qwen 2.5 14B at Q4_K_M (~8.5 GB).
**Why:** Best quality/speed/size tradeoff. Fits in 12 GB VRAM per GPU with
headroom for KV cache. Q4_0 is faster but lower quality; Q5_K_M is higher
quality but pushes VRAM limits.
**How to apply:** When downloading models, always prefer Q4_K_M GGUFs from
bartowski or TheBloke on HuggingFace.

## 3. Tailscale Mesh Networking

**Decision:** Hermes AI connects to llama-server via Tailscale IP, not raw LAN.
**Why:** Stable IP that survives network changes, built-in WireGuard encryption,
works across networks. Both servers join the same Tailnet.
**How to apply:** llama-server binds to Tailscale interface. Hermes tier-0
endpoint URL uses the Tailnet IP.

## 4. systemd for Process Management

**Decision:** llama-server managed by systemd, not Docker (initially).
**Why:** Zero overhead, native auto-restart, simple logging via journald.
Docker adds complexity for the GPU passthrough path. Containerization comes
later when Coolify enters the picture.
**How to apply:** systemd unit at /etc/systemd/system/llama-server.service.

## 5. ROCm from AMD Official Repo

**Decision:** Install ROCm via AMD's official Ubuntu package repository.
**Why:** Only source with guaranteed gfx1031 support. Avoids distro packages
that may lag or lack GPU support for RDNA 2.
