#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  models/ltx23_full.sh — LTX 2.3 FULL bf16 (sem quantização)
#  by Wilton Matos
#  Para RunPod com GPU robusta (48GB+ : L40, A40, RTX PRO 6000)
#
#  Inclui:
#    - Modelo dev 22B bf16 (46GB) — qualidade de produção
#    - VAEs + Gemma 3 12B bf16 + text projection
#    - LoRA distilled v1.1 + spatial upscaler v1.1
#    - TODOS os IC-LoRAs oficiais (HDR, Union, Motion-Track, LipDub)
#    - Creative Lab (Day-To-Night, Colorization, Deblur, etc.)
#
#  NOTA: arquivos grandes usam Xet — usamos `hf download` (multi-stream)
#  que é mais rápido que aria2 em arquivos Xet. Demais usam aria2c.
# ════════════════════════════════════════════════════════════════
set +e

MODELS_ROOT="${MODELS_ROOT:-/ComfyUI/models}"
echo "═══ Download LTX 2.3 FULL bf16 → $MODELS_ROOT ═══"

# Garante hf CLI disponível (vem no container, mas garantir não custa)
pip install -q "huggingface_hub[cli,hf_xet]" 2>/dev/null

# Download via hf CLI (ideal p/ arquivos Xet grandes) → move pro destino
hf_dl() {
    local repo="$1"; local file="$2"; local subdir="$3"; local rename="$4"
    local dest_dir="$MODELS_ROOT/$subdir"
    local final="${rename:-$(basename "$file")}"
    mkdir -p "$dest_dir"
    if [ -f "$dest_dir/$final" ]; then echo "  ✅ já existe: $final"; return 0; fi
    echo "  ⬇️  [hf] $repo → $final"
    hf download "$repo" "$file" --local-dir "$dest_dir/_tmp_$$" 2>/dev/null \
        && mv "$dest_dir/_tmp_$$/$file" "$dest_dir/$final" \
        && rm -rf "$dest_dir/_tmp_$$" \
        && echo "  ✅ ok: $final" \
        || { echo "  ⚠️  falha: $final"; rm -rf "$dest_dir/_tmp_$$"; }
}

# Download via aria2 (arquivos menores, URL resolve direto)
dl() {
    local url="$1"; local subdir="$2"; local fname="$3"
    local dest_dir="$MODELS_ROOT/$subdir"
    mkdir -p "$dest_dir"
    if [ -f "$dest_dir/$fname" ]; then echo "  ✅ já existe: $fname"; return 0; fi
    echo "  ⬇️  [aria2] $fname"
    aria2c -x 16 -s 16 -k 1M --console-log-level=warn --summary-interval=0 \
        --auto-file-renaming=false --allow-overwrite=true \
        -d "$dest_dir" -o "$fname" "$url" \
        && echo "  ✅ ok: $fname" || echo "  ⚠️  falha: $fname"
}

# ════════════════════════════════════════════════════════════════
#  1. MODELO BASE — dev 22B bf16 (46GB) → diffusion_models/
# ════════════════════════════════════════════════════════════════
echo "── [1/5] Modelo base dev bf16 (46GB) ──"
hf_dl "Lightricks/LTX-2.3" "ltx-2.3-22b-dev.safetensors" "diffusion_models"

# Distilled full v1.1 (46GB) — opcional, para drafting rápido em 8 steps
# Descomente se quiser também o distilled completo:
# hf_dl "Lightricks/LTX-2.3" "ltx-2.3-22b-distilled-1.1.safetensors" "diffusion_models"

