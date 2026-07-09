# Qwen LLM on AMD Multi-GPU — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Qwen 2.5 14B (Q4_K_M) on Ubuntu 26.04 with 2x RX 6700 XT via llama.cpp + ROCm, accessible as an OpenAI-compatible API over Tailscale.

**Architecture:** llama.cpp built from source with GGML_HIPBLAS=ON for ROCm. llama-server binary serves `/v1/chat/completions`. Model split across both GPUs. Systemd manages the service. Tailscale provides stable addressing for Hermes AI.

**Tech Stack:** ROCm 6.x, llama.cpp (HIPBLAS), GGUF Q4_K_M, systemd, Tailscale, Docker (later)

## Server State (pre-flight)

| Item | Status |
|------|--------|
| OS | Ubuntu 26.04 LTS, kernel 7.0.0-27 |
| amdgpu driver | Loaded, both GPUs at /dev/dri/renderD128 & renderD129 |
| ROCm | Not installed |
| Tailscale | Not installed |
| Docker | Not installed |
| SSH key auth | Already working for mfirdaus |
| sudo | Requires password |
| Disk | 97 GB free on / |
| Render group | mfirdaus already in `video`, `render` groups |
| Git repo | Cloned at ~/qwen-llm-amd-multi (bare initial commit) |

## Global Constraints

- ROCm must be installed from AMD's official Ubuntu repository
- llama.cpp must be built from source with `GGML_HIPBLAS=ON`
- Model: Qwen 2.5 14B Instruct GGUF, Q4_K_M quantization
- GPU split: `--tensor-split 12,12` (12GB each GPU)
- llama-server on port 8080, bound to Tailscale IP only
- systemd unit for auto-start and crash recovery
- No secrets committed — Tailscale auth keys, SSH keys stay out of git

---

## File Map

### Local repo (this machine → pushed to GitHub → pulled on server)
```
qwen-llm-amd-multi/
├── AGENTS.md                          # Project instructions for Claude
├── memory/                            # Persistent project memory
│   ├── MEMORY.md                      # Index of all memories
│   ├── server-hardware.md             # Server specs and discovered hardware
│   ├── key-decisions.md               # Architecture decisions and rationale
│   └── session-log.md                 # Running log of changes and outcomes
├── docs/
│   └── install-amd-ubuntu.md          # Reproducible installation guide
├── scripts/
│   ├── test-chat.py                   # Smoke test: sends a prompt, prints response
│   └── benchmark.py                   # Benchmark: measures tokens/sec
├── docker/
│   ├── Dockerfile                     # Container build for Coolify later
│   └── docker-compose.yml            # Local test compose
├── config/
│   ├── llama-server.service           # systemd unit template
│   └── .env.example                   # Environment template (no secrets)
├── .gitignore                         # Already exists, add entries
└── README.md                          # Already exists, update with project info
```

### Server-side (on <server-lan-ip>, not in git)
```
/opt/llm/
├── models/                            # GGUF model files
│   └── qwen2.5-14b-instruct-q4_k_m.gguf
├── llama.cpp/                         # Built from source
│   ├── build/
│   │   └── bin/
│   │       └── llama-server           # The compiled binary
│   └── ...                            # source code
└── logs/
    └── llama-server.log

/etc/systemd/system/
└── llama-server.service               # Auto-start service

/etc/tailscale/                        # Tailscale state (managed by tailscaled)
```

---

### Task 1: AGENTS.md — Project Context File

**Files:**
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: Design spec at `docs/superpowers/specs/2026-07-08-qwen-llm-amd-design.md`
- Produces: Project context that Claude reads on every interaction

- [ ] **Step 1: Write AGENTS.md**

```markdown
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
- **OS:** Ubuntu 26.04 LTS (Resolute Raccoon), kernel 7.0
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
2. Root: `sudo -i` (requires password — set up key auth per task 2)
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
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add AGENTS.md with project context and conventions

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Memory Directory — Persistent Project Tracking

**Files:**
- Create: `memory/MEMORY.md`
- Create: `memory/server-hardware.md`
- Create: `memory/key-decisions.md`
- Create: `memory/session-log.md`

**Interfaces:**
- Consumes: AGENTS.md (references memory files), design spec
- Produces: Memory index and fact files for Claude to read on each session

- [ ] **Step 1: Create memory/MEMORY.md (index)**

```markdown
# Project Memory Index

- [Server Hardware](server-hardware.md) — specs, discovered hardware, PCI topology
- [Key Decisions](key-decisions.md) — architecture choices and rationale
- [Session Log](session-log.md) — chronological log of changes and outcomes
```

- [ ] **Step 2: Create memory/server-hardware.md**

```markdown
---
name: server-hardware
description: Physical server specs, GPU topology, and discovered hardware details
metadata:
  type: project
