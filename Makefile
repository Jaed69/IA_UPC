.PHONY: dev large down logs test-api test-chat prod-up prod-down prod-logs help

# ── Desarrollo ──────────────────────────────────────────────────────────────

dev: ## gemma-4-E4B-it | rápido, cabe en 8GB VRAM sin ajustes
	cp .env.dev .env
	docker compose up -d
	@echo "→ Servidor iniciando con perfil DEV ($(shell grep MODEL_ID .env.dev | cut -d= -f2))"
	@echo "→ Logs: make logs | Test: make test-chat"

large: ## gemma-4-26B-A4B-it | MoE INT4 + CPU offload (lento al arrancar)
	cp .env.large .env
	docker compose up -d
	@echo "→ Servidor iniciando con perfil LARGE ($(shell grep MODEL_ID .env.large | cut -d= -f2))"
	@echo "→ Primera vez: descarga ~13GB, espera 5-10 min"

down: ## Apagar servidor
	docker compose down

logs: ## Ver logs en tiempo real
	docker compose logs -f vllm-server

# ── Producción ───────────────────────────────────────────────────────────────

prod-up: ## Levantar con nginx (usar .env configurado manualmente)
	docker compose -f docker-compose.prod.yml up -d

prod-down:
	docker compose -f docker-compose.prod.yml down

prod-logs:
	docker compose -f docker-compose.prod.yml logs -f

# ── Testing ──────────────────────────────────────────────────────────────────

test-api: ## Verificar que el servidor responde
	@curl -s http://localhost:$$(grep VLLM_PORT .env 2>/dev/null | cut -d= -f2 || echo 8000)/v1/models \
	  | python3 -m json.tool

test-chat: ## Enviar mensaje de prueba
	@PORT=$$(grep VLLM_PORT .env 2>/dev/null | cut -d= -f2 || echo 8000); \
	 KEY=$$(grep VLLM_API_KEY .env 2>/dev/null | cut -d= -f2); \
	 AUTH=$$([ -n "$$KEY" ] && echo "-H \"Authorization: Bearer $$KEY\"" || echo ""); \
	 curl -s $$AUTH http://localhost:$$PORT/v1/chat/completions \
	   -H "Content-Type: application/json" \
	   -d '{"model":"gemma","messages":[{"role":"user","content":"Hola, presenta el modelo que eres en una línea"}],"max_tokens":80}' \
	   | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])"

status: ## Ver qué perfil está activo
	@if [ -f .env ]; then \
	  echo "Perfil activo:"; \
	  grep -E "MODEL_ID|MAX_MODEL_LEN|EXTRA_VLLM_ARGS" .env; \
	else \
	  echo "Sin perfil activo. Usa: make dev  o  make large"; \
	fi

help:
	@grep -E '^[a-zA-Z_-]+:.*## ' Makefile | awk 'BEGIN{FS=":.*## "}{printf "  %-12s %s\n", $$1, $$2}'