# ════════════════════════════════════════════════════════════════
#  2. VAEs + TEXT ENCODER (Gemma bf16) — via Kijai/Comfy-Org repos
# ════════════════════════════════════════════════════════════════
echo "── [2/5] VAEs + Text Encoder ──"
hf_dl "Kijai/LTX2.3_comfy" "vae/LTX23_video_vae_bf16.safetensors" "vae" "LTX23_video_vae_bf16.safetensors"
hf_dl "Kijai/LTX2.3_comfy" "vae/LTX23_audio_vae_bf16.safetensors" "vae" "LTX23_audio_vae_bf16.safetensors"
hf_dl "Kijai/LTX2.3_comfy" "vae/taeltx2_3.safetensors" "vae" "taeltx2_3.safetensors"
hf_dl "Kijai/LTX2.3_comfy" "text_encoders/ltx-2.3_text_projection_bf16.safetensors" "text_encoders" "ltx-2.3_text_projection_bf16.safetensors"

# Gemma 3 12B bf16 full (para 32GB+) — via Comfy-Org
hf_dl "Comfy-Org/ltx-2" "split_files/text_encoders/gemma_3_12B_it_bf16.safetensors" "text_encoders" "comfy_gemma_3_12B_it.safetensors"

# ════════════════════════════════════════════════════════════════
#  3. DISTILLED LORA v1.1 + SPATIAL UPSCALER v1.1
# ════════════════════════════════════════════════════════════════
echo "── [3/5] Distilled LoRA + Upscaler ──"
hf_dl "Lightricks/LTX-2.3" "ltx-2.3-22b-distilled-lora-384-1.1.safetensors" "loras"
hf_dl "Lightricks/LTX-2.3" "ltx-2.3-spatial-upscaler-x2-1.1.safetensors" "latent_upscale_models"

# ════════════════════════════════════════════════════════════════
#  4. IC-LORAS OFICIAIS (HDR, Union, Motion-Track, LipDub)
# ════════════════════════════════════════════════════════════════
echo "── [4/5] IC-LoRAs oficiais ──"
# HDR — o principal para teu pipeline de delivery EXR/HDR
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-HDR" "ltx-2.3-22b-ic-lora-hdr-0.9.safetensors" "loras"
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-HDR" "ltx-2.3-22b-ic-lora-hdr-scene-emb.safetensors" "loras"
# Union control (estrutura: pose/depth/edges)
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control" "ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors" "loras"
# Motion-Track
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Motion-Track-Control" "ltx-2.3-22b-ic-lora-motion-track-control-ref0.5.safetensors" "loras"
# LipDub (dublagem)
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-LipDub" "ltx-2.3-22b-ic-lora-lipdub-0.9.safetensors" "loras"

# ════════════════════════════════════════════════════════════════
#  5. CREATIVE LAB (LoRAs criativos video-to-video)
# ════════════════════════════════════════════════════════════════
echo "── [5/5] Creative Lab ──"
# Day-To-Night
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Day-To-Night" "ltx-2.3-22b-ic-lora-day-to-night-0.9.safetensors" "loras"
# Colorization
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Colorization" "ltx-2.3-22b-ic-lora-colorization-0.9.safetensors" "loras"
# Decompression
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Decompression" "ltx-2.3-22b-ic-lora-decompression-0.9.safetensors" "loras"
# Deblur
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Deblur" "ltx-2.3-22b-ic-lora-deblur-0.9.safetensors" "loras"
# Water Simulation
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-Water-Simulation" "ltx-2.3-22b-ic-lora-water-simulation-0.9.safetensors" "loras"
# In-Outpainting
hf_dl "Lightricks/LTX-2.3-22b-IC-LoRA-In-Outpainting" "ltx-2.3-22b-ic-lora-in-outpainting-0.9.safetensors" "loras"
# FaceSwap (BFS - Best Face Swap Video)
hf_dl "Alissonerdx/BFS-Best-Face-Swap-Video" "ltx-2.3/head_swap_v3_rank_adaptive_fro_098.safetensors" "loras"

echo "═══ LTX 2.3 FULL download finalizado ═══"
echo "⚠️  Lembre: OPENCV_IO_ENABLE_OPENEXR=1 no env para escrita de EXR linear"
echo "⚠️  Modelo dev bf16 = 46GB. Requer 48GB+ VRAM ou sequential offload em 32GB."
