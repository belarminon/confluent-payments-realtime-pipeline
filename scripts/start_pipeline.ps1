# Script de validação de ambiente, verificação do Docker e inicialização do Postgres + Confluent Pipeline

Write-Host "=== Pipeline Real-Time Payments (Confluent + Postgres) ===" -ForegroundColor Cyan

# 1. Função de Verificação de Portas
function Test-PortInUse ($port) {
    try {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conns) { return $true }
    } catch {}

    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        $listener.Start()
        $listener.Stop()
        return $false
    } catch {
        return $true
    }
}

$defaultPort = 5432
$postgresPort = $defaultPort
if (Test-PortInUse $postgresPort) {
    Write-Host "  [AVISO] A porta $defaultPort do PostgreSQL esta em uso. Buscando uma porta livre..." -ForegroundColor Yellow
    while (Test-PortInUse $postgresPort) { $postgresPort++ }
    Write-Host "  [OK] PostgreSQL redirecionado para a porta $postgresPort." -ForegroundColor Green
} else {
    Write-Host "  [OK] Porta $postgresPort (PostgreSQL) disponivel." -ForegroundColor Green
}

# 2. Gestão do Ficheiro .env
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }
$rootDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$envPath = Join-Path $rootDir ".env"
$envExamplePath = Join-Path $rootDir ".env.example"

if (-not (Test-Path $envPath)) {
    if (Test-Path $envExamplePath) {
        Copy-Item $envExamplePath $envPath
        Write-Host "Ficheiro .env criado a partir do .env.example." -ForegroundColor Yellow
    } else {
        Write-Host "Erro: Ficheiro .env.example nao encontrado na raiz." -ForegroundColor Red
        exit 1
    }
}

# Atualiza POSTGRES_PORT no .env
$envContent = Get-Content $envPath
if ($envContent -match "^POSTGRES_PORT=") {
    $envContent = $envContent -replace "^POSTGRES_PORT=.*", "POSTGRES_PORT=$postgresPort"
} else {
    $envContent += "POSTGRES_PORT=$postgresPort"
}
Set-Content -Path $envPath -Value $envContent -Encoding UTF8

# 3. Verificação e Inicialização do Docker Engine
Write-Host "A verificar status do Docker Engine..." -ForegroundColor Cyan
$dockerReady = $false
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
} catch {}

if (-not $dockerReady) {
    Write-Host "Docker Daemon nao esta ativo. A iniciar o Docker Desktop..." -ForegroundColor Yellow
    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    
    if (Test-Path $dockerPath) {
        Start-Process $dockerPath
    } else {
        Write-Host "Erro: Docker Desktop nao encontrado em $dockerPath. Inicie-o manualmente." -ForegroundColor Red
        exit 1
    }

    Write-Host "A aguardar inicializacao do Docker..." -ForegroundColor Yellow
    $timeout = 60
    $elapsed = 0
    while (-not $dockerReady -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        try {
            docker info > $null 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerReady = $true }
        } catch {}
        Write-Host "." -NoNewline
    }
    Write-Host ""
}

if (-not $dockerReady) {
    Write-Host "Erro: Tempo limite excedido a aguardar pelo Docker." -ForegroundColor Red
    exit 1
}

# 4. Iniciar Container do Postgres e aguardar Healthcheck
Write-Host "Docker ativo! A subir o container do PostgreSQL..." -ForegroundColor Green
docker compose up -d postgres

Write-Host "A aguardar o PostgreSQL ficar PRONTO (Healthcheck)..." -ForegroundColor Yellow
$pgReady = $false
$elapsed = 0
while (-not $pgReady -and $elapsed -lt 30) {
    $status = docker inspect --format='{{json .State.Health.Status}}' payments-postgres 2>$null
    if ($status -eq '"healthy"') {
        $pgReady = $true
        break
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
    Write-Host "." -NoNewline
}
Write-Host ""

if ($pgReady) {
    Write-Host "PostgreSQL operacional na porta $postgresPort!" -ForegroundColor Green
    Write-Host "A executar o setup.sh no Confluent Cloud..." -ForegroundColor Cyan
    
    # Executa o setup.sh via Bash (Git Bash ou WSL se disponível no Windows)
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        bash "$rootDir\setup.sh"
    } else {
        Write-Host "Aviso: Git Bash/WSL nao detectado para rodar o setup.sh automaticamente." -ForegroundColor Yellow
        Write-Host "Por favor, execute o ./setup.sh manualmente num terminal Bash." -ForegroundColor Cyan
    }
} else {
    Write-Host "Erro: PostgreSQL nao inicializou a tempo." -ForegroundColor Red
    exit 1
}