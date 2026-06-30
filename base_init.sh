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

# ── DETECÇÃO DO VENV (runpod-slim usa .venv-cu128, outros podem ter .venv) ──
VENV_PYTHON=""
for venv_name in .venv-cu128 .venv venv env; do
    candidate="$COMFYUI_DIR/$venv_name/bin/python"
    if [ -f "$candidate" ]; then
        if "$candidate" -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
            VENV_PYTHON="$candidate"
            VENV_PIP="$COMFYUI_DIR/$venv_name/bin/pip"
            echo "Venv detectado: $COMFYUI_DIR/$venv_name"
            # Redetecta SM com o Python correto do venv
            SM=$("$VENV_PYTHON" -c "import torch; cap=torch.cuda.get_device_capability(); print(cap[0]*10+cap[1])" 2>/dev/null || echo "$SM")
            echo "GPU SM (venv): sm_$SM"
            if [ "$SM" -ge 100 ]; then export TORCH_COMPILE_DISABLE=1; fi
            break
        fi
    fi
done

# Python/pip a usar — venv tem prioridade sobre sistema
if [ -n "$VENV_PYTHON" ]; then
    PY="$VENV_PYTHON"
    PIP="$VENV_PIP"
else
    PY="python3"
    PIP="pip"
    echo "Sem venv CUDA — usando Python do sistema"
fi
export PY PIP

