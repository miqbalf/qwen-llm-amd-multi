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
**Why:** Ubuntu 26.04 ships ROCm 7.1.0 but rocBLAS lacks gfx1031 TensileLibrary.
AMD's ROCm 7.2.4 (rocBLAS 5.2.0) was installed for newer libraries.
**How to apply:** AMD repo at `https://repo.radeon.com/rocm/apt/7.2.4 noble main`.

## 6. GPU Architecture Targeting: gfx1030 for gfx1031

**Decision:** Build llama.cpp with `-DCMAKE_HIP_ARCHITECTURES=gfx1030` and
runtime `HSA_OVERRIDE_GFX_VERSION=10.3.0`.
**Why:** gfx1031 (Navi 22 / RX 6700 XT) is not in ROCm's rocBLAS TensileLibrary.
gfx1030 (Navi 21) kernels are binary-compatible with gfx1031 (both RDNA 2).
The override tells ROCm to report the GPU as gfx1030, matching the compiled kernels.
**Rejected:** Vulkan backend — would work but adds complexity.
**Rejected:** gfx1030→gfx1031 file copies — rocBLAS loaded kernels but CUBLAS_STATUS_INTERNAL_ERROR.
**How to apply:** Always build with `-DCMAKE_HIP_ARCHITECTURES=gfx1030` for RX 6700 XT.

## 7. Flash Attention Disabled

**Decision:** Use `--flash-attn off` (explicitly disabled).
**Why:** Flash attention HIP kernels crash on gfx1030/gfx1031 with
`GGML_ASSERT(max_blocks_per_sm > 0) failed`. This is a known compatibility
issue with RDNA 2 GPUs. Standard attention works correctly at acceptable speed.
