# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure project to deploy Google Gemma models locally via vLLM, exposing an OpenAI-compatible API. All configuration is file-driven — there is no custom application code.

## Environment Setup

Copy the appropriate env template before starting:
```bash
cp .env.example .env   # then fill in HF_TOKEN and other values
```

Required variables:
- `HF_TOKEN`: HuggingFace token with Gemma model access (mandatory)
- `MODEL_ID`, `GPU_COUNT`, `MAX_MODEL_LEN`, `VLLM_PORT` (default: 8000)

## Common Commands

```bash
make dev          # Start dev profile (gemma-4-E4B-it, ~8GB VRAM)
make large        # Start large profile (gemma-4-26B-A4B-it, INT4 + CPU offload)
make down         # Stop all containers
make status       # Show active profile and config
make logs         # Tail vllm-server logs

make test-api     # Verify server is up, list models
make test-chat    # Send a test chat message

make prod-up      # Start production stack (vLLM + nginx)
make prod-down    # Stop production stack
make prod-logs    # Tail production logs
```

## Architecture

**Deployment profiles** — two Docker Compose configurations:
- `docker-compose.yml`: dev stack (vLLM only, no auth, fast startup)
- `docker-compose.prod.yml`: prod stack (vLLM + nginx reverse proxy)

Profile selection is driven by copying a pre-made `.env.*` file: `make dev` copies `.env.dev`, `make large` copies `.env.large`.

**vLLM container** (`vllm/vllm-openai:v0.19.0-cu130`):
- Serves OpenAI-compatible API at `/v1`
- Mounts `~/.cache/huggingface` for model caching (models are downloaded on first run)
- Requires `nvidia` runtime and `nvidia-container-toolkit` on the host

**Nginx (production only)**:
- Rate limiting: 10 req/s per IP, burst 20
- Long timeouts (300s) to accommodate inference latency
- Proxy buffering disabled for SSE streaming
- SSL/TLS template in `nginx/nginx.conf` (certs go in `nginx/certs/`, excluded from git)

**Model profiles**:

| Profile | Model | VRAM | Notes |
|---------|-------|------|-------|
| dev | google/gemma-4-E4B-it | ~8GB | No quantization, fast startup |
| large | google/gemma-4-26B-A4B-it | Lower | INT4 + 8GB CPU offload, 4096 max context |

**OpenAI client usage** (standard SDK, no custom client):
```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8000/v1", api_key="none")
client.chat.completions.create(model="gemma", messages=[...])
```

## Key Files

| File | Role |
|------|------|
| `Makefile` | All task automation |
| `docker-compose.yml` | Dev container stack |
| `docker-compose.prod.yml` | Prod container stack (+ nginx) |
| `.env.dev` / `.env.large` | Profile-specific environment presets |
| `.env.example` | Template — copy to `.env` |
| `nginx/nginx.conf` | Reverse proxy config |
