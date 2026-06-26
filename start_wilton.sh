#!/usr/bin/env bash

# ── GPU: desabilita torch.compile em Blackwell/Hopper (sm_100+) ──
SM=$(python3 -c "
import torch
cap = torch.cuda.get_device_capability()
print(cap[0]*10 + cap[1])
" 2>/dev/null || echo "0")

echo "GPU SM Capability: sm_$SM"
if [ "$SM" -ge 100 ]; then
    export TORCH_COMPILE_DISABLE=1
    echo "Blackwell/Hopper detectado — torch.compile desabilitado"
fi

# ── CUSTOM NODES ADICIONAIS (não incluídos no template base) ──────
COMFYUI_DIR="/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

declare -A EXTRA_NODES=(
    # Video / compositing
    ["ComfyUI-LTXVideo"]="https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    ["ComfyUI-BFSNodes"]="https://github.com/alisson-anjos/ComfyUI-BFSNodes.git"
    ["ComfyUI-SeedVR2_VideoUpscaler"]="https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    ["ComfyUI_ProPainter_Nodes"]="https://github.com/daniabib/ComfyUI_ProPainter_Nodes.git"
    ["ComfyUI_DiffuEraser"]="https://github.com/smthemex/ComfyUI_DiffuEraser.git"
    ["ComfyUI-TP-OmnimatteZero"]="https://github.com/tpc2233/ComfyUI-TP-OmnimatteZero.git"
    ["cotracker_node"]="https://github.com/s9roll7/comfyui_cotracker_node.git"

    # Inpaint / sampling
    ["LanPaint"]="https://github.com/scraed/LanPaint.git"
    ["ComfyUI-Inpaint-CropAndStitch"]="https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"

    # AI models / API
    ["MiniMax-bmo"]="https://github.com/casterpollux/MiniMax-bmo.git"
    ["radiance"]="https://github.com/fxtdstudios/radiance.git"

    # Utilities
    ["ComfyUI-Crystools"]="https://github.com/crystian/ComfyUI-Crystools.git"
    ["comfy_mtb"]="https://github.com/melMass/comfy_mtb.git"
    ["ComfyUI-Custom-Scripts"]="https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    ["batch_image_loader"]="https://github.com/orion4d/batch_image_loader.git"
    ["ComfyUI-Blender"]="https://github.com/alexisrolland/ComfyUI-Blender.git"
    ["Nvidia_RTX_Nodes_ComfyUI"]="https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git"

    # LoRA
    ["ComfyUI-SUPIR"]="https://github.com/kijai/ComfyUI-SUPIR.git"
)

echo "── Instalando custom nodes adicionais ──"
for name in "${!EXTRA_NODES[@]}"; do
    url="${EXTRA_NODES[$name]}"
    dir="$CUSTOM_NODES_DIR/$name"
    if [ ! -d "$dir" ]; then
        echo "Clonando $name..."
        git clone "$url" "$dir" || echo "AVISO: Falha ao clonar $name"
    else
        echo "$name já existe — atualizando..."
        git -C "$dir" pull || true
    fi
done

# ── INSTALA REQUIREMENTS DOS NOVOS NODES (em paralelo) ──────────
install_reqs() {
    local name=$1
    local dir="$CUSTOM_NODES_DIR/$name"
    if [ -f "$dir/requirements.txt" ]; then
        echo "Instalando requirements de $name..."
        pip install -r "$dir/requirements.txt" --quiet || echo "AVISO: Falha em $name requirements"
    fi
}

INSTALL_PIDS=()
for name in "${!EXTRA_NODES[@]}"; do
    install_reqs "$name" &
    INSTALL_PIDS+=($!)
done

# BFSNodes instala por último (monkey-patches LTX) para minimizar conflito
wait "${INSTALL_PIDS[@]}"
echo "Requirements dos nodes adicionais instalados"

# ── DEFENSIVE: reinstala onnxruntime-gpu se cv2 conflitou ────────
# ProPainter e DiffuEraser podem clobberar o onnxruntime-gpu do template
if ! python3 -c 'import onnxruntime as o, sys; sys.exit(0 if "CUDAExecutionProvider" in o.get_available_providers() else 1)' 2>/dev/null; then
    echo "onnxruntime CUDA provider perdido após instalação dos nodes — reinstalando..."
    pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null || true
    pip install onnxruntime-gpu --quiet
fi

# ── CHAMA O START ORIGINAL DO TEMPLATE ───────────────────────────
echo "Iniciando start.sh original do template..."
exec /bin/bash /start.sh
