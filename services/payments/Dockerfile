# --- Estágio 1: Builder (Compilação/Dependências) ---
FROM python:3.11-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev postgresql-dev

COPY requirements.txt . 2>/dev/null || touch requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Estágio 2: Runtime (Imagem Final de Produção Mínima) ---
FROM python:3.11-alpine

WORKDIR /app

RUN apk add --no-cache libpq

# Copia apenas os artefatos compilados do estágio anterior (Redução de Camadas e Tamanho)
COPY --from=builder /install /usr/local
COPY . .

# Prática de Segurança: Cria e define usuário não-root (Evita privilégios elevados caso o container seja invadido)
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

CMD ["python", "-m", "http.server", "8000"]