---

# Server Hardware

## Specs

| Component | Detail |
|-----------|--------|
| CPU | AMD Ryzen 4600G (Renoir, 12 threads, with integrated GPU) |
| GPU 0 | AMD Radeon RX 6700/6700 XT (Navi 22, gfx1031, ~12 GB VRAM) |
| GPU 1 | AMD Radeon RX 6700/6700 XT (Navi 22, gfx1031, ~12 GB VRAM) |
| RAM | 30 GiB available (32 GiB installed, ~2 GiB reserved for iGPU) |
| Storage | 114 GB SSD, 97 GB free on / |
| OS | Ubuntu 26.04 LTS (Resolute Raccoon) |
| Kernel | 7.0.0-27-generic |
| Network | LAN <server-lan-ip>, 1 GbE |

## PCI Topology

- GPU 0: PCI 12:00.0 (Navi 22, rev c5) — connected via Navi 10 XL PCIe switch
- GPU 1: PCI 23:00.0 (Navi 22, rev c1) — connected via Navi 10 XL PCIe switch
- Both GPUs have associated HDMI/DP Audio controllers

## Discovery Date

2026-07-08 — Originally thought to be 2x RX 5700XT. SSH inspection revealed
2x RX 6700/6700 XT (Navi 22, RDNA 2). This is better: gfx1031 has full ROCm
support, whereas gfx1010 (5700XT) was never officially supported.

## GPU Driver

- amdgpu kernel driver loaded (21 GB module)
- Both cards at /dev/dri/card0, /dev/dri/card1
- Render nodes at /dev/dri/renderD128, /dev/dri/renderD129
- mfirdaus is in `video` and `render` groups
```

- [ ] **Step 3: Create memory/key-decisions.md**

```markdown
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

## 5. ROCm 6.x from AMD Official Repo

**Decision:** Install ROCm via AMD's official Ubuntu package repository.
**Why:** Only source with guaranteed gfx1031 support. Avoids distro packages
that may lag or lack GPU support for RDNA 2.
```

- [ ] **Step 4: Create memory/session-log.md**

```markdown
---
name: session-log
description: Chronological log of all server changes and outcomes
metadata:
  type: project
---

# Session Log

## 2026-07-08 — Initial Setup

- **SSH verified:** Key auth working to mfirdaus@<server-lan-ip>
- **Hardware discovered:** 2x RX 6700 XT (not 5700XT as originally thought)
- **OS:** Ubuntu 26.04 LTS, kernel 7.0.0-27
- **State:** Clean server, no ROCm, no Tailscale, no Docker
- **Repo cloned:** ~/qwen-llm-amd-multi at initial commit
- **Design spec written:** docs/superpowers/specs/2026-07-08-qwen-llm-amd-design.md
- **Plan written:** docs/superpowers/plans/2026-07-08-qwen-llm-amd-implementation.md
```

- [ ] **Step 5: Commit**

```bash
git add memory/
git commit -m "docs: add memory directory with project tracking files

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Server — Git Config & Repo Sync

**Files:**
- Modify: Server git config (via SSH commands)

**Interfaces:**
- Consumes: Tasks 1-2 produce AGENTS.md and memory files
- Produces: Server has latest repo, can push/pull from GitHub

- [ ] **Step 1: Set git identity on server**

SSH to server and run:
```bash
ssh mfirdaus@<server-lan-ip>
git config --global user.name "M Iqbal Firdaus"
git config --global user.email "mfirdaus@example.com"
git config --global init.defaultBranch main
```

- [ ] **Step 2: Pull latest from GitHub to server**

After pushing tasks 1-2 locally:
```bash
# Local — push changes to GitHub
git push origin main

# Server — pull changes
ssh mfirdaus@<server-lan-ip> "cd ~/qwen-llm-amd-multi && git pull origin main"
```

Expected: Server repo shows AGENTS.md and memory/ directory.

- [ ] **Step 3: Commit note in session log**

No commit needed — server git config is outside repo scope. Log this in next session-log update.

---

### Task 4: Server — SSH Root Key Auth

**Files:**
- Modify: `/root/.ssh/authorized_keys` (on server)
- Modify: `memory/session-log.md`

**Interfaces:**
- Consumes: mfirdaus has SSH key at `~/.ssh/id_ed25519.pub`
- Produces: `ssh root@<server-lan-ip>` works without password

- [ ] **Step 1: Copy SSH key to root authorized_keys**

