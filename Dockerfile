# Qwen LLM AMD — Dockerfile
# Build ON the AMD server, push to ghcr.io, Coolify pulls.
#
# Build:
#   docker build -t ghcr.io/miqbalf/qwen-llm-amd:latest .
#   docker push ghcr.io/miqbalf/qwen-llm-amd:latest

FROM ubuntu:26.04

# Only Ubuntu main repo packages — no external repos needed
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates curl \
    libgomp1 \
    libdrm2 libdrm-amdgpu1 \
    libnuma1 libelf1 libfmt10 \
    zlib1g libzstd1 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Pre-built llama.cpp binaries (built on AMD server)
COPY build-bin/ /opt/llm/bin/

# ROCm 7.2.4 runtime libraries (from /opt/rocm-7.2.4/lib/)
COPY rocm-libs/ /opt/rocm/lib/

# System ROCm libs (from /usr/lib/x86_64-linux-gnu/)
COPY rocm-syslibs/ /usr/lib/x86_64-linux-gnu/

RUN ldconfig && \
    mkdir -p /opt/llm/models /opt/llm/logs

ENV HIP_VISIBLE_DEVICES=0,1
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0
ENV LD_LIBRARY_PATH=/opt/rocm/lib:/opt/llm/bin

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8081/health || exit 1

ENTRYPOINT ["/opt/llm/bin/llama-server"]
CMD ["--model", "/opt/llm/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf", \
     "--host", "0.0.0.0", \
     "--port", "8081", \
     "--n-gpu-layers", "99", \
     "--tensor-split", "12,12", \
     "--ctx-size", "8192", \
     "--threads", "6", \
     "--batch-size", "512", \
     "--flash-attn", "off", \
     "--metrics"]
