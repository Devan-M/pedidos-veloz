# Script de Instalação - Pedidos Veloz (Windows)
# Este script instala todas as dependências e inicia os serviços

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Instalação - Pedidos Veloz" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se está rodando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "⚠️  Este script precisa ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito em PowerShell e selecione 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Passo 1: Verificar Git
Write-Host ""
Write-Host "1️⃣  Verificando Git..." -ForegroundColor Yellow
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = git --version
    Write-Host "✅ Git instalado: $gitVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Git não encontrado!" -ForegroundColor Red
    Write-Host "Baixe em: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Passo 2: Verificar Docker
Write-Host ""
Write-Host "2️⃣  Verificando Docker..." -ForegroundColor Yellow
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVersion = docker --version
    Write-Host "✅ Docker instalado: $dockerVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Docker não encontrado!" -ForegroundColor Red
    Write-Host "Baixe em: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}

# Passo 3: Verificar Docker Compose
Write-Host ""
Write-Host "3️⃣  Verificando Docker Compose..." -ForegroundColor Yellow
if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    $composeVersion = docker-compose --version
    Write-Host "✅ Docker Compose instalado: $composeVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Docker Compose não encontrado!" -ForegroundColor Red
    exit 1
}

# Passo 4: Verificar Docker Desktop rodando
Write-Host ""
Write-Host "4️⃣  Verificando Docker Desktop..." -ForegroundColor Yellow
try {
    docker ps > $null 2>&1
    Write-Host "✅ Docker Desktop está rodando" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker Desktop não está rodando!" -ForegroundColor Red
    Write-Host "Abra Docker Desktop e tente novamente" -ForegroundColor Yellow
    exit 1
}

# Passo 5: Criar arquivo .env
Write-Host ""
Write-Host "5️⃣  Criando arquivo .env..." -ForegroundColor Yellow
if (Test-Path ".env") {
    Write-Host "✅ Arquivo .env já existe" -ForegroundColor Green
} else {
    Copy-Item ".env.example" ".env"
    Write-Host "✅ Arquivo .env criado" -ForegroundColor Green
}

# Passo 6: Build das imagens
Write-Host ""
Write-Host "6️⃣  Construindo imagens Docker..." -ForegroundColor Yellow
Write-Host "⏳ Isso pode levar 5-10 minutos na primeira vez..." -ForegroundColor Cyan
docker-compose build
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Imagens construídas com sucesso" -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao construir imagens" -ForegroundColor Red
    exit 1
}

# Passo 7: Iniciar serviços
Write-Host ""
Write-Host "7️⃣  Iniciando serviços..." -ForegroundColor Yellow
docker-compose up -d
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Serviços iniciados" -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao iniciar serviços" -ForegroundColor Red
    exit 1
}

# Passo 8: Aguardar serviços ficarem prontos
Write-Host ""
Write-Host "8️⃣  Aguardando serviços ficarem prontos..." -ForegroundColor Yellow
Write-Host "⏳ Aguardando 30 segundos..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

# Passo 9: Verificar status
Write-Host ""
Write-Host "9️⃣  Verificando status dos serviços..." -ForegroundColor Yellow
docker-compose ps

# Passo 10: Testar Health Check
Write-Host ""
Write-Host "🔟 Testando Health Check..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ API Gateway respondendo" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️  API Gateway ainda não está respondendo (pode levar mais tempo)" -ForegroundColor Yellow
}

# Resumo Final
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ Instalação Concluída!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Serviços disponíveis:" -ForegroundColor Yellow
Write-Host "  • API Gateway: http://localhost:8080" -ForegroundColor Cyan
Write-Host "  • Grafana: http://localhost:3000 (admin/CHANGE_ME)" -ForegroundColor Cyan
Write-Host "  • Prometheus: http://localhost:9090" -ForegroundColor Cyan
Write-Host "  • RabbitMQ: http://localhost:15672 (CHANGE_ME/CHANGE_ME)" -ForegroundColor Cyan
Write-Host ""
Write-Host "📝 Próximos passos:" -ForegroundColor Yellow
Write-Host "  1. Abra http://localhost:3000 no navegador" -ForegroundColor Cyan
Write-Host "  2. Teste a API com: curl http://localhost:8080/health" -ForegroundColor Cyan
Write-Host "  3. Para parar: docker-compose down" -ForegroundColor Cyan
Write-Host ""
Write-Host "📚 Documentação:" -ForegroundColor Yellow
Write-Host "  • README.md - Visão geral do projeto" -ForegroundColor Cyan
Write-Host "  • docs/ARCHITECTURE.md - Arquitetura" -ForegroundColor Cyan
Write-Host "  • docs/DEPLOYMENT.md - Deploy" -ForegroundColor Cyan
Write-Host "  • docs/OBSERVABILITY.md - Monitoramento" -ForegroundColor Cyan
Write-Host "  • docs/SCALING.md - Escalabilidade" -ForegroundColor Cyan
Write-Host ""