```bash
ssh mfirdaus@<server-lan-ip> "cat ~/.ssh/id_ed25519.pub | sudo tee -a /root/.ssh/authorized_keys && sudo chmod 600 /root/.ssh/authorized_keys && sudo chmod 700 /root/.ssh"
```

Expected: No errors. Key appended to root's authorized_keys.

- [ ] **Step 2: Test root SSH**

```bash
ssh -o ConnectTimeout=5 root@<server-lan-ip> "echo 'Root SSH key auth: SUCCESS' && hostname"
```

Expected: "Root SSH key auth: SUCCESS" and "udinpc".

- [ ] **Step 3: Update session log**

Add entry to `memory/session-log.md`:
```markdown
- **Root SSH:** Key auth configured for root@<server-lan-ip>. Verified working.
```

- [ ] **Step 4: Commit**

```bash
git add memory/session-log.md
git commit -m "log: root SSH key auth configured and verified

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Server — ROCm Installation

**Files:**
- Modify: Server packages (via SSH)
- Modify: `memory/session-log.md`

**Interfaces:**
- Consumes: Root SSH working, amdgpu driver loaded
- Produces: `rocminfo` shows 2 GPUs, `rocm-smi` shows GPU stats

- [ ] **Step 1: Check ROCm availability for Ubuntu 26.04**

AMD's ROCm repo may not yet have a named Ubuntu 26.04 release. We check and adapt:

```bash
ssh root@<server-lan-ip> "apt update && apt-cache search rocm 2>/dev/null | head -20 || echo 'No ROCm in default repos'"
```

If not in default repos, check AMD's official repo structure:
```bash
ssh root@<server-lan-ip> "curl -s https://repo.radeon.com/rocm/apt/ | grep -o 'href=\"[0-9].*/\"' | sort -V | tail -5"
```

- [ ] **Step 2: Install via AMD official repo**

Use the Ubuntu 24.04 repo as fallback if 26.04 isn't listed yet (26.04 just released):

```bash
ssh root@<server-lan-ip> << 'ROCM_SETUP'
# Add AMD ROCm repository
apt update && apt install -y wget gnupg

# Signing key
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg

# Determine correct distro codename — try noble (24.04) if resolute (26.04) not available
CODENAME=$(lsb_release -cs)
echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.3.2 $CODENAME main" > /etc/apt/sources.list.d/rocm.list

# If 26.04 repo fails, fall back to noble
if ! apt update 2>&1 | grep -q "rocm"; then
    echo "Falling back to noble (24.04) ROCm repo for Ubuntu 26.04 compatibility"
    echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.3.2 noble main" > /etc/apt/sources.list.d/rocm.list
    apt update
fi

# Install ROCm stack
apt install -y rocm-hip-libraries rocm-hip-runtime rocm-core rocm-smi-lib rocm-device-libs

# Add mfirdaus to render and video groups (should already be)
usermod -a -G render,video mfirdaus

echo "ROCm installation complete"
ROCM_SETUP
```

**Note:** The exact ROCm version (6.3.2 above) should be checked against what's actually available. If the repo has 6.4.x, use that.

- [ ] **Step 3: Verify ROCm installation**

```bash
ssh root@<server-lan-ip> "rocminfo 2>&1 | head -40 && echo '---' && rocm-smi 2>&1"
```

Expected output: `rocminfo` lists 2 agents (GPUs) with gfx1031. `rocm-smi` shows both GPUs with VRAM, temperature, and power.

Look for lines like:
```
Agent 1 — Name: gfx1031
Agent 2 — Name: gfx1031
```

- [ ] **Step 4: Verify HIP runtime**

```bash
ssh mfirdaus@<server-lan-ip> "hipconfig --full 2>&1 || echo 'hipconfig not found — trying /opt/rocm/bin/hipconfig' && /opt/rocm/bin/hipconfig --full 2>&1"
```

Expected: HIP version, ROCm path, GPU targets including gfx1031.

- [ ] **Step 5: Reboot to load ROCm kernel modules**

```bash
ssh root@<server-lan-ip> "reboot"
```

Wait 30 seconds, then verify:
```bash
sleep 30 && ssh mfirdaus@<server-lan-ip> "lsmod | grep kfd && rocm-smi"
```

Expected: `amdgpu` and `kfd` modules loaded. `rocm-smi` shows both GPUs.

- [ ] **Step 6: Update session log**

Add to `memory/session-log.md`:
```markdown
- **ROCm installed:** Version [X.Y.Z] from AMD official repo (Ubuntu 24.04/noble fallback for 26.04)
- **Verification:** rocminfo shows 2x gfx1031 agents, rocm-smi shows both GPUs
- **Kernel modules:** amdgpu + kfd loaded after reboot
```

- [ ] **Step 7: Commit**

```bash
git add memory/session-log.md
git commit -m "log: ROCm installed and verified on 2x RX 6700 XT

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Server — Tailscale Installation

