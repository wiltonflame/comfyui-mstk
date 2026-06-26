#!/usr/bin/env bash
set +e  # Não sai em caso de erro — essencial para não matar o container

# ── GPU: detecta Blackwell e desabilita torch.compile ────────────
SM=$(python3 -c "
import torch
cap = torch.cuda.get_device_capability()
print(cap[0]*10 + cap[1])
" 2>/dev/null || echo "0")

echo "GPU SM Capability: sm_$SM"
if [ "$SM" -ge 100 ]; then
    export TORCH_COMPILE_DISABLE=1
    echo "Blackwell detectado — torch.compile desabilitado"
fi

# ── CUSTOM NODES ADICIONAIS ───────────────────────────────────────
COMFYUI_DIR="/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

EXTRA_NODES=(
    "ComfyUI-LTXVideo|https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    "ComfyUI-BFSNodes|https://github.com/alisson-anjos/ComfyUI-BFSNodes.git"
    "ComfyUI-SeedVR2_VideoUpscaler|https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    "ComfyUI_ProPainter_Nodes|https://github.com/daniabib/ComfyUI_ProPainter_Nodes.git"
    "ComfyUI_DiffuEraser|https://github.com/smthemex/ComfyUI_DiffuEraser.git"
    "ComfyUI-TP-OmnimatteZero|https://github.com/tpc2233/ComfyUI-TP-OmnimatteZero.git"
    "cotracker_node|https://github.com/s9roll7/comfyui_cotracker_node.git"
    "LanPaint|https://github.com/scraed/LanPaint.git"
    "ComfyUI-Inpaint-CropAndStitch|https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
    "MiniMax-bmo|https://github.com/casterpollux/MiniMax-bmo.git"
    "radiance|https://github.com/fxtdstudios/radiance.git"
    "ComfyUI-Crystools|https://github.com/crystian/ComfyUI-Crystools.git"
    "comfy_mtb|https://github.com/melMass/comfy_mtb.git"
    "ComfyUI-Custom-Scripts|https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "batch_image_loader|https://github.com/orion4d/batch_image_loader.git"
    "Comfyui-Memory_Cleanup|https://github.com/LAOGOU-666/Comfyui-Memory_Cleanup.git"
    "ComfyUI-Blender|https://github.com/alexisrolland/ComfyUI-Blender.git"
    "ComfyUI-SUPIR|https://github.com/kijai/ComfyUI-SUPIR.git"
    "Nvidia_RTX_Nodes_ComfyUI|https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git"
)

echo "── Instalando custom nodes adicionais ──"
for entry in "${EXTRA_NODES[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    dir="$CUSTOM_NODES_DIR/$name"
    if [ ! -d "$dir" ]; then
        echo "Clonando $name..."
        git clone "$url" "$dir" 2>/dev/null || echo "AVISO: Falha ao clonar $name — continuando"
    else
        echo "$name já existe — pulando"
    fi
done

# ── INSTALA REQUIREMENTS EM BACKGROUND ───────────────────────────
echo "── Instalando requirements dos nodes ──"
for entry in "${EXTRA_NODES[@]}"; do
    name="${entry%%|*}"
    dir="$CUSTOM_NODES_DIR/$name"
    if [ -f "$dir/requirements.txt" ]; then
        pip install -r "$dir/requirements.txt" --quiet 2>/dev/null &
    fi
done
wait
echo "── Requirements instalados ──"

# ── DEFENSIVE: verifica onnxruntime-gpu ──────────────────────────
if ! python3 -c 'import onnxruntime as o, sys; sys.exit(0 if "CUDAExecutionProvider" in o.get_available_providers() else 1)' 2>/dev/null; then
    echo "Reinstalando onnxruntime-gpu..."
    pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null || true
    pip install onnxruntime-gpu --quiet 2>/dev/null || true
fi

# ── CHAMA O START ORIGINAL DO TEMPLATE ───────────────────────────
echo "Iniciando /start.sh original do template..."
exec /bin/bash /start.sh

# Failsafe — nunca deve chegar aqui
sleep infinity
