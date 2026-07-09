# Qwen LLM AMD — Dockerfile for Coolify deployment
# Ubuntu 26.04 native ROCm packages from universe repo

FROM ubuntu:26.04 AS builder

# Enable universe repo (Docker ubuntu image has restricted sources)
RUN cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak && \
    sed -i 's/Components: main restricted/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    build-essential cmake git ca-certificates \
    libcurl4-openssl-dev \
    hipcc libamdhip64-dev librocblas-dev rocm-cmake rocm-device-libs-21 \
    && rm -rf /var/lib/apt/lists/*

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

RUN cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak && \
    sed -i 's/Components: main restricted/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates curl \
    libcurl4t64 libgomp1 \
    libamdhip64-7 librocblas5 rocm-smi \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server

RUN mkdir -p /opt/llm/models /opt/llm/logs

ENV HIP_VISIBLE_DEVICES=0,1
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0

EXPOSE 8080

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