**Files:**
- Modify: Server packages (via SSH)
- Modify: `memory/session-log.md`

**Interfaces:**
- Consumes: Server networking functional
- Produces: Tailscale node online, stable Tailnet IP

- [ ] **Step 1: Install Tailscale**

```bash
ssh root@<server-lan-ip> "curl -fsSL https://tailscale.com/install.sh | sh"
```

Expected: Tailscale installed, tailscaled service running.

- [ ] **Step 2: Authenticate to Tailnet**

```bash
ssh root@<server-lan-ip> "tailscale up"
```

Expected: Prints a URL. You (mfirdaus) need to open it in a browser to authenticate.
**Note:** For headless servers, use an auth key from Tailscale admin console:
```bash
# Alternative: pre-auth key (no browser needed)
ssh root@<server-lan-ip> "tailscale up --authkey tskey-... --hostname udinpc-amd-llm"
```
The auth key should be generated at https://login.tailscale.com/admin/settings/keys.
**Do not commit the auth key to git.**

- [ ] **Step 3: Verify Tailscale**

```bash
ssh mfirdaus@<server-lan-ip> "tailscale status && echo '---' && tailscale ip -4"
```

Expected: Shows the node with its Tailnet IP (100.x.y.z). Note this IP.

- [ ] **Step 4: Update session log**

Add to `memory/session-log.md`:
```markdown
- **Tailscale installed:** Node `udinpc-amd-llm` joined Tailnet
- **Tailnet IP:** `100.x.y.z` (recorded in server, not committed to git — this is a private IP)
```

- [ ] **Step 5: Commit**

```bash
git add memory/session-log.md
git commit -m "log: Tailscale installed and joined to Tailnet

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Server — llama.cpp Build with ROCm

**Files:**
- Create: `/opt/llm/` directory structure
- Create: `/opt/llm/llama.cpp/` (git clone + build)

**Interfaces:**
- Consumes: ROCm installed (Task 5), build tools
- Produces: `/opt/llm/llama.cpp/build/bin/llama-server` binary

- [ ] **Step 1: Install build dependencies**

```bash
ssh root@<server-lan-ip> "apt install -y build-essential cmake git libgomp1 libcurl4-openssl-dev"
```

- [ ] **Step 2: Create directory structure**

```bash
ssh mfirdaus@<server-lan-ip> "mkdir -p /opt/llm/models /opt/llm/logs"
```

- [ ] **Step 3: Clone llama.cpp**

```bash
ssh mfirdaus@<server-lan-ip> "git clone https://github.com/ggerganov/llama.cpp.git /opt/llm/llama.cpp"
```

- [ ] **Step 4: Build with HIPBLAS**

```bash
ssh mfirdaus@<server-lan-ip> << 'BUILD'
cd /opt/llm/llama.cpp
mkdir -p build && cd build

# HIPBLAS build for ROCm
cmake .. \
    -DGGML_HIPBLAS=ON \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DAMDGPU_TARGETS=gfx1031 \
    -DGPU_TARGETS=gfx1031 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CCACHE=OFF

# Build with all cores (12 threads)
make -j12 llama-server

echo "Build complete"
ls -lh bin/llama-server
BUILD
```

Expected: `bin/llama-server` binary exists, ~20-50 MB.

**Note:** If cmake fails with ROCm not found, explicitly set the ROCm path:
```bash
cmake .. \
    -DGGML_HIPBLAS=ON \
    -DAMDGPU_TARGETS=gfx1031 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/opt/rocm/bin/hipcc \
    -DCMAKE_CXX_COMPILER=/opt/rocm/bin/hipcc
```

- [ ] **Step 5: Verify the binary**

```bash
ssh mfirdaus@<server-lan-ip> "/opt/llm/llama.cpp/build/bin/llama-server --help 2>&1 | head -20"
```

Expected: Help text listing flags including `--tensor-split`, `--n-gpu-layers`, etc.

- [ ] **Step 6: Update session log**

Add to `memory/session-log.md`:
```markdown
- **llama.cpp built:** HIPBLAS backend, gfx1031 target, Release mode
- **Binary:** `/opt/llm/llama.cpp/build/bin/llama-server` ([size] MB)
```

- [ ] **Step 7: Commit**

```bash
git add memory/session-log.md
git commit -m "log: llama.cpp built with ROCm HIPBLAS for gfx1031

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Server — Qwen 2.5 14B Model Download

