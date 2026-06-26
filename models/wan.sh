#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  models/wan.sh — Família Wan completa (T2V, I2V, Animate, VACE)
#  by Wilton Matos
#  Chamado em background pelo base_init.sh
#
#  Controle por sub-flag WAN_PARTS (separado por vírgula):
#    WAN_PARTS=t2v             → só text-to-video
#    WAN_PARTS=i2v             → só image-to-video
#    WAN_PARTS=animate         → só Wan Animate
#    WAN_PARTS=vace            → só Wan VACE
#    WAN_PARTS=i2v,animate     → combina os que quiser
#    WAN_PARTS=all (ou vazio)  → baixa TUDO (~150GB+)
#
#  Precisão: fp16 full (Animate/VACE só existem em bf16 = equivalente)
#  Common (VAE + text encoder + clip vision) baixa sempre que houver parte.
# ════════════════════════════════════════════════════════════════
set +e

MODELS_ROOT="${MODELS_ROOT:-/ComfyUI/models}"
WAN_PARTS="${WAN_PARTS:-all}"
echo "═══ Download Wan → $MODELS_ROOT (partes: $WAN_PARTS) ═══"

# helper: verifica se uma parte está habilitada
has_part() {
    [ "$WAN_PARTS" = "all" ] && return 0
    [[ ",$WAN_PARTS," == *",$1,"* ]] && return 0
    return 1
}

# download via hf CLI (ideal p/ arquivos Xet grandes)
hf_dl() {
    local repo="$1"; local file="$2"; local subdir="$3"; local rename="$4"
    local dest_dir="$MODELS_ROOT/$subdir"
    local final="${rename:-$(basename "$file")}"
    mkdir -p "$dest_dir"
    if [ -f "$dest_dir/$final" ]; then echo "  ✅ já existe: $final"; return 0; fi
    echo "  ⬇️  [hf] $final"
    hf download "$repo" "$file" --local-dir "$dest_dir/_tmp_$$" 2>/dev/null \
        && mv "$dest_dir/_tmp_$$/$file" "$dest_dir/$final" \
        && rm -rf "$dest_dir/_tmp_$$" \
        && echo "  ✅ ok: $final" \
        || { echo "  ⚠️  falha: $final"; rm -rf "$dest_dir/_tmp_$$"; }
}

pip install -q "huggingface_hub[cli,hf_xet]" 2>/dev/null

WAN22="Comfy-Org/Wan_2.2_ComfyUI_Repackaged"
WAN21="Comfy-Org/Wan_2.1_ComfyUI_repackaged"

# ════════════════════════════════════════════════════════════════
#  COMMON — sempre baixa se qualquer parte estiver ativa
#  (VAE, text encoder umt5, clip vision)
# ════════════════════════════════════════════════════════════════
echo "── Common (VAE + text encoder + clip vision) ──"
hf_dl "$WAN22" "split_files/vae/wan2.2_vae.safetensors" "vae" "wan2.2_vae.safetensors"
hf_dl "$WAN21" "split_files/vae/wan_2.1_vae.safetensors" "vae" "wan_2.1_vae.safetensors"
hf_dl "$WAN21" "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors"
hf_dl "$WAN21" "split_files/clip_vision/clip_vision_h.safetensors" "clip_vision" "clip_vision_h.safetensors"

# ════════════════════════════════════════════════════════════════
#  T2V — Text-to-Video 14B (high + low noise, fp16)
# ════════════════════════════════════════════════════════════════
if has_part "t2v"; then
    echo "── [T2V] Text-to-Video 14B fp16 ──"
    hf_dl "$WAN22" "split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp16.safetensors" "diffusion_models"
    hf_dl "$WAN22" "split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors" "diffusion_models"
fi

# ════════════════════════════════════════════════════════════════
#  I2V — Image-to-Video 14B (high + low noise, fp16) + LoRAs LightX2V
# ════════════════════════════════════════════════════════════════
if has_part "i2v"; then
    echo "── [I2V] Image-to-Video 14B fp16 ──"
    hf_dl "$WAN22" "split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors" "diffusion_models"
    hf_dl "$WAN22" "split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors" "diffusion_models"
    # LoRAs LightX2V 4-step (acelera I2V)
    hf_dl "lightx2v/Wan2.2-Distill-Loras" "wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors" "loras" "wan2.2_i2v_high_lightx2v_4step.safetensors"
    hf_dl "lightx2v/Wan2.2-Distill-Loras" "wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors" "loras" "wan2.2_i2v_low_lightx2v_4step.safetensors"
fi

# ════════════════════════════════════════════════════════════════
#  ANIMATE — Wan 2.2 Animate 14B (bf16) + relight LoRA + detection
# ════════════════════════════════════════════════════════════════
if has_part "animate"; then
    echo "── [ANIMATE] Wan 2.2 Animate 14B bf16 ──"
    hf_dl "$WAN22" "split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors" "diffusion_models"
    hf_dl "$WAN22" "split_files/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors" "loras"
    # Modelos de detecção (preprocessor: pose + bbox)
    hf_dl "Wan-AI/Wan2.2-Animate-14B" "process_checkpoint/det/yolov10m.onnx" "detection" "yolov10m.onnx"
    hf_dl "JunkyByte/easy_ViTPose" "onnx/wholebody/vitpose-l-wholebody.onnx" "detection" "vitpose-l-wholebody.onnx"
fi

# ════════════════════════════════════════════════════════════════
#  VACE — Wan 2.1 VACE module 14B (fp16) — video-to-video control
# ════════════════════════════════════════════════════════════════
if has_part "vace"; then
    echo "── [VACE] Wan 2.1 VACE 14B fp16 ──"
    hf_dl "$WAN21" "split_files/diffusion_models/wan2.1_vace_14B_fp16.safetensors" "diffusion_models"
fi

echo "═══ Wan download finalizado (partes: $WAN_PARTS) ═══"
