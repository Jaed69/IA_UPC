# IA UPC — Servidor local de inferencia Gemma

Infraestructura para servir modelos **Google Gemma** localmente y en producción, con una API 100% compatible con OpenAI. Dos backends disponibles según el hardware:

| Backend | Cuándo usarlo | Puerto por defecto |
|---------|--------------|-------------------|
| **Ollama** | Laptop / GPU ≤8 GB VRAM | `11434` |
| **vLLM** | Servidor / GPU ≥16 GB VRAM | `8000` |

---

## Arquitectura

```
┌────────────────────────────────────────────────────────────┐
│                    DEV — Laptop (8GB VRAM)                  │
│                                                            │
│   make dev                                                 │
│        │                                                   │
│        ▼                                                   │
│  ┌───────────────┐                                         │
│  │ Ollama        │  :11434/v1  ← API OpenAI-compatible     │
│  │ (llama.cpp)   │                                         │
│  │ GPU + CPU     │  offload automático CPU/GPU             │
│  │ offload       │  (gemma4:e4b = 68% CPU / 32% GPU)       │
│  └───────────────┘                                         │
│        │                                                   │
│  ./ollama_data/   ← modelos GGUF cacheados localmente      │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│              PRODUCCIÓN — Servidor (≥16 GB VRAM)            │
│                                                            │
│  Internet                                                  │
│     │  HTTPS :443                                          │
│     ▼                                                      │
│  ┌────────┐   proxy   ┌──────────────────────┐            │
│  │ nginx  │ ────────► │ vLLM                 │            │
│  │        │   :8000   │ (OpenAI-compatible)  │            │
│  │ rate   │           │ gpu_memory_util 0.95 │            │
│  │ limit  │           │ bitsandbytes INT4    │            │
│  └────────┘           └──────────────────────┘            │
│                              │                             │
│                    ~/.cache/huggingface/  ← pesos del modelo│
└────────────────────────────────────────────────────────────┘
```

---

## Desarrollo local (Ollama)

### Requisitos

- Docker + Docker Compose
- Drivers NVIDIA instalados + [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- GPU con soporte CUDA (funciona desde 4 GB VRAM con offload a CPU)

### Arrancar

```bash
# 1. Levantar el contenedor Ollama
make dev

# 2. Si es la primera vez (modelo no descargado):
make pull          # descarga gemma4:e4b (~9.6 GB)

# 3. Verificar que el servidor responde
make test-api      # lista los modelos disponibles
make test-chat     # envía un mensaje de prueba
```

El modelo por defecto es `gemma4:e4b` definido en `.env.ollama`. Para cambiar de modelo, edita `OLLAMA_MODEL` en ese archivo y vuelve a hacer `make dev && make pull`.

### Comandos útiles

```bash
make logs          # ver logs en tiempo real
make ls            # listar modelos descargados
make down          # apagar
make shell         # shell bash dentro del contenedor

# en el shell puedes correr:
# ollama list
# ollama run gemma4:e4b
# ollama rm gemma4:26b
```

### Modelos disponibles en Ollama

| Modelo | Tamaño disco | VRAM (con offload) |
|--------|-------------|-------------------|
| `gemma4:e4b` | 9.6 GB | ~3.4 GB GPU + RAM |
| `gemma4:26b` | 17 GB | más CPU offload |
| `gemma2:2b` | ~1.8 GB | entra entero en 4 GB VRAM |

---

## Usar la API

La API es 100% compatible con OpenAI. Cambia solo la `base_url` y el nombre del modelo.

### Curl (rápido)

```bash
# Listar modelos
curl http://localhost:11434/v1/models

# Chat completion
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma4:e4b",
    "messages": [{"role": "user", "content": "Explica qué es una red neuronal"}],
    "max_tokens": 200
  }'
```

### Python (SDK openai)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",            # Ollama ignora el valor, pero el SDK lo exige
)

