# Qwen LLM on AMD GPU — Installation Guide

Reproducible guide for deploying Qwen 2.5 14B on AMD Radeon GPUs with ROCm.
Tested on **2x RX 6700 XT (Navi 22)** with Ubuntu 26.04 LTS.

## Hardware Requirements

| Component | Minimum | Tested |
|-----------|---------|--------|
| GPU | 1x AMD RDNA 2 GPU (12 GB VRAM) | 2x RX 6700 XT (12 GB each) |
| RAM | 16 GB | 32 GB |
| Storage | 20 GB free | 114 GB SSD |
| OS | Ubuntu 24.04+ | Ubuntu 26.04 LTS |
| Network | LAN + Tailscale (optional) | 1 GbE + Tailscale mesh |

## Architecture Overview

```
┌──────────────────┐     Tailscale      ┌──────────────────────┐
│  Hermes AI Agent │ ◄────────────────► │  llama-server :8081  │
│  (consumer)      │                    │  Qwen 2.5 14B Q4_K_M │
└──────────────────┘                    │  2x RX 6700 XT (ROCm)│
                                        └──────────────────────┘
```

## Step 1: ROCm Installation

Ubuntu 26.04 ships ROCm 7.1.0 but its rocBLAS lacks gfx1031 support.
Install AMD's official ROCm for newer rocBLAS:

```bash
# Add AMD ROCm repository
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
  sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg
echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/7.2.4 noble main' | \
  sudo tee /etc/apt/sources.list.d/amdgpu.list

# Install ROCm + updated rocBLAS
sudo apt update
sudo apt install -y rocm rocblas rocblas-dev

# Add user to GPU groups
sudo usermod -aG render,video $USER

# Reboot to load kfd kernel module
sudo reboot
```

**Verify:**
```bash
rocminfo | grep -A5 "Agent [23]"
rocm-smi
lsmod | grep kfd
```

Expected: 2 GPU agents (gfx1031), rocm-smi shows both GPUs.

## Step 2: Build Dependencies

```bash
sudo apt install -y build-essential cmake git libcurl4-openssl-dev
```

## Step 3: Build llama.cpp with ROCm

```bash
# Clone
git clone https://github.com/ggerganov/llama.cpp.git /opt/llm/llama.cpp
cd /opt/llm/llama.cpp
mkdir build && cd build

# Build — CRITICAL: target gfx1030, not gfx1031
cmake .. \
    -DGGML_HIP=ON \
    -DCMAKE_HIP_ARCHITECTURES=gfx1030 \
    -DCMAKE_BUILD_TYPE=Release

make -j$(nproc) llama-server
```

**Why gfx1030?** RX 6700 XT is gfx1031, but ROCm's rocBLAS doesn't include
gfx1031 in its TensileLibrary. gfx1030 (Navi 21) kernels are binary-compatible
with gfx1031 (Navi 22). We compile for gfx1030 and override at runtime.

## Step 4: Download Model

```bash
mkdir -p /opt/llm/models /opt/llm/logs

# Qwen 2.5 14B Instruct Q4_K_M (~9 GB)
wget -O /opt/llm/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf \
    'https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf'
```

Other model options:
- **7B:** `Qwen2.5-7B-Instruct-Q4_K_M.gguf` (~4.5 GB, faster, less capable)
- **32B:** `Qwen2.5-32B-Instruct-IQ4_XS.gguf` (~18 GB, needs both GPUs)

## Step 5: systemd Service

```bash
sudo tee /etc/systemd/system/llama-server.service << 'EOF'
[Unit]
Description=llama.cpp server — Qwen 2.5 14B (ROCm)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=render
WorkingDirectory=/opt/llm
ExecStartPre=/bin/sleep 5
ExecStart=/opt/llm/llama.cpp/build/bin/llama-server \
    --model /opt/llm/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf \
    --host 0.0.0.0 \
    --port 8081 \
    --n-gpu-layers 99 \
    --tensor-split 12,12 \
    --ctx-size 8192 \
    --threads 6 \
    --batch-size 512 \
    --flash-attn off \
    --metrics
Restart=always
RestartSec=10
StandardOutput=append:/opt/llm/logs/llama-server.log
StandardError=append:/opt/llm/logs/llama-server.log

Environment=HIP_VISIBLE_DEVICES=0,1
Environment=HSA_OVERRIDE_GFX_VERSION=10.3.0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now llama-server
```

**Flag reference:**

| Flag | Value | Purpose |
|------|-------|---------|
| `--n-gpu-layers` | 99 | Offload all layers to GPU |
| `--tensor-split` | 12,12 | Split tensors evenly across GPUs |
| `--ctx-size` | 8192 | Context window size |
| `--threads` | 6 | CPU threads (half of total cores) |
| `--batch-size` | 512 | Batch size for prompt processing |
| `--flash-attn` | off | **Must be off** on RDNA 2 (crashes) |

**Environment variables:**

| Variable | Value | Purpose |
|----------|-------|---------|
| `HIP_VISIBLE_DEVICES` | 0,1 | Use both GPUs |
| `HSA_OVERRIDE_GFX_VERSION` | 10.3.0 | Report GPU as gfx1030 |

## Step 6: Verify

