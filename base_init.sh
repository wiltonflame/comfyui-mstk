#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  ComfyWill — base_init.sh
#  Script UNIVERSAL de inicialização para pods ComfyUI no RunPod
#  by Wilton Matos
#
#  Funciona em QUALQUER pod ComfyUI (template hearmeman OU pod base
#  zerado sem nodes/modelos). Detecta o ambiente automaticamente.
#
#  Uso (no Container Start Command do RunPod):
#    bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=wan WAN_PARTS=i2v,animate bash"
#
#  Variáveis aceitas:
#    MODEL      = wan | ltx | videoinpainting   (pacote de modelos; vazio = só nodes)
#    WAN_PARTS  = t2v,i2v,animate,vace          (sub-flag do Wan; vazio = all)
#    REPO       = URL base dos scripts          (default: repo do Wilton)
#    SKIP_NODES = 1                             (pula instalação dos custom nodes)
# ════════════════════════════════════════════════════════════════
set +e  # nunca mata o container por erro de um node

REPO="${REPO:-https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main}"
MODEL="${MODEL:-none}"

echo "═══════════════════════════════════════════════"
echo "  ComfyWill init — modelo: $MODEL"
echo "═══════════════════════════════════════════════"

# ── 1. DETECÇÃO DE GPU (Blackwell desabilita torch.compile) ──────
SM=$(python3 -c "
import torch
cap = torch.cuda.get_device_capability()
print(cap[0]*10 + cap[1])
" 2>/dev/null || echo "0")

echo "GPU SM Capability: sm_$SM"
if [ "$SM" -ge 100 ]; then
    export TORCH_COMPILE_DISABLE=1
    echo "Blackwell/Hopper (sm_$SM) — torch.compile DESABILITADO"
else
    echo "GPU sm_$SM — torch.compile e Triton ativos"
fi

# ── 2. DETECÇÃO DO COMFYUI (funciona em qualquer pod) ────────────
COMFYUI_DIR=""
for d in /ComfyUI /workspace/ComfyUI /comfyui /workspace/comfyui /root/ComfyUI; do
    if [ -f "$d/main.py" ]; then COMFYUI_DIR="$d"; break; fi
done
if [ -z "$COMFYUI_DIR" ]; then
    found=$(find / -maxdepth 4 -name "main.py" -path "*omfyUI*" 2>/dev/null | head -1)
    [ -n "$found" ] && COMFYUI_DIR="$(dirname "$found")"
fi
[ -z "$COMFYUI_DIR" ] && COMFYUI_DIR="/ComfyUI"

export COMFYUI_DIR
export CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
export MODELS_ROOT="$COMFYUI_DIR/models"
mkdir -p "$CUSTOM_NODES_DIR" "$MODELS_ROOT"
echo "ComfyUI dir : $COMFYUI_DIR"
echo "Models root : $MODELS_ROOT"

# ── 3. CUSTOM NODES — FOREGROUND (ComfyUI precisa deles no boot) ──
if [ "$SKIP_NODES" != "1" ]; then
    echo "── Instalando custom nodes (foreground) ──"

EXTRA_NODES=(
    # Video / compositing
    "ComfyUI-WanVideoWrapper|https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "ComfyUI-WanAnimatePreprocess|https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git"
    "ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes.git"
    "ComfyUI-VideoHelperSuite|https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "ComfyUI-LTXVideo|https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    "ComfyUI-BFSNodes|https://github.com/alisson-anjos/ComfyUI-BFSNodes.git"
    "ComfyUI-SeedVR2_VideoUpscaler|https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    "ComfyUI_ProPainter_Nodes|https://github.com/daniabib/ComfyUI_ProPainter_Nodes.git"
    "ComfyUI_DiffuEraser|https://github.com/smthemex/ComfyUI_DiffuEraser.git"
    "ComfyUI-TP-OmnimatteZero|https://github.com/tpc2233/ComfyUI-TP-OmnimatteZero.git"
    "cotracker_node|https://github.com/s9roll7/comfyui_cotracker_node.git"
    # Inpaint / sampling
    "LanPaint|https://github.com/scraed/LanPaint.git"
    "ComfyUI-Inpaint-CropAndStitch|https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
    # GGUF
    "ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF.git"
    # AI models / API
    "MiniMax-bmo|https://github.com/casterpollux/MiniMax-bmo.git"
    "radiance|https://github.com/fxtdstudios/radiance.git"
    # Utilities
    "ComfyUI-Crystools|https://github.com/crystian/ComfyUI-Crystools.git"
    "comfy_mtb|https://github.com/melMass/comfy_mtb.git"
    "ComfyUI-Custom-Scripts|https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "ComfyUI-Pixaroma|https://github.com/pixaroma/ComfyUI-Pixaroma.git"
    "batch_image_loader|https://github.com/orion4d/batch_image_loader.git"
    "Comfyui-Memory_Cleanup|https://github.com/LAOGOU-666/Comfyui-Memory_Cleanup.git"
    "ComfyUI-Blender|https://github.com/alexisrolland/ComfyUI-Blender.git"
    "ComfyUI-SUPIR|https://github.com/kijai/ComfyUI-SUPIR.git"
    "Nvidia_RTX_Nodes_ComfyUI|https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git"
    "rgthree-comfy|https://github.com/rgthree/rgthree-comfy.git"
    # Manager
    "comfyui-manager|https://github.com/ltdrdata/ComfyUI-Manager.git"
)

    for entry in "${EXTRA_NODES[@]}"; do
        name="${entry%%|*}"
        url="${entry##*|}"
        dir="$CUSTOM_NODES_DIR/$name"
        if [ ! -d "$dir" ]; then
            git clone --depth=1 "$url" "$dir" 2>/dev/null \
                && echo "  OK   $name" \
                || echo "  FAIL $name"
        else
            echo "  SKIP $name (ja existe)"
        fi
    done

    echo "── Instalando requirements dos nodes ──"
    for entry in "${EXTRA_NODES[@]}"; do
        name="${entry%%|*}"
        dir="$CUSTOM_NODES_DIR/$name"
        [ -f "$dir/requirements.txt" ] && \
            pip install -r "$dir/requirements.txt" --quiet 2>/dev/null &
    done
    wait
    echo "Custom nodes prontos"

    if ! python3 -c 'import onnxruntime as o, sys; sys.exit(0 if "CUDAExecutionProvider" in o.get_available_providers() else 1)' 2>/dev/null; then
        echo "Reinstalando onnxruntime-gpu..."
        pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null
        pip install onnxruntime-gpu --quiet 2>/dev/null
    fi
else
    echo "SKIP_NODES=1 — pulando custom nodes"
fi

command -v aria2c >/dev/null 2>&1 || { echo "Instalando aria2..."; apt-get update -qq 2>/dev/null && apt-get install -y -qq aria2 2>/dev/null; }
pip install -q "huggingface_hub[cli,hf_xet]" 2>/dev/null

# ── 4. DOWNLOAD DE MODELOS — BACKGROUND ──────────────────────────
export WAN_PARTS="${WAN_PARTS:-all}"

if [ "$MODEL" != "none" ]; then
    echo "── Download de modelos '$MODEL' em BACKGROUND ──"
    [ "$MODEL" = "wan" ] && echo "   WAN_PARTS=$WAN_PARTS"
    (
        curl -fsSL "$REPO/models/${MODEL}.sh" -o /tmp/model_dl.sh \
            && MODELS_ROOT="$MODELS_ROOT" CUSTOM_NODES_DIR="$CUSTOM_NODES_DIR" WAN_PARTS="$WAN_PARTS" \
               bash /tmp/model_dl.sh > /tmp/model_download.log 2>&1 \
            && echo "[BG] Download '$MODEL' completo" >> /tmp/model_download.log \
            || echo "[BG] Falha no download de '$MODEL'" >> /tmp/model_download.log
    ) &
    echo "Download rodando em background → tail -f /tmp/model_download.log"
else
    echo "MODEL=none — nenhum modelo sera baixado"
fi

# ── 5. SOBE O COMFYUI (universal) ────────────────────────────────
echo "── Iniciando ComfyUI ──"

if [ -f /start.sh ] && grep -q "ComfyUI" /start.sh 2>/dev/null; then
    echo "Detectado /start.sh do template — delegando a ele"
    exec /bin/bash /start.sh
fi

echo "Pod base — iniciando ComfyUI diretamente em $COMFYUI_DIR"
cd "$COMFYUI_DIR" || exit 1

if command -v jupyter-lab >/dev/null 2>&1; then
    nohup jupyter-lab --ip=0.0.0.0 --port=8888 --allow-root --no-browser \
        --NotebookApp.token='' --NotebookApp.password='' \
        --ServerApp.allow_origin='*' --notebook-dir=/ \
        > /tmp/jupyter.log 2>&1 &
    echo "JupyterLab iniciado na porta 8888"
fi

ATTENTION_FLAG=""
python3 -c "import sageattention" 2>/dev/null && ATTENTION_FLAG="--use-sage-attention"

exec python3 main.py --listen --port 8188 --enable-cors-header '*' $ATTENTION_FLAG
