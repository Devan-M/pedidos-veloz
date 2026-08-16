# Stage 1: Build
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

# Criar usuário não-root
RUN useradd -m -u 1001 appuser

# Copiar dependências do builder
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local

# Copiar código
COPY --chown=appuser:appuser . .

# Trocar para usuário não-root
USER appuser

# Adicionar .local/bin ao PATH
ENV PATH=/home/appuser/.local/bin:$PATH

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:3002/health', timeout=5)"

EXPOSE 3002

CMD ["python", "src/app.py"]