**Files:**
- Create: `/opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf`

**Interfaces:**
- Consumes: llama.cpp built (Task 7), disk space
- Produces: GGUF model file, ~8.5 GB

- [ ] **Step 1: Download the model**

Use huggingface-cli or direct download from HuggingFace. The standard source for quality GGUFs is bartowski on HuggingFace:

```bash
ssh mfirdaus@<server-lan-ip> << 'DOWNLOAD'
cd /opt/llm/models

# Install huggingface-hub CLI
pip3 install --break-system-packages huggingface-hub 2>/dev/null || \
  pip3 install huggingface-hub

# Download Qwen 2.5 14B Instruct Q4_K_M GGUF
# Repository: bartowski/Qwen2.5-14B-Instruct-GGUF
huggingface-cli download bartowski/Qwen2.5-14B-Instruct-GGUF \
    Qwen2.5-14B-Instruct-Q4_K_M.gguf \
    --local-dir /opt/llm/models \
    --local-dir-use-symlinks False

echo "Download complete"
ls -lh /opt/llm/models/
DOWNLOAD
```

Expected: File `qwen2.5-14b-instruct-q4_k_m.gguf` (or similar name) ~8.5 GB.

**Alternative if huggingface-cli is problematic:**
```bash
# Direct URL download (check HuggingFace for latest URL)
wget -O /opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf \
    "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf"
```

- [ ] **Step 2: Verify the model file**

```bash
ssh mfirdaus@<server-lan-ip> "ls -lh /opt/llm/models/ && file /opt/llm/models/*.gguf"
```

Expected: GGUF file, ~8.5 GB.

- [ ] **Step 3: Update session log**

Add to `memory/session-log.md`:
```markdown
- **Model downloaded:** Qwen 2.5 14B Instruct Q4_K_M GGUF, [size] GB
- **Source:** bartowski/Qwen2.5-14B-Instruct-GGUF on HuggingFace
- **Path:** `/opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf`
```

- [ ] **Step 4: Commit**

```bash
git add memory/session-log.md
git commit -m "log: Qwen 2.5 14B Q4_K_M model downloaded

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Server — systemd Service for llama-server

**Files:**
- Create: `/etc/systemd/system/llama-server.service`
- Create: `config/llama-server.service` (repo copy for reference)

**Interfaces:**
- Consumes: llama-server binary (Task 7), model file (Task 8)
- Produces: Auto-starting llama-server on port 8080

- [ ] **Step 1: Determine Tailscale IP**

```bash
ssh mfirdaus@<server-lan-ip> "tailscale ip -4"
```

Note the Tailscale IP (e.g., `<your-tailscale-ip>`). We'll use this in the service file.

- [ ] **Step 2: Create systemd service file**

Write on server:
```bash
ssh root@<server-lan-ip> "cat > /etc/systemd/system/llama-server.service << 'EOF'
[Unit]
Description=llama.cpp server — Qwen 2.5 14B (ROCm)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=mfirdaus
Group=render
WorkingDirectory=/opt/llm
ExecStartPre=/bin/sleep 5
ExecStart=/opt/llm/llama.cpp/build/bin/llama-server \
    --model /opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --n-gpu-layers 99 \
    --tensor-split 12,12 \
    --ctx-size 8192 \
    --threads 6 \
    --batch-size 512 \
    --flash-attn \
    --log-disable \
    --metrics
Restart=always
RestartSec=10
StandardOutput=append:/opt/llm/logs/llama-server.log
StandardError=append:/opt/llm/logs/llama-server.log

# ROCm environment
Environment=HIP_VISIBLE_DEVICES=0,1
Environment=HSA_OVERRIDE_GFX_VERSION=10.3.1

