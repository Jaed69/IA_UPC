# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure project to serve Google Gemma models locally with an OpenAI-compatible API. Two backends are wired:

- **Ollama** (primary, dev on laptop) — llama.cpp + GGUF, native CPU/GPU offload, ideal for ≤8GB VRAM.
- **vLLM** (reference, prod / GPUs ≥16GB VRAM) — server-grade engine, kept for future deployments on bigger GPUs.

All configuration is file-driven; there is no custom application code.

## Environment Setup

```bash
cp .env.example .env   # then trim to the section of the backend you'll use
```

`make dev` and `make vllm-dev` overwrite `.env` from the matching `.env.ollama` / `.env.dev` profile, so manual edits are only needed for `prod-*` targets.

Required variables per backend:
- **Ollama**: `OLLAMA_PORT`, `OLLAMA_MODEL`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_NUM_PARALLEL`
- **vLLM**: `HF_TOKEN` (HuggingFace token with Gemma access), `MODEL_ID`, `GPU_COUNT`, `MAX_MODEL_LEN`, `VLLM_PORT`

## Common Commands

```bash
# Ollama (primary)
make dev          # Start Ollama with .env.ollama profile
make pull         # Pull the model defined in .env (OLLAMA_MODEL)
make ls           # List cached Ollama models
make shell        # Bash inside the Ollama container
make down         # Stop Ollama
make logs         # Tail Ollama logs

# vLLM (reference / bigger GPU)
make vllm-dev     # Start vLLM dev profile (gemma-4-E4B-it, needs ≥16GB VRAM in practice)
make vllm-large   # Start vLLM large profile (gemma-4-26B MoE INT4 + CPU offload)
make vllm-down    # Stop vLLM
make vllm-logs    # Tail vLLM logs

# Common
make status       # Show which backend/profile is active
make test-api     # Hit /v1/models on the active backend
make test-chat    # Send a test chat message to the active backend

# Production (vLLM + nginx)
make prod-up
make prod-down
make prod-logs
```

## Architecture

**Deployment profiles** — three Docker Compose files:
- `docker-compose.ollama.yml`: Ollama (dev primary)
- `docker-compose.yml`: vLLM dev stack (legacy on this laptop, kept for ≥16GB GPUs)
- `docker-compose.prod.yml`: vLLM + nginx prod stack

Profile selection is driven by copying a pre-made `.env.*` file: `make dev` → `.env.ollama`, `make vllm-dev` → `.env.dev`, `make vllm-large` → `.env.large`.

**Ollama container** (`ollama/ollama:latest`):
- OpenAI-compatible API at `:11434/v1`
- Mounts `./ollama_data:/root/.ollama` for model cache (kept in repo, gitignored)
- Healthcheck via `ollama list`
- GPU via CDI: `nvidia.com/gpu=all`

**vLLM container** (`vllm/vllm-openai:gemma4-cu130` for dev, `vllm/vllm-openai:v0.19.0-cu130` for prod):
- OpenAI-compatible API at `:8000/v1`
- Mounts `~/.cache/huggingface` for model cache (downloads on first run)
- Requires NVIDIA CDI / `nvidia-container-toolkit`

**Nginx (production only)**:
- Rate limiting: 10 req/s per IP, burst 20
- Long timeouts (300s) to accommodate inference latency
- Proxy buffering disabled for SSE streaming
- SSL/TLS template in `nginx/nginx.conf` (certs go in `nginx/certs/`, excluded from git)

**Model profiles**:

| Backend | Profile | Model | Notes |
|---------|---------|-------|-------|
| Ollama | (default) | `gemma4:e4b` | Q4 GGUF, ~5GB VRAM, partial CPU offload if needed |
| vLLM | `vllm-dev` | `google/gemma-4-E4B-it` | Multimodal Matformer; OOM on 8GB VRAM in practice |
| vLLM | `vllm-large` | `google/gemma-4-26B-A4B-it` | MoE INT4 + 8GB CPU offload, 4096 max context |

**Hardware note (this laptop)**: RTX 5060 Laptop, 8GB VRAM, 16GB RAM. vLLM with Gemma-4-E4B fails OOM here (the per-layer Matformer embedding alone tries to allocate ~5.25GB). Use Ollama for any local development.

**OpenAI client usage** (same SDK, only base_url and model name change):
```python
from openai import OpenAI

# Ollama
client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
client.chat.completions.create(model="gemma4:e4b", messages=[...])

# vLLM
client = OpenAI(base_url="http://localhost:8000/v1", api_key="none")
client.chat.completions.create(model="gemma", messages=[...])
```

## Key Files

| File | Role |
|------|------|
| `Makefile` | All task automation |
| `docker-compose.ollama.yml` | Ollama dev stack (primary) |
| `docker-compose.yml` | vLLM dev stack (reference) |
| `docker-compose.prod.yml` | vLLM + nginx prod stack |
| `.env.ollama` | Ollama profile preset |
| `.env.dev` / `.env.large` | vLLM profile presets |
| `.env.example` | Template with both backends |
| `ollama_data/` | Ollama model cache (gitignored, ~26GB) |
| `nginx/nginx.conf` | Reverse proxy config |