# ── 3. CUSTOM NODES — FOREGROUND (ComfyUI precisa deles no boot) ──
if [ "$SKIP_NODES" != "1" ]; then
    echo "── Instalando custom nodes (foreground) ──"

    EXTRA_NODES=(
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
        "LanPaint|https://github.com/scraed/LanPaint.git"
        "ComfyUI-Inpaint-CropAndStitch|https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git"
        "ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF.git"
        "MiniMax-bmo|https://github.com/casterpollux/MiniMax-bmo.git"
        "radiance|https://github.com/fxtdstudios/radiance.git"
        "ComfyUI-Crystools|https://github.com/crystian/ComfyUI-Crystools.git"
        "comfy_mtb|https://github.com/melMass/comfy_mtb.git"
        "ComfyUI-Custom-Scripts|https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
        "batch_image_loader|https://github.com/orion4d/batch_image_loader.git"
        "Comfyui-Memory_Cleanup|https://github.com/LAOGOU-666/Comfyui-Memory_Cleanup.git"
        "ComfyUI-SUPIR|https://github.com/kijai/ComfyUI-SUPIR.git"
        "Nvidia_RTX_Nodes_ComfyUI|https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git"
        "ComfyUI-QwenVL|https://github.com/1038lab/ComfyUI-QwenVL.git"
        "ComfyUI_essentials|https://github.com/cubiq/ComfyUI_essentials.git"
        "ComfyUI-qwenmultiangle|https://github.com/jtydhr88/ComfyUI-qwenmultiangle.git"
        "ComfyUI-Florence2|https://github.com/kijai/ComfyUI-Florence2.git"
        "comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git"
        "ComfyUI-Impact-Pack|https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
        "ComfyUI-RMBG|https://github.com/1038lab/ComfyUI-RMBG.git"
        "ComfyUI-WD14-Tagger|https://github.com/pythongosssss/ComfyUI-WD14-Tagger.git"
        "RES4LYF|https://github.com/ClownsharkBatwing/RES4LYF.git"
        "comfyui_segment_anything|https://github.com/storyicon/comfyui_segment_anything.git"
        "ComfyUI_Fill-Nodes|https://github.com/filliptm/ComfyUI_Fill-Nodes.git"
        "rgthree-comfy|https://github.com/rgthree/rgthree-comfy.git"
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

    # ── CONSTRAINTS: protege torch/numpy desde já, antes de qualquer
    # instalação de requirements.txt de node — assim a agregação abaixo
    # nunca arrisca tocar nessas duas libs já validadas no boot.
    TORCH_VER=$("$PY" -c "import torch; print(torch.__version__)" 2>/dev/null)
    CONSTRAINTS="/tmp/comfywill_constraints.txt"
    {
        [ -n "$TORCH_VER" ] && echo "torch==$TORCH_VER"
        echo "numpy<2.0"
    } > "$CONSTRAINTS"
    echo "  Constraints: torch==$TORCH_VER, numpy<2.0"

    # ── PATCH: remove pins problemáticos ANTES de agregar requirements ──
    # DiffuEraser pina accelerate==0.30.1 que quebra peft/SeedVR2/MiniMax/OmnimatteZero.
    # Precisa rodar antes da agregação, senão o pin ruim entra no merge.
    for req in \
        "$CUSTOM_NODES_DIR/ComfyUI_DiffuEraser/requirements.txt" \
        "$CUSTOM_NODES_DIR/ComfyUI-SeedVR2_VideoUpscaler/requirements.txt"; do
        if [ -f "$req" ]; then
            sed -i 's/accelerate==0\.30\.1/accelerate>=1.0/g' "$req"
            sed -i 's/accelerate==[0-9]\+\.[0-9]\+\.[0-9]*/accelerate>=1.0/g' "$req"
            sed -i 's/diffusers==[0-9]\+\.[0-9]\+\.[0-9]*/diffusers>=0.32/g' "$req"
            echo "  Patched: $(basename $(dirname $req))/requirements.txt"
        fi
    done

    # ── PATCH: ComfyUI-LTXVideo importa 'pad' de kornia.geometry.transform.pyramid
    # mas kornia>=0.8.3 removeu esse re-export (pad só existe em kornia.core agora).
    # Bug upstream conhecido (PRs #506/#508/#516 abertos, ainda não mergeados).
    LTX_PYRAMID="$CUSTOM_NODES_DIR/ComfyUI-LTXVideo/pyramid_blending.py"
    if [ -f "$LTX_PYRAMID" ] && grep -q "from kornia.geometry.transform.pyramid import" "$LTX_PYRAMID" 2>/dev/null; then
        "$PY" << PYEOF
path = "$LTX_PYRAMID"
with open(path) as f:
    content = f.read()
start = content.find("from kornia.geometry.transform.pyramid import (")
if start != -1:
    end = content.find(")", start) + 1
    block = content[start:end]
    inner = block[block.find("(")+1:block.rfind(")")]
    raw_names = [n.strip() for n in inner.split(",")]
    if "pad" in raw_names:
        names = [n for n in raw_names if n and n != "pad"]
        new_block = "from kornia.core import pad\nfrom kornia.geometry.transform.pyramid import (\n    " + ",\n    ".join(names) + ",\n)"
        content = content[:start] + new_block + content[end:]
        with open(path, "w") as f:
            f.write(content)
        print("  Patched: ComfyUI-LTXVideo/pyramid_blending.py (kornia pad import)")
PYEOF
    fi

    # ── REQUIREMENTS: RESOLUÇÃO AGREGADA (single-pass) ──────────────
    # Em vez de instalar requirements.txt de cada node em sequência/paralelo
    # (onde o node N pode silenciosamente derrubar uma versão que o node N-1
    # já tinha deixado funcionando), juntamos TODOS os requirements.txt num
    # único arquivo, removemos duplicatas e pacotes "críticos" (que o bloco
    # de fixes abaixo já controla com precisão), e mandamos pro pip de UMA
    # vez. O resolver do pip enxerga o grafo completo e resolve tudo junto
    # — muito mais estável que instalações seriais brigando entre si.
    echo "── Resolvendo requirements agregados (single-pass) ──"
    MERGED_REQ="/tmp/comfywill_merged_requirements.txt"

    "$PY" << PYEOF
import re, glob, os

# Pacotes "críticos" que o bloco de fixes finais já trava com precisão.
# Excluí-los da agregação evita que a resolução conjunta tente uma versão
# diferente da que sabemos que funciona — o bloco final tem a palavra final.
BLACKLIST = {
    "torch", "torchvision", "torchaudio", "torchsde", "xformers", "triton",
    "numpy", "kornia", "safetensors", "accelerate", "diffusers", "transformers",
    "huggingface_hub", "huggingface-hub", "peft", "einops",
    "onnxruntime", "onnxruntime-gpu", "onnxruntime-directml",
}

seen = set()
lines_out = []
skipped = 0
files_used = 0

pattern = os.path.join("$CUSTOM_NODES_DIR", "*", "requirements.txt")
for req_file in sorted(glob.glob(pattern)):
    try:
        added_from_this_file = 0
        with open(req_file, encoding="utf-8", errors="ignore") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith(("-r ", "-e ", "--")):
                    continue
                pkg = re.split(r'[=<>!~\[\s;@]', line, 1)[0].strip().lower()
                if not pkg:
                    continue
                if pkg in BLACKLIST:
                    skipped += 1
                    continue
                key = line.lower()
                if key in seen:
                    continue
                seen.add(key)
                lines_out.append(line)
                added_from_this_file += 1
        if added_from_this_file:
            files_used += 1
    except Exception as e:
        print(f"  Aviso: erro lendo {req_file}: {e}")

with open("$MERGED_REQ", "w") as f:
    f.write("\n".join(lines_out) + ("\n" if lines_out else ""))

print(f"  {len(lines_out)} linhas unicas de {files_used} requirements.txt agregadas")
print(f"  {skipped} linhas de pacotes criticos excluidas (protegidos pelo fix block final)")
PYEOF

    AGGREGATE_OK=0
    if [ -s "$MERGED_REQ" ]; then
        if $PIP install --quiet -r "$MERGED_REQ" -c "$CONSTRAINTS" 2>/tmp/comfywill_merge_error.log; then
            echo "  ✅ Requirements agregados instalados com sucesso (single-pass)"
            AGGREGATE_OK=1
        else
            echo "  ⚠️  Resolução agregada falhou — caindo para instalação individual (modo seguro)"
            tail -5 /tmp/comfywill_merge_error.log 2>/dev/null | sed 's/^/    /'
        fi
    else
        echo "  Nenhum requirements.txt relevante encontrado"
        AGGREGATE_OK=1
    fi

    if [ "$AGGREGATE_OK" != "1" ]; then
        echo "  Fallback: instalando requirements.txt node por node..."
        for entry in "${EXTRA_NODES[@]}"; do
            name="${entry%%|*}"
            dir="$CUSTOM_NODES_DIR/$name"
            [ -f "$dir/requirements.txt" ] && \
                $PIP install -r "$dir/requirements.txt" --quiet 2>/dev/null &
        done
        wait
    fi
    echo "Custom nodes prontos"

    # ── FIX: dependências comuns que requirements dos nodes quebram ──
    # 1. onnxruntime-gpu 1.27+ exige CUDA 13. Pod com cu128 precisa cu12-compat (1.20.1)
    # 2. accelerate antigo (sem clear_device_cache) quebra SeedVR2/DiffuEraser/MiniMax
    # 3. diffusers/peft precisam estar alinhados
    echo "── Aplicando fixes de dependências (accelerate/onnxruntime/diffusers) ──"

    # Detecta versão de CUDA do PyTorch
    CUDA_MAJOR=$(python3 -c "import torch; print(torch.version.cuda.split('.')[0] if torch.version.cuda else '0')" 2>/dev/null || echo "0")
    echo "PyTorch CUDA major: $CUDA_MAJOR"

    # Fix numpy: scipy compilado em NumPy 1.x não roda com NumPy 2.x
    $PIP install --quiet "numpy<2.0" 2>/dev/null \
        && echo "  ✅ numpy<2.0 OK" \
        || echo "  ⚠️  numpy fix falhou"

    CUDA_MAJOR=$("$PY" -c "import torch; print(torch.version.cuda.split('.')[0] if torch.version.cuda else '0')" 2>/dev/null || echo "0")
    echo "PyTorch CUDA major: $CUDA_MAJOR"

    if [ "$CUDA_MAJOR" = "12" ]; then
        $PIP install --quiet --force-reinstall "onnxruntime-gpu==1.20.1" \
            --extra-index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-12/pypi/simple/ \
            2>/dev/null \
        || $PIP install --quiet --force-reinstall "onnxruntime-gpu==1.20.1" 2>/dev/null
    else
        if ! "$PY" -c 'import onnxruntime as o, sys; sys.exit(0 if "CUDAExecutionProvider" in o.get_available_providers() else 1)' 2>/dev/null; then
            $PIP install --quiet --force-reinstall onnxruntime-gpu 2>/dev/null
        fi
    fi

    # Upgrade accelerate + peft + diffusers no venv correto

    # FIX: dist-info corrompido do accelerate causa "TypeError: NoneType
    # object is not iterable" no boot (transformers nao consegue ler a versao).
    # Acontece apos multiplas instalacoes conflitantes na mesma sessao pip.
    SITE_PACKAGES=$("$PY" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
    if [ -n "$SITE_PACKAGES" ]; then
        rm -rf "$SITE_PACKAGES"/accelerate-*.dist-info 2>/dev/null
        rm -rf "$SITE_PACKAGES"/accelerate 2>/dev/null
    fi

    # FIX: kornia é mascarada pelo sistema (--system-site-packages do venv).
    # Precisa de --force-reinstall --no-deps ISOLADO — sem --no-deps ele
    # tentaria reinstalar o torch também e quebraria contra o constraint
    # de versão exata (torch==X+cuXXX não existe no PyPI genérico).
    echo "  Forçando kornia no venv (bypass system-site-packages)..."
    $PIP install --quiet --force-reinstall --no-deps "kornia>=0.8" 2>/dev/null

    # Resto das libs: SEM --force-reinstall. O cap "transformers<5.0" já
    # força o downgrade sozinho, pois a versão atual (5.x) VIOLA esse cap
    # — não precisa forçar. Isso evita o pip tentar reinstalar o torch.
    $PIP install --quiet -c "$CONSTRAINTS" \
        "accelerate==1.14.0" \
        "peft>=0.13" \
        "diffusers==0.38.0" \
        "transformers>=4.51,<5.0" \
        "huggingface_hub>=0.34,<1.0" \
        "einops>=0.8" 2>/dev/null

    # Sanity check final de toda a cadeia
    "$PY" -c "
import torch, numpy
print('  torch:', torch.__version__, '| CUDA:', torch.cuda.is_available())
print('  numpy:', numpy.__version__)
" 2>/dev/null

    # Sanity check: garante que a versao do accelerate e legivel (nao so importavel)
    "$PY" -c "import accelerate; v=accelerate.__version__; assert v" 2>/dev/null \
        && echo "  accelerate metadata OK ($("$PY" -c "import accelerate; print(accelerate.__version__)" 2>/dev/null))" \
        || { echo "  accelerate metadata corrompida - forcando reinstall limpo"; \
             rm -rf "$SITE_PACKAGES"/accelerate-*.dist-info "$SITE_PACKAGES"/accelerate 2>/dev/null; \
             $PIP install --quiet -c "$CONSTRAINTS" "accelerate==1.14.0" 2>/dev/null; }

    # Sanity check usando o Python correto
    "$PY" -c "from accelerate.utils.memory import clear_device_cache" 2>/dev/null \
        && echo "  ✅ accelerate OK" \
        || echo "  ⚠️  accelerate ainda problemático"
    "$PY" -c "import onnxruntime as o; assert 'CUDAExecutionProvider' in o.get_available_providers()" 2>/dev/null \
        && echo "  ✅ onnxruntime CUDA OK" \
        || echo "  ⚠️  onnxruntime sem CUDA"
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

# Detecta runpod-slim (tem constraints que sobrescrevem nossas versões no boot)
RUNPOD_SLIM=0
if [ -f /opt/comfyui-runtime-constraints.txt ]; then
    RUNPOD_SLIM=1
    echo "Template runpod-slim detectado (com runtime constraints)"
fi

if [ "$RUNPOD_SLIM" = "1" ]; then
    # runpod-slim: subimos FileBrowser/Jupyter manualmente E o ComfyUI direto,
    # BYPASSANDO o /start.sh que aplicaria constraints e sobrescreveria numpy.
    echo "Subindo serviços auxiliares (FileBrowser + JupyterLab)..."

    # FileBrowser na 8080 (se o template tem o binário)
    if command -v filebrowser >/dev/null 2>&1; then
        FB_DB=$(find /workspace -maxdepth 3 -name "filebrowser.db" 2>/dev/null | head -1)
        [ -z "$FB_DB" ] && FB_DB="/workspace/filebrowser.db"
        nohup filebrowser -d "$FB_DB" -a 0.0.0.0 -p 8080 -r / > /tmp/filebrowser.log 2>&1 &
        echo "FileBrowser iniciado na porta 8080"
    fi

    # JupyterLab na 8888
    if [ -f "$COMFYUI_DIR/.venv-cu128/bin/jupyter-lab" ]; then
        nohup "$COMFYUI_DIR/.venv-cu128/bin/jupyter-lab" --ip=0.0.0.0 --port=8888 --allow-root --no-browser \
            --NotebookApp.token='' --NotebookApp.password='' \
            --ServerApp.allow_origin='*' --notebook-dir=/ \
            > /tmp/jupyter.log 2>&1 &
        echo "JupyterLab iniciado na porta 8888"
    fi

    # Re-aplica numpy<2 caso algum constraints já tenha rodado
    "$PIP" install --quiet --force-reinstall --no-deps "numpy<2.0" 2>/dev/null

    # Sobe ComfyUI direto com o venv (sem passar pelo /start.sh)
    # Mata qualquer processo ComfyUI travado na porta 8188 de uma execucao anterior
    pkill -f "main.py --listen" 2>/dev/null
    sleep 2

    echo "Iniciando ComfyUI direto pelo venv (bypass /start.sh)..."
    cd "$COMFYUI_DIR" || exit 1
    exec "$PY" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header '*'
fi

# Fallback: template hearmeman ou similar
if [ -f /start.sh ] && grep -q "ComfyUI" /start.sh 2>/dev/null; then
    echo "Detectado /start.sh do template — delegando a ele"
    exec /bin/bash /start.sh
fi

# Pod base (sem entrypoint próprio)
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
"$PY" -c "import sageattention" 2>/dev/null && ATTENTION_FLAG="--use-sage-attention"

exec "$PY" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header '*' $ATTENTION_FLAG