```bash
# Check service
sudo systemctl status llama-server

# Health endpoint
curl http://localhost:8081/health

# Chat test
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hi"}],"max_tokens":10}'

# GPU usage
watch -n1 rocm-smi
```

## Step 7: Tailscale (Optional)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname <your-hostname>
```

Hermes AI connects via Tailscale IP: `http://100.x.y.z:8081/v1/chat/completions`

## Step 8: Docker Deployment (Recommended)

The pre-built Docker image includes llama.cpp binaries + ROCm 7.2.4 libraries.
Build on the AMD server, push to ghcr.io, then deploy via Coolify or docker-compose.

### Build & Push (on AMD server)

```bash
# 1. Build llama.cpp on the server first (Steps 1-3 above)
# 2. Run the build script
cd /path/to/qwen-llm-amd-multi
./scripts/build-docker.sh

# 3. Push to GitHub Container Registry
echo $GITHUB_PAT | docker login ghcr.io -u YOUR_USERNAME --password-stdin
docker push ghcr.io/miqbalf/qwen-llm-amd:latest
```

The build script copies:
- `build-bin/` — pre-built llama-server + llama-cli
- `rocm-libs/` — ROCm 7.2.4 runtime libraries (~6 GB incl. GPU kernels)
- `rocm-syslibs/` — system ROCm libraries from /usr/lib

### Deploy via docker-compose

```yaml
# docker-compose.yml
services:
  llama-server:
    image: ghcr.io/miqbalf/qwen-llm-amd:latest
    container_name: qwen-llm-amd
    restart: unless-stopped
    network_mode: host          # needed for Tailscale
    volumes:
      - /opt/llm/models:/opt/llm/models:ro
      - /opt/llm/logs:/opt/llm/logs
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
    group_add:
      - "44"    # video
      - "991"   # render
    security_opt:
      - seccomp:unconfined
    environment:
      - HIP_VISIBLE_DEVICES=0,1
      - HSA_OVERRIDE_GFX_VERSION=10.3.0
    command: >
      --model /opt/llm/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf
      --host 0.0.0.0
      --port 8081
      --n-gpu-layers 99
      --tensor-split 12,12
      --ctx-size 8192
      --threads 6
      --batch-size 512
      --flash-attn off
      --metrics
```

```bash
docker compose pull && docker compose up -d
```

### Deploy via Coolify

Point Coolify at the repo. It pulls the pre-built image from ghcr.io.
Set the compose file path to `docker-compose.yml`.

**Important:** Port 8081 (8081 is used by Coolify's own Traefik proxy).

### GPU group IDs

Docker cannot resolve group names on all systems. Use numeric GIDs:
```bash
getent group video   # usually 44
getent group render  # usually 991
```

### rocBLAS / hipblaslt GPU Kernel Libraries

The image must include GPU kernel libraries from the build host:
- `/opt/rocm/lib/rocblas/library/` (~671 MB) — TensileLibrary kernel files
- `/opt/rocm/lib/hipblaslt/library/` (~4.5 GB) — hipBLASLt kernel files

Without these, you'll get: `rocBLAS error: Cannot read TensileLibrary.dat: Illegal seek for GPU arch : gfx1030`

## Hermes AI Integration

Set these env vars in Hermes (Coolify → Hermes → Environment):

| Variable | Value |
|---|---|
| `TIER_0_MODEL` | `local/qwen2.5-14b` |
| `LOCAL_BASE_URL` | `http://100.106.139.126:8081/v1` |
| `LOCAL_API_KEY` | `not-needed` |

The `local/` prefix routes to LocalProvider (OpenAI-compatible, 300s timeout, no auth).

## Performance

| Metric | Value |
|--------|-------|
| Generation speed | 31.5 tok/s |
| Prompt processing | ~86 ms for 36-39 tokens |
| GPU 0 VRAM | ~5.6 GB (47%) |
| GPU 1 VRAM | ~5.9 GB (49%) |
| GPU temps | 48-49°C |
| GPU power | 40-43W |

## Troubleshooting

### "Cannot read TensileLibrary.dat: No such file or directory for GPU arch : gfx1031"
Your rocBLAS lacks gfx1031 support. Install AMD's rocBLAS 5.2.0+ from the
official repo. Or build with `-DCMAKE_HIP_ARCHITECTURES=gfx1030` and set
`HSA_OVERRIDE_GFX_VERSION=10.3.0`.

### "GGML_ASSERT(max_blocks_per_sm > 0) failed"
Flash attention crash on RDNA 2. Add `--flash-attn off`.

### "CUBLAS_STATUS_INTERNAL_ERROR"
Kernel execution failure. Ensure `CMAKE_HIP_ARCHITECTURES` matches
`HSA_OVERRIDE_GFX_VERSION` (both must be gfx1030 for RX 6700 XT).

### "kfd module not loaded"
ROCm kernel driver not active. Run `sudo modprobe kfd` or reboot.

### Model loads but inference crashes
Check that `--flash-attn off` is set. Check that `HSA_OVERRIDE_GFX_VERSION=10.3.0`
is in the service environment.

### Single GPU setup
Remove `--tensor-split 12,12` and set `HIP_VISIBLE_DEVICES=0`.
The 14B Q4_K_M model fits on a single 12 GB GPU.

## References

- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [ROCm Installation](https://rocm.docs.amd.com/en/latest/)
- [Qwen 2.5 GGUF Models](https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF)
