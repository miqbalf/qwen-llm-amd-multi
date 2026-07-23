#!/bin/bash
# llm_gpu_entrypoint.sh — read GPU profile written by image-video-gen handoff.
#
# Profile values:
#   "single" → GPU 1 only (ComfyUI owns GPU 0)
#   "dual"   → GPU 0,1 (no image gen running, use both)
#   (missing) → default both GPUs
#
# Usage: set as container ENTRYPOINT or CMD wrapper in Dockerfile.
# The profile file path must be mounted from the host.

PROFILE="${LLM_PROFILE_PATH:-/mnt/SSD_DATA/image-video-gen/run/llm_profile}"
DEFAULT_GPUS="${LLM_DEFAULT_GPUS:-0,1}"
SINGLE_GPU="${LLM_SINGLE_GPU:-1}"
# GPU layers to keep on-device while pinned to ONE 12GB GPU. The 14B Q4_K_M
# model (~8.4GB weights) plus the FULL 16384-token KV cache + compute buffers
# (flash-attn is off on gfx1031) overflows a single 12GB card if fully
# offloaded. We keep the full context (shrinking it breaks mid-conversation
# with "exceeds context size") and instead offload a few layers to CPU.
# Empirically ngl=32 (of 40) loads with headroom at ctx 16384 on one card.
SINGLE_NGL="${LLM_SINGLE_NGL:-32}"

MODE="dual"
if [ -f "$PROFILE" ]; then
    MODE=$(tr -d '[:space:]' < "$PROFILE")
fi

ARGS=("$@")

case "$MODE" in
    single)
        echo "[llm_gpu_entrypoint] Profile=$MODE → GPU $SINGLE_GPU"
        export HIP_VISIBLE_DEVICES="$SINGLE_GPU"
        # On one 12GB GPU we must rewrite two launch args or llama.cpp crashes:
        #   1. --tensor-split expects one value per visible GPU; a multi-value
        #      split (e.g. "12,12") fails with a single GPU visible — strip it.
        #   2. Full offload of 8.4GB weights + 16384 KV + compute OOMs on 12GB;
        #      keep the full context and cap --n-gpu-layers at SINGLE_NGL so a
        #      few layers spill to CPU (slower, but context stays consistent).
        FILTERED=()
        ngl_replaced=0
        i=0
        n=${#ARGS[@]}
        while [ "$i" -lt "$n" ]; do
            arg="${ARGS[$i]}"
            if [ "$arg" = "--tensor-split" ]; then
                i=$((i + 2))
                continue
            fi
            if [ "$arg" = "--n-gpu-layers" ] || [ "$arg" = "-ngl" ]; then
                FILTERED+=("$arg" "$SINGLE_NGL")
                ngl_replaced=1
                i=$((i + 2))
                continue
            fi
            FILTERED+=("$arg")
            i=$((i + 1))
        done
        if [ "$ngl_replaced" = "0" ]; then
            FILTERED+=("--n-gpu-layers" "$SINGLE_NGL")
        fi
        ARGS=("${FILTERED[@]}")
        echo "[llm_gpu_entrypoint] single-GPU: n-gpu-layers=$SINGLE_NGL, full ctx kept (partial CPU offload)"
        ;;
    dual|"")
        echo "[llm_gpu_entrypoint] Profile=$MODE → GPUs $DEFAULT_GPUS"
        export HIP_VISIBLE_DEVICES="$DEFAULT_GPUS"
        ;;
    *)
        echo "[llm_gpu_entrypoint] Unknown profile '$MODE', using default GPUs $DEFAULT_GPUS"
        export HIP_VISIBLE_DEVICES="$DEFAULT_GPUS"
        ;;
esac

echo "[llm_gpu_entrypoint] HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES"
exec /opt/llm/bin/llama-server "${ARGS[@]}"
