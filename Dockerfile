# Qwen LLM AMD — Dockerfile for Coolify deployment
# Build: docker build -t qwen-llm-amd:latest -f docker/Dockerfile .
#
# Model is mounted at runtime (9 GB — too large for image layers).
# Run: see docker-compose.yml

FROM ubuntu:26.04 AS builder

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    build-essential cmake git ca-certificates gnupg wget \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# AMD ROCm repo
RUN wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg && \
    echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/7.2.4 noble main' \
    > /etc/apt/sources.list.d/amdgpu.list

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    rocm-hip-libraries rocm-hip-runtime rocm-core rocm-device-libs \
    rocblas rocblas-dev hipcc rocm-cmake \
    && rm -rf /var/lib/apt/lists/*

# Build llama.cpp with HIP targeting gfx1030
RUN git clone --depth 1 https://github.com/ggerganov/llama.cpp.git /build/llama.cpp
WORKDIR /build/llama.cpp
RUN mkdir build && cd build && \
    cmake .. \
        -DGGML_HIP=ON \
        -DCMAKE_HIP_ARCHITECTURES=gfx1030 \
        -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) llama-server

# --- Runtime stage ---
FROM ubuntu:26.04

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates wget gnupg \
    libcurl4 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# AMD ROCm runtime (no dev packages)
RUN wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg && \
    echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/7.2.4 noble main' \
    > /etc/apt/sources.list.d/amdgpu.list

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    rocm-hip-runtime rocm-core rocblas rocm-smi \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binary
COPY --from=builder /build/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server

# Directories
RUN mkdir -p /opt/llm/models /opt/llm/logs

# ROCm environment
ENV HIP_VISIBLE_DEVICES=0,1
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

ENTRYPOINT ["llama-server"]
CMD ["--model", "/opt/llm/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--n-gpu-layers", "99", \
     "--tensor-split", "12,12", \
     "--ctx-size", "8192", \
     "--threads", "6", \
     "--batch-size", "512", \
     "--flash-attn", "off", \
     "--metrics"]
