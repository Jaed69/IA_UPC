.PHONY: dev down logs pull shell ls test-api test-chat status help \
        vllm-dev vllm-large vllm-down vllm-logs \
        prod-up prod-down prod-logs

# ── Desarrollo (Ollama — backend principal en laptop) ───────────────────────

dev: ## Ollama con OLLAMA_MODEL — perfil principal en laptop (8GB VRAM)
	cp .env.ollama .env
	docker compose -f docker-compose.ollama.yml up -d
	@echo "→ Ollama en http://localhost:$$(grep OLLAMA_PORT .env.ollama | cut -d= -f2)/v1 (OpenAI-compatible)"
	@echo "→ Modelo por defecto: $$(grep OLLAMA_MODEL .env.ollama | cut -d= -f2)"
	@echo "→ Si el modelo no está cacheado, ejecuta: make pull"

down: ## Apagar Ollama
	docker compose -f docker-compose.ollama.yml down

logs: ## Ver logs Ollama en tiempo real
	docker compose -f docker-compose.ollama.yml logs -f ollama

pull: ## Descargar el modelo definido en .env (OLLAMA_MODEL)
	@MODEL=$$(grep OLLAMA_MODEL .env | cut -d= -f2); \
	 echo "→ Descargando $$MODEL..."; \
	 docker exec ia-upc-ollama ollama pull $$MODEL

shell: ## Shell interactiva dentro del contenedor (corre `ollama list`, `ollama run`, etc.)
	docker exec -it ia-upc-ollama bash

ls: ## Listar modelos descargados en Ollama
	docker exec ia-upc-ollama ollama list

# ── Testing ──────────────────────────────────────────────────────────────────

# `pretty` formatea JSON con jq → python3 → raw, según lo que esté instalado
pretty = $$(command -v jq >/dev/null && echo "jq ." \
            || command -v python3 >/dev/null && echo "python3 -m json.tool" \
            || echo "cat")

test-api: ## Verificar que el servidor responde (lista modelos vía /v1/models)
	@curl -s http://localhost:$$(grep OLLAMA_PORT .env 2>/dev/null | cut -d= -f2 || echo 11434)/v1/models \
	  | $(pretty)

test-chat: ## Enviar mensaje de prueba al modelo activo
	@PORT=$$(grep OLLAMA_PORT .env 2>/dev/null | cut -d= -f2 || echo 11434); \
	 MODEL=$$(grep OLLAMA_MODEL .env 2>/dev/null | cut -d= -f2 || echo gemma4:e4b); \
	 RESP=$$(curl -s http://localhost:$$PORT/v1/chat/completions \
	   -H "Content-Type: application/json" \
	   -d "{\"model\":\"$$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Hola, presenta el modelo que eres en una línea\"}],\"max_tokens\":80}"); \
	 if command -v jq >/dev/null; then echo "$$RESP" | jq -r '.choices[0].message.content'; \
	 elif command -v python3 >/dev/null; then echo "$$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"; \
	 else echo "$$RESP"; fi

status: ## Ver qué backend/perfil está activo
	@if [ ! -f .env ]; then \
	  echo "Sin perfil activo. Usa: make dev  (Ollama)  o  make vllm-dev  (vLLM)"; \
	elif grep -q '^OLLAMA_' .env; then \
	  echo "Backend activo: OLLAMA"; \
	  grep -E "OLLAMA_MODEL|OLLAMA_PORT" .env; \
	else \
	  echo "Backend activo: vLLM"; \
	  grep -E "MODEL_ID|MAX_MODEL_LEN|EXTRA_VLLM_ARGS" .env; \
	fi

# ── vLLM (referencia / GPUs grandes) ────────────────────────────────────────

vllm-dev: ## vLLM gemma-4-E4B-it (requiere ≥16GB VRAM en la práctica)
	cp .env.dev .env
	docker compose up -d
	@echo "→ vLLM iniciando con perfil DEV ($(shell grep MODEL_ID .env.dev | cut -d= -f2))"

vllm-large: ## vLLM gemma-4-26B-A4B-it MoE INT4 + CPU offload
	cp .env.large .env
	docker compose up -d
	@echo "→ vLLM iniciando con perfil LARGE ($(shell grep MODEL_ID .env.large | cut -d= -f2))"

vllm-down: ## Apagar vLLM
	docker compose down

vllm-logs: ## Ver logs vLLM
	docker compose logs -f vllm-server

# ── Producción ───────────────────────────────────────────────────────────────

prod-up: ## Levantar stack vLLM + nginx (usar .env configurado manualmente)
	docker compose -f docker-compose.prod.yml up -d

prod-down:
	docker compose -f docker-compose.prod.yml down

prod-logs:
	docker compose -f docker-compose.prod.yml logs -f

help:
	@grep -E '^[a-zA-Z_-]+:.*## ' Makefile | awk 'BEGIN{FS=":.*## "}{printf "  %-12s %s\n", $$1, $$2}'
