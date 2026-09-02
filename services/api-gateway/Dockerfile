# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copiar package files
COPY package*.json ./

# Instalar dependências
RUN npm ci --omit=dev && \
    npm cache clean --force

# Stage 2: Runtime
FROM node:20-alpine

WORKDIR /app

# Criar usuário não-root
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copiar node_modules do builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copiar código da aplicação
COPY --chown=nodejs:nodejs . .

# Trocar para usuário não-root
USER nodejs

EXPOSE 8080

CMD ["node", "--import", "./instrumentation.mjs", "src/index.js"]