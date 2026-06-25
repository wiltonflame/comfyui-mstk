#!/usr/bin/env bash

# Detecta GPU e desabilita torch.compile em Blackwell
SM=$(python3 -c "
import torch
cap = torch.cuda.get_device_capability()
print(cap[0]*10 + cap[1])
" 2>/dev/null || echo "0")

echo "GPU SM: $SM"
if [ "$SM" -ge 100 ]; then
    export TORCH_COMPILE_DISABLE=1
    echo "Blackwell detectado — torch.compile desabilitado"
fi

# Roda o start original do template
exec /bin/bash /start_original.sh
