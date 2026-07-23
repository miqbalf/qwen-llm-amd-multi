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
# Context window used while pinned to ONE 12GB GPU. The 14B Q4_K_M model
# (~8.4GB weights) plus the full 16384-token KV cache and compute buffers
# (flash-attn is off on gfx1031) overflows a single 12GB card and OOMs.
# 8192 leaves >1GB headroom on one GPU while staying fully offloaded.
SINGLE_CTX_SIZE="${LLM_SINGLE_CTX_SIZE:-8192}"

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
        #   2. --ctx-size 16384 + 8.4GB weights + compute buffers OOMs on 12GB;
        #      shrink the context to SINGLE_CTX_SIZE so it fits fully offloaded.
        FILTERED=()
        ctx_replaced=0
        i=0
        n=${#ARGS[@]}
        while [ "$i" -lt "$n" ]; do
            arg="${ARGS[$i]}"
            if [ "$arg" = "--tensor-split" ]; then
                i=$((i + 2))
                continue
            fi
            if [ "$arg" = "--ctx-size" ] || [ "$arg" = "-c" ]; then
                FILTERED+=("$arg" "$SINGLE_CTX_SIZE")
                ctx_replaced=1
                i=$((i + 2))
                continue
            fi
            FILTERED+=("$arg")
            i=$((i + 1))
        done
        if [ "$ctx_replaced" = "0" ]; then
            FILTERED+=("--ctx-size" "$SINGLE_CTX_SIZE")
        fi
        ARGS=("${FILTERED[@]}")
        echo "[llm_gpu_entrypoint] single-GPU: ctx-size=$SINGLE_CTX_SIZE (fits 12GB)"
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