[Install]
WantedBy=multi-user.target
EOF"
```

**Flag explanation:**
- `--n-gpu-layers 99` — offload all layers to GPU (99 > total layers, so all offloaded)
- `--tensor-split 12,12` — split tensors evenly across both GPUs (12 GB each)
- `--ctx-size 8192` — 8K context window
- `--threads 6` — half of 12 CPU threads, leave rest for I/O
- `--flash-attn` — faster attention computation
- `--batch-size 512` — reasonable batch for 14B
- `HSA_OVERRIDE_GFX_VERSION=10.3.1` — ensures ROCm treats gfx1031 correctly

- [ ] **Step 3: Save a repo copy for reference**

```bash
# Read from server and save locally
ssh root@<server-lan-ip> "cat /etc/systemd/system/llama-server.service" > /Volumes/DATA_SSD/Github/qwen-llm-amd-multi/config/llama-server.service
```

- [ ] **Step 4: Enable and start the service**

```bash
ssh root@<server-lan-ip> "systemctl daemon-reload && systemctl enable llama-server && systemctl start llama-server"
```

- [ ] **Step 5: Check service status**

```bash
ssh mfirdaus@<server-lan-ip> "systemctl status llama-server --no-pager -l && echo '---' && tail -30 /opt/llm/logs/llama-server.log"
```

Expected: Service active (running). Logs show model loaded, server listening.

Look for log lines like:
```
llama_model_load: loaded meta data with N key-value pairs
llama_model_load: using ROCm backend
llm_load_tensors: offloading N layers to GPU
llama_server: listening on http://0.0.0.0:8080
```

- [ ] **Step 6: Test the endpoint**

```bash
ssh mfirdaus@<server-lan-ip> "curl -s http://localhost:8080/health"
```

Expected: `{"status": "ok"}` or similar health response.

- [ ] **Step 7: Update session log**

Add to `memory/session-log.md`:
```markdown
- **systemd service:** llama-server.service created, enabled, and started
- **Binding:** Port 8080, all interfaces
- **GPU config:** n-gpu-layers=99, tensor-split=12,12, flash-attn on
- **Status:** Active and healthy
```

- [ ] **Step 8: Commit**

```bash
git add config/llama-server.service memory/session-log.md
git commit -m "feat: systemd service for llama-server, active on port 8080

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Test Scripts — Smoke Test & Benchmark

**Files:**
- Create: `scripts/test-chat.py`
- Create: `scripts/benchmark.py`
- Modify: `memory/session-log.md`

**Interfaces:**
- Consumes: llama-server running on :8080 (Task 9)
- Produces: Verified chat completion, measured tokens/sec

- [ ] **Step 1: Write smoke test script**

```python
#!/usr/bin/env python3
"""Smoke test for llama-server — sends a single chat completion request."""

import json
import sys
import time
from urllib import request, error

# Point to server — use Tailscale IP or LAN IP
SERVER = "<server-lan-ip>"
PORT = 8080
URL = f"http://{SERVER}:{PORT}/v1/chat/completions"

PAYLOAD = {
    "messages": [
        {"role": "system", "content": "You are a helpful AI assistant. Answer concisely."},
        {"role": "user", "content": "What is the capital of Indonesia? Reply in one sentence."}
    ],
    "max_tokens": 100,
    "temperature": 0.7,
    "stream": False,
}


def test_chat():
    print(f"Testing {URL}")
    req = request.Request(
        URL,
        data=json.dumps(PAYLOAD).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    try:
        with request.urlopen(req, timeout=120) as resp:
            body = json.loads(resp.read())
            elapsed = time.time() - t0
            choice = body["choices"][0]
            content = choice["message"]["content"]
            tokens = body.get("usage", {})
            print(f"✓ Response ({elapsed:.1f}s):")
            print(f"  {content.strip()}")
            print(f"  Tokens: prompt={tokens.get('prompt_tokens')}, "
                  f"completion={tokens.get('completion_tokens')}, "
                  f"total={tokens.get('total_tokens')}")
            return True
    except error.HTTPError as e:
        print(f"✗ HTTP {e.code}: {e.read().decode()[:500]}")
        return False
    except error.URLError as e:
        print(f"✗ Connection failed: {e.reason}")
        return False


if __name__ == "__main__":
    ok = test_chat()
    sys.exit(0 if ok else 1)
```

- [ ] **Step 2: Run smoke test**

```bash
python3 /Volumes/DATA_SSD/Github/qwen-llm-amd-multi/scripts/test-chat.py
```

Expected: Prints the AI response with token counts. Exit code 0.

- [ ] **Step 3: Write benchmark script**