response = client.chat.completions.create(
    model="gemma4:e4b",
    messages=[
        {"role": "system", "content": "Eres un asistente conciso."},
        {"role": "user", "content": "Explica qué es una red neuronal"},
    ],
    max_tokens=300,
)
print(response.choices[0].message.content)
```

### Streaming

```python
stream = client.chat.completions.create(
    model="gemma4:e4b",
    messages=[{"role": "user", "content": "Cuenta hasta 10 lentamente"}],
    stream=True,
)
for chunk in stream:
    print(chunk.choices[0].delta.content or "", end="", flush=True)
```

> **Nota Gemma 4:** Este modelo incluye un paso de "razonamiento" antes de la respuesta final. Si usas `max_tokens` muy bajo (<100), los tokens se consumen en la fase de razonamiento y el contenido visible puede quedar vacío. Usa al menos 200 tokens para respuestas normales.

---

## Despliegue en servidor (producción)

Este stack usa **vLLM + nginx** y requiere una GPU con ≥16 GB VRAM.

### Requisitos en el servidor

- Ubuntu 22.04 / Debian 12 (o similar)
- Docker + Docker Compose
- Drivers NVIDIA + nvidia-container-toolkit
- Cuenta HuggingFace con acceso a Gemma (acepta la licencia en [hf.co/google/gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it))
- Dominio con DNS apuntando al servidor (para HTTPS)

### Pasos

```bash
# 1. Copiar el repositorio al servidor
scp -r . usuario@ip-servidor:~/ia-upc/
# o clonar si está en GitHub:
# git clone https://github.com/tu-usuario/ia-upc.git && cd ia-upc

# 2. Configurar variables de entorno
ssh usuario@ip-servidor
cd ~/ia-upc

cp .env.example .env
nano .env                # añade HF_TOKEN, MODEL_ID, VLLM_API_KEY (una contraseña fuerte)

# 3. (Opcional) Configurar HTTPS
# Coloca tus certificados en nginx/certs/:
#   nginx/certs/server.crt
#   nginx/certs/server.key
# Luego descomenta el bloque SSL en nginx/nginx.conf

# 4. Levantar el stack
make prod-up

# El primer arranque descarga el modelo (~8-13 GB), puede tardar varios minutos.
make prod-logs           # seguir el progreso

# 5. Verificar
make test-api
make test-chat
```

### Conectarse al servidor desde otro equipo

Una vez en producción, la API es accesible desde cualquier cliente OpenAI:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://tu-dominio.com/v1",   # HTTP si no configuraste HTTPS
    api_key="tu-VLLM_API_KEY",              # el que pusiste en .env
)

response = client.chat.completions.create(
    model="gemma",                           # vLLM sirve el modelo como "gemma"
    messages=[{"role": "user", "content": "Hola"}],
)
print(response.choices[0].message.content)
```

Desde curl:

```bash
curl https://tu-dominio.com/v1/chat/completions \
  -H "Authorization: Bearer tu-VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma","messages":[{"role":"user","content":"Hola"}],"max_tokens":100}'
```

### Diferencias dev ↔ producción

| | Dev (Ollama) | Producción (vLLM + nginx) |
|---|---|---|
| Backend | Ollama (llama.cpp) | vLLM |
| Puerto | `11434` | `80`/`443` (vía nginx) |
| Nombre del modelo | `gemma4:e4b` | `gemma` |
| Autenticación | No | `VLLM_API_KEY` via nginx |
| HTTPS | No | Sí (nginx + certs) |
| Rate limiting | No | 10 req/s por IP |
| Hardware mínimo | 4 GB VRAM (con offload) | ≥16 GB VRAM |

---

## Archivos clave

| Archivo | Función |
|---------|---------|
| `docker-compose.ollama.yml` | Stack Ollama (dev) |
| `docker-compose.yml` | Stack vLLM (referencia) |
| `docker-compose.prod.yml` | Stack vLLM + nginx (producción) |
| `.env.ollama` | Configuración Ollama dev |
| `.env.dev` / `.env.large` | Perfiles vLLM |
| `.env.example` | Plantilla con ambos backends |
| `nginx/nginx.conf` | Proxy reverso, rate limiting, SSL |
| `Makefile` | Todos los comandos (`make help`) |

```bash
make help   # muestra todos los comandos disponibles
```
