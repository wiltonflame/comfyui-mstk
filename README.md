# ComfyWill 🔥

**Bootstrap universal de ComfyUI para RunPod** — transforma qualquer pod ComfyUI (mesmo um totalmente zerado) em um ambiente de produção VFX com custom nodes e download seletivo de modelos, sem rebuild de Docker.

*by Wilton Matos — VFX Compositor & Pipeline Developer*

---

## ✨ O que é

Um conjunto de scripts que você passa no **Container Start Command** de qualquer pod ComfyUI no RunPod. No boot ele:

1. **Detecta a GPU** e ajusta `torch.compile` automaticamente (desabilita em Blackwell/sm_120 como RTX 5090 e RTX PRO 6000; mantém ativo em 4090/L40/A40).
2. **Instala os custom nodes** em primeiro plano (o ComfyUI precisa deles para subir).
3. **Baixa os modelos** que você escolher em segundo plano — sem travar o boot.
4. **Sobe o ComfyUI** em ~3-5 minutos. Os modelos vão "aparecendo" conforme baixam.

> **Funciona em pod zerado.** Não precisa de imagem Docker custom nem network volume. Aponte para qualquer imagem ComfyUI base, cole o comando, e pronto.

---

## 📁 Estrutura do projeto

```
comfyui-mstk/
├── base_init.sh              # Script universal de inicialização
├── README.md                 # Este arquivo
└── models/
    ├── wan.sh                # Família Wan: T2V, I2V, Animate, VACE
    ├── ltx.sh                # LTX 2.3 full bf16 + IC-LoRAs + Creative Lab
    └── videoinpainting.sh    # ProPainter + DiffuEraser + OmnimatteZero
```

### Função de cada script

| Script | O que faz |
|---|---|
| **base_init.sh** | Orquestrador. Detecta GPU + ComfyUI, instala nodes, dispara o download do modelo escolhido, sobe o ComfyUI. É o único que você chama. |
| **models/wan.sh** | Baixa a família Wan. Controlado por `WAN_PARTS` (escolhe T2V/I2V/Animate/VACE). |
| **models/ltx.sh** | Baixa o LTX 2.3 completo bf16 (46GB) + todos os IC-LoRAs oficiais e Creative Lab. Para GPUs 48GB+. |
| **models/videoinpainting.sh** | Pré-baixa pesos de ProPainter, DiffuEraser e OmnimatteZero para remoção de objetos/inpainting. |

---

## 🚀 Uso rápido

No campo **Container Start Command** do template/pod RunPod, cole **um** dos comandos abaixo.

### Família Wan (com sub-flags)

```bash
# Só Image-to-Video
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=wan WAN_PARTS=i2v bash"

# Image-to-Video + Animate
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=wan WAN_PARTS=i2v,animate bash"

# Tudo da família Wan (~150GB+)
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=wan bash"
```

Partes válidas em `WAN_PARTS`: `t2v`, `i2v`, `animate`, `vace` (vírgula, sem espaços).

### LTX 2.3 (full bf16)

```bash
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=ltx bash"
```

### Video Inpainting

```bash
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | MODEL=videoinpainting bash"
```

### Só os nodes (sem baixar modelo)

```bash
bash -c "curl -fsSL https://raw.githubusercontent.com/wiltonflame/comfyui-mstk/main/base_init.sh | bash"
```

---

## ⚙️ Variáveis de ambiente

Você pode passar inline no comando (como acima) **ou** definir nas Environment Variables do template.

| Variável | Valores | Default | Função |
|---|---|---|---|
| `MODEL` | `wan` `ltx` `videoinpainting` | *(vazio)* | Pacote de modelos a baixar |
| `WAN_PARTS` | `t2v,i2v,animate,vace` | `all` | Sub-partes do Wan |
| `SKIP_NODES` | `1` | *(off)* | Pula instalação de nodes (só baixa modelos) |
| `REPO` | URL | repo do Wilton | Permite usar um fork |
| `OPENCV_IO_ENABLE_OPENEXR` | `1` | — | **Defina no template** para escrita de EXR linear (HDR) |

> `TORCH_COMPILE_DISABLE` **não precisa** ser definido — o `base_init.sh` detecta a GPU e ajusta sozinho.

---

## 🖥️ Configuração do pod no RunPod

| Campo | Recomendação |
|---|---|
| **Container image** | Qualquer imagem ComfyUI (ex: `hearmeman/comfyui-wan-template:v22`, ou uma imagem ComfyUI base) |
| **Container disk** | 50 GB (com network volume) · 150-450 GB (ephemeral, conforme o modelo) |
| **HTTP Ports** | `8188` (ComfyUI) · `8888` (JupyterLab) |
| **Env var** | `OPENCV_IO_ENABLE_OPENEXR=1` |
| **Start Command** | um dos comandos da seção acima |

### Compatibilidade de GPU

| GPU | torch.compile | SageAttention | Triton |
|---|---|---|---|
| RTX 4090 (sm_89) | ✅ ativo | ✅ | ✅ |
| L40 / L40S (sm_89) | ✅ ativo | ✅ | ✅ |
| A40 (sm_86) | ✅ ativo | ✅ | ✅ |
| RTX 5090 (sm_120) | ❌ auto-off | ✅ | ❌ |
| RTX PRO 6000 (sm_120) | ❌ auto-off | ✅ | ❌ |

A detecção de Blackwell e o desligamento do `torch.compile` previnem o erro `CUDA driver error: device kernel image is invalid` do Triton.

---

## 📥 Acompanhando o progresso

No **JupyterLab** (porta 8888), abra um terminal:

```bash
# Download dos modelos em segundo plano
tail -f /tmp/model_download.log

# Log geral do ComfyUI
tail -f /comfyui_*_nohup.log   # template hearmeman
# ou
tail -f /tmp/jupyter.log        # pod base
```

Sinais de que está pronto, na ordem:
```
GPU SM Capability: sm_XXX
Custom nodes prontos
Download rodando em background
... ComfyUI is UP / Starting server na porta 8188
```

---

## 🛠️ Troubleshooting

| Sintoma | Causa | Solução |
|---|---|---|
| `curl: 404` no boot | Repositório privado | Settings → Change visibility → **Public** |
| ComfyUI não abre, reinicia em loop | Erro no script | Suba sem Start Command, rode o curl manual no JupyterLab para ver o erro |
| Modelo não aparece no workflow | Ainda baixando | `tail -f /tmp/model_download.log` |
| Node com `IMPORT FAILED` | Requirement faltando | ComfyUI Manager → Install missing custom nodes → Try fix |
| Erro Triton em 5090/PRO 6000 | `torch.compile` | Já tratado automaticamente — confira `sm_120` no log |

---

## 🔄 Atualizando

Edite qualquer script direto no GitHub (lápis ✏️ → Commit). **Não precisa rebuildar nada** — o próximo pod que você subir já baixa a versão nova via `curl`. O GitHub é a fonte da verdade.

---

## 📦 Custom nodes incluídos

WanVideoWrapper · WanAnimatePreprocess · KJNodes · VideoHelperSuite · LTXVideo · BFSNodes · SeedVR2 · ProPainter · DiffuEraser · OmnimatteZero · cotracker · LanPaint · Inpaint-CropAndStitch · GGUF · MiniMax-bmo · radiance · Crystools · MTB · Custom-Scripts · batch_image_loader · Memory_Cleanup · Blender · SUPIR · Nvidia RTX Nodes · rgthree · ComfyUI-Manager

---

*Uso pessoal — pipeline VFX e geração de vídeo com IA.*