```python
#!/usr/bin/env python3
"""Benchmark llama-server — measures tokens/sec generation speed."""

import json
import sys
import time
from urllib import request, error

SERVER = "<server-lan-ip>"
PORT = 8080
URL = f"http://{SERVER}:{PORT}/v1/chat/completions"

BENCH_PROMPTS = [
    "Explain what a GPU is in one paragraph.",
    "Write a short poem about artificial intelligence.",
    "List five benefits of renewable energy with one sentence each.",
    "What is the difference between RAM and VRAM? Explain simply.",
    "Write a Python function that calculates fibonacci numbers recursively.",
]

TEST_HEADER = """
╔══════════════════════════════════════════════════════════╗
║           Qwen 2.5 14B — ROCm Benchmark                 ║
╚══════════════════════════════════════════════════════════╝
"""


def benchmark_once(prompt: str) -> dict:
    payload = {
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 200,
        "temperature": 0.0,
        "stream": False,
    }
    req = request.Request(
        URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read())
    elapsed = time.time() - t0
    usage = body.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    prompt_tokens = usage.get("prompt_tokens", 0)
    tps = completion_tokens / elapsed if elapsed > 0 else 0
    return {
        "prompt": prompt[:80] + "...",
        "elapsed": elapsed,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "tokens_per_sec": tps,
    }


def main():
    print(TEST_HEADER)
    results = []
    for i, prompt in enumerate(BENCH_PROMPTS, 1):
        print(f"[{i}/{len(BENCH_PROMPTS)}] {prompt[:60]}...", end=" ", flush=True)
        try:
            r = benchmark_once(prompt)
            results.append(r)
            print(f"✓ {r['completion_tokens']} tokens in {r['elapsed']:.1f}s "
                  f"({r['tokens_per_sec']:.1f} tok/s)")
        except Exception as e:
            print(f"✗ {e}")

    if results:
        avg_tps = sum(r["tokens_per_sec"] for r in results) / len(results)
        total_tokens = sum(r["completion_tokens"] for r in results)
        total_time = sum(r["elapsed"] for r in results)
        print(f"\n{'─' * 56}")
        print(f"Results: {len(results)}/{len(BENCH_PROMPTS)} passed")
        print(f"Average:  {avg_tps:.1f} tokens/sec")
        print(f"Total:    {total_tokens} tokens in {total_time:.1f}s")
        print(f"{'─' * 56}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run benchmark**

```bash
python3 /Volumes/DATA_SSD/Github/qwen-llm-amd-multi/scripts/benchmark.py
```

Expected: 5/5 passed. Note the average tokens/sec.
Target: >15 tok/s for usable interactive chat, >25 tok/s is good for 14B on dual 6700 XT.

- [ ] **Step 5: Monitor GPUs during benchmark**

In a separate terminal or before running:
```bash
ssh mfirdaus@<server-lan-ip> "watch -n1 rocm-smi"
```

Expected: Both GPUs show utilization during inference, VRAM ~4-5 GB used per GPU.

- [ ] **Step 6: Update session log with results**

Add to `memory/session-log.md`:
```markdown
- **Smoke test:** Passed. Chat completion working correctly.
- **Benchmark:** Average [X] tok/s across 5 prompts. Both GPUs utilized.
```

- [ ] **Step 7: Commit**

```bash
git add scripts/test-chat.py scripts/benchmark.py memory/session-log.md
git commit -m "feat: add smoke test and benchmark scripts, verified working

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Docker — Container Build for Coolify (Phase 5 Prep)

**Files:**
- Create: `docker/Dockerfile`
- Create: `docker/docker-compose.yml`
- Create: `config/.env.example`

**Interfaces:**
- Consumes: Working local deployment (Tasks 1-10)
- Produces: Docker image with llama-server + model, ready for Coolify

- [ ] **Step 1: Write Dockerfile**

```dockerfile
# Dockerfile for llama.cpp + Qwen 14B on ROCm
# Build: docker build -t qwen-llm-amd:latest -f docker/Dockerfile .

FROM ubuntu:26.04 AS builder

RUN apt update && apt install -y \
    build-essential cmake git \
    rocm-hip-libraries rocm-hip-runtime rocm-core rocm-device-libs \
    libcurl4-openssl-dev

# Build llama.cpp with HIPBLAS
RUN git clone https://github.com/ggerganov/llama.cpp.git /build/llama.cpp
WORKDIR /build/llama.cpp
RUN mkdir build && cd build && \
    cmake .. \
        -DGGML_HIPBLAS=ON \
        -DAMDGPU_TARGETS=gfx1031 \
        -DGPU_TARGETS=gfx1031 \
        -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) llama-server

FROM ubuntu:26.04

RUN apt update && apt install -y \
    rocm-hip-runtime rocm-core rocm-smi-lib \
    libcurl4 libgomp1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server

# Model directory (mount model at runtime or copy into image)
RUN mkdir -p /opt/llm/models /opt/llm/logs

ENV HIP_VISIBLE_DEVICES=0,1
ENV HSA_OVERRIDE_GFX_VERSION=10.3.1

EXPOSE 8080

ENTRYPOINT ["llama-server"]
CMD ["--model", "/opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--n-gpu-layers", "99", \
     "--tensor-split", "12,12", \
     "--ctx-size", "8192", \
     "--threads", "6", \
     "--batch-size", "512", \
     "--flash-attn", \
     "--metrics"]
```

