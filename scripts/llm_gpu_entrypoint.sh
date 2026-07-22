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

MODE="dual"
if [ -f "$PROFILE" ]; then
    MODE=$(tr -d '[:space:]' < "$PROFILE")
fi

ARGS=("$@")

case "$MODE" in
    single)
        echo "[llm_gpu_entrypoint] Profile=$MODE → GPU $SINGLE_GPU"
        export HIP_VISIBLE_DEVICES="$SINGLE_GPU"
        # --tensor-split expects one value per visible GPU. With only one
        # GPU visible, a multi-value split (e.g. "12,12") makes llama.cpp
        # fail at startup — strip it so single-GPU mode always works.
        FILTERED=()
        skip_next=0
        for arg in "${ARGS[@]}"; do
            if [ "$skip_next" = "1" ]; then
                skip_next=0
                continue
            fi
            if [ "$arg" = "--tensor-split" ]; then
                skip_next=1
                continue
            fi
            FILTERED+=("$arg")
        done
        ARGS=("${FILTERED[@]}")
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
