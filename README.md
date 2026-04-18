# vLLM + Gemma — IA UPC

Servidor de inferencia local y en producción usando [vLLM](https://github.com/vllm-project/vllm) con modelos Gemma de Google.

## Requisitos

- Docker + Docker Compose
- NVIDIA GPU con drivers instalados
- [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- Cuenta en [HuggingFace](https://huggingface.co) con acceso a Gemma (acepta la licencia en hf.co/google/gemma-3-27b-it)

## Setup

```bash
# 1. Copia y configura variables de entorno
cp .env.example .env
# Edita .env y agrega tu HF_TOKEN y MODEL_ID

# 2. Levanta el servidor
make up

# 3. Verifica que funciona (espera ~1-2 min mientras carga el modelo)
make test-api
make test-chat
```

## Uso de la API

La API es compatible con OpenAI. Puedes usar cualquier cliente OpenAI apuntando a `http://localhost:8000`.

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="tu-VLLM_API_KEY-o-cualquier-string-si-no-configuraste",
)

response = client.chat.completions.create(
    model="gemma",
    messages=[{"role": "user", "content": "Explica qué es una red neuronal"}],
)
print(response.choices[0].message.content)
```

## Modelos recomendados (ajusta según tu VRAM)

| Modelo | VRAM aprox. |
|--------|------------|
| google/gemma-3-4b-it  | ~8 GB  |
| google/gemma-3-12b-it | ~24 GB |
| google/gemma-3-27b-it | ~48 GB |

## Deployment en servidor

```bash
# 1. Copia los archivos al servidor
scp -r . usuario@servidor:~/ia-upc/

# 2. En el servidor, configura .env con VLLM_API_KEY segura
ssh usuario@servidor
cd ~/ia-upc
cp .env.example .env && nano .env

# 3. Levanta con nginx
make prod-up
```

Para HTTPS, coloca tus certificados en `nginx/certs/` y descomenta el bloque SSL en `nginx/nginx.conf`.
