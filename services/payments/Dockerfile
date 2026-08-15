# --- Estágio 1: Builder (Compilação/Dependências) ---
FROM python:3.11-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev postgresql-dev

# Cria o arquivo vazio via RUN caso ele não exista localmente, tornando a cópia sempre segura
COPY . .
RUN if [ ! -f requirements.txt ]; then touch requirements.txt; fi \
    && pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Estágio 2: Runtime (Imagem Final de Produção Mínima) ---
FROM python:3.11-alpine

WORKDIR /app

RUN apk add --no-cache libpq

# Copia apenas os artefatos compilados do estágio anterior (Multi-Stage Build)
COPY --from=builder /install /usr/local
COPY . .

# Prática de Segurança: Usuário não-root
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

CMD ["python", "-m", "http.server", "8000"]
