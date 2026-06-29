#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  models/videoinpainting.sh — Pré-download VideoInpainting
#  by Wilton Matos
#  ProPainter + DiffuEraser + OmnimatteZero
#  Chamado em background pelo base_init.sh
#
#  NOTA: estes 3 nodes baixam pesos automaticamente no 1º uso.
#  Este script PRÉ-baixa para a primeira execução não travar.
#  Os nodes já foram clonados pelo base_init.sh.
# ════════════════════════════════════════════════════════════════
set +e

MODELS_ROOT="${MODELS_ROOT:-/ComfyUI/models}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-/ComfyUI/custom_nodes}"
echo "═══ Pré-download VideoInpainting → $MODELS_ROOT ═══"

dl() {
    local url="$1"; local dest_dir="$2"; local fname="$3"
    mkdir -p "$dest_dir"
    if [ -f "$dest_dir/$fname" ]; then echo "  ✅ já existe: $fname"; return 0; fi
    echo "  ⬇️  $fname"
    aria2c -x 16 -s 16 -k 1M --console-log-level=warn --summary-interval=0 \
        --auto-file-renaming=false --allow-overwrite=true \
        -d "$dest_dir" -o "$fname" "$url" \
        && echo "  ✅ ok: $fname" || echo "  ⚠️  falha: $fname"
}

hf_dl() {
    local repo="$1"; local file="$2"; local dest_dir="$3"; local rename="$4"
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

# ════════════════════════════════════════════════════════════════
#  1. PROPAINTER — pesos no diretório weights/ do node
# ════════════════════════════════════════════════════════════════
echo "── [1/3] ProPainter ──"
PP_WEIGHTS="$CUSTOM_NODES_DIR/ComfyUI_ProPainter_Nodes/weights"
PP_BASE="https://github.com/sczhou/ProPainter/releases/download/v0.1.0"
dl "$PP_BASE/ProPainter.pth"                "$PP_WEIGHTS" "ProPainter.pth"
dl "$PP_BASE/recurrent_flow_completion.pth" "$PP_WEIGHTS" "recurrent_flow_completion.pth"
dl "$PP_BASE/raft-things.pth"               "$PP_WEIGHTS" "raft-things.pth"
dl "$PP_BASE/i3d_rgb_imagenet.pt"           "$PP_WEIGHTS" "i3d_rgb_imagenet.pt"

# ════════════════════════════════════════════════════════════════
#  2. DIFFUERASER — pesos do repo HF lixiaowen/diffuEraser
#  Estrutura no disco (esperada pelo node):
#    models/vae/sd-vae-ft-mse.safetensors
#    models/clip/clip_l.safetensors  (já vem com qualquer ComfyUI)
#    models/DiffuEraservae/brushnet/{config.json, diffusion_pytorch_model.safetensors}
#    models/DiffuEraservae/unet_main/{config.json, diffusion_pytorch_model.safetensors}
#    models/DiffuEraservae/propainter/{ProPainter.pth, raft-things.pth, recurrent_flow_completion.pth}
# ════════════════════════════════════════════════════════════════
echo "── [2/3] DiffuEraser ──"

# VAE base (sd-vae-ft-mse) → models/vae
hf_dl "stabilityai/sd-vae-ft-mse" "diffusion_pytorch_model.safetensors" "$MODELS_ROOT/vae" "sd-vae-ft-mse.safetensors"

# clip_l: já vem no ComfyUI padrão (models/clip/clip_l.safetensors).
# Se não existir, baixa do repo oficial do ComfyUI clip vision.
CLIP_DIR="$MODELS_ROOT/clip"
mkdir -p "$CLIP_DIR"
if [ ! -f "$CLIP_DIR/clip_l.safetensors" ]; then
    echo "  ⬇️  clip_l.safetensors (do repo Comfy-Org Flux1-dev)"
    hf_dl "Comfy-Org/flux1-dev" "split_files/text_encoders/clip_l.safetensors" "$CLIP_DIR" "clip_l.safetensors"
fi

# Pesos DiffuEraser (brushnet + unet_main) → models/DiffuEraservae
DE_DIR="$MODELS_ROOT/DiffuEraservae"
DE_REPO="lixiaowen/diffuEraser"
hf_dl "$DE_REPO" "brushnet/diffusion_pytorch_model.safetensors" "$DE_DIR/brushnet" "diffusion_pytorch_model.safetensors"
hf_dl "$DE_REPO" "brushnet/config.json"                          "$DE_DIR/brushnet" "config.json"
hf_dl "$DE_REPO" "unet_main/diffusion_pytorch_model.safetensors" "$DE_DIR/unet_main" "diffusion_pytorch_model.safetensors"
hf_dl "$DE_REPO" "unet_main/config.json"                         "$DE_DIR/unet_main" "config.json"

# DiffuEraser também usa os pesos do ProPainter no subdir propainter/
DE_PP="$DE_DIR/propainter"
mkdir -p "$DE_PP"
for f in ProPainter.pth raft-things.pth recurrent_flow_completion.pth; do
    if [ -f "$PP_WEIGHTS/$f" ] && [ ! -f "$DE_PP/$f" ]; then
        cp "$PP_WEIGHTS/$f" "$DE_PP/$f" && echo "  ↪️  copiado p/ DiffuEraser: $f"
    fi
done

# ════════════════════════════════════════════════════════════════
#  3. OMNIMATTE ZERO — baixa pesos no 1º uso (HF cache)
#  Node: ComfyUI-TP-OmnimatteZero. Modelos auto-baixam ao rodar.
# ════════════════════════════════════════════════════════════════
echo "── [3/3] OmnimatteZero ──"
echo "  ℹ️  OmnimatteZero baixa seus pesos automaticamente no primeiro uso do workflow."
echo "     (Node já instalado pelo base_init.sh — nenhum pré-download fixo necessário.)"

echo "═══ VideoInpainting pré-download finalizado ═══"
