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
| Network | LAN 192.168.1.12, 1 GbE |

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