- [ ] **Step 2: Write docker-compose.yml**

```yaml
# docker-compose.yml — local testing on AMD server
# Usage: docker compose -f docker/docker-compose.yml up -d
#
# For Coolify deployment, mount the model from host or use a model volume.

version: "3.8"

services:
  llama-server:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: qwen-llm-amd
    ports:
      - "8080:8080"
    volumes:
      - /opt/llm/models:/opt/llm/models:ro
      - /opt/llm/logs:/opt/llm/logs
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
    group_add:
      - video
      - render
    restart: unless-stopped
    environment:
      - HIP_VISIBLE_DEVICES=0,1
      - HSA_OVERRIDE_GFX_VERSION=10.3.1
    security_opt:
      - seccomp:unconfined
    # For Tailscale: use host network mode or add a Tailscale sidecar
    network_mode: host
```

**Note:** `network_mode: host` is used so the container can access Tailscale interfaces directly. This simplifies Coolify networking.

- [ ] **Step 3: Write .env.example**

```bash
# Environment variables for Qwen LLM AMD deployment
# Copy this to .env and fill in values. .env is git-ignored.

# Model path
MODEL_PATH=/opt/llm/models/qwen2.5-14b-instruct-q4_k_m.gguf

# Server config
LLAMA_HOST=0.0.0.0
LLAMA_PORT=8080
CONTEXT_SIZE=8192
THREADS=6
BATCH_SIZE=512

# GPU config
GPU_LAYERS=99
TENSOR_SPLIT=12,12
GPU_COUNT=2

# ROCm
HIP_VISIBLE_DEVICES=0,1
HSA_OVERRIDE_GFX_VERSION=10.3.1

# Tailscale (do not commit auth keys)
TAILSCALE_AUTH_KEY=
```

- [ ] **Step 4: Update .gitignore**

Check `.gitignore` already covers `.env`. Add entries:
```
# Project-specific
/opt/
*.gguf
.env
config/.env
```

- [ ] **Step 5: Commit**

```bash
git add docker/Dockerfile docker/docker-compose.yml config/.env.example .gitignore
git commit -m "feat: add Dockerfile and compose for Coolify deployment path

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 12: Documentation — Installation Guide

**Files:**
- Create: `docs/install-amd-ubuntu.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: All completed tasks, real commands that worked
- Produces: Reproducible guide for similar AMD hardware

- [ ] **Step 1: Write installation guide**

Create `docs/install-amd-ubuntu.md` based on the commands that actually worked during Tasks 5-9. The document should cover:

1. **Prerequisites** — hardware checklist, Ubuntu version, GPU identification
2. **ROCm Installation** — exact repo URL, version, kernel module check
3. **llama.cpp Build** — clone, cmake flags, make targets
4. **Model Download** — HuggingFace repo, file name, size
5. **systemd Setup** — service file, environment vars, flag meanings
6. **Verification** — smoke test commands, expected output, benchmark targets
7. **Troubleshooting** — common errors (kfd not loading, GPU not detected, build failures)

Each section should have copy-pasteable commands and expected output.

- [ ] **Step 2: Wait until all server tasks complete**

The guide must reflect what actually worked, not what we predicted. Fill in:
- The exact ROCm version installed
- Any workarounds needed for Ubuntu 26.04
- Actual build time and binary size
- Actual benchmark numbers

- [ ] **Step 3: Update README.md**

Replace the one-line README with:
```markdown
# Qwen LLM on AMD Multi-GPU

Production local LLM deployment: Qwen 2.5 14B on AMD Radeon GPUs with ROCm.

## Hardware
- 2x AMD Radeon RX 6700 XT (24 GB VRAM total)
- AMD Ryzen 4600G, 32 GB RAM
- Ubuntu 26.04 LTS

## Quick Start
See [Installation Guide](docs/install-amd-ubuntu.md) for full setup.

### Test
```bash
python3 scripts/test-chat.py
python3 scripts/benchmark.py
```

### Server
```bash
ssh mfirdaus@<server-lan-ip>
systemctl status llama-server
tail -f /opt/llm/logs/llama-server.log
```
```

- [ ] **Step 4: Commit**

```bash
git add docs/install-amd-ubuntu.md README.md memory/session-log.md
git commit -m "docs: add reproducible installation guide and update README

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Execution Order

Tasks 1-2 (locally) → push → Task 3 (pull on server) → Tasks 4-10 (server) → Task 11 (local) → Task 12 (after all server work done)

Tasks 4-9 must run sequentially on the server. Task 10 can run from local machine against the server endpoint.
