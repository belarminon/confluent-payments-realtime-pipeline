#!/usr/bin/env bash
set -e

echo "=== [0/5] Verificando Docker e PostgreSQL Local ==="

# 1. Cria o .env se não existir
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "Ficheiro .env criado a partir do .env.example!"
        # Substitui host, porta e senha padrão para o Postgres local
        sed -i 's|POSTGRES_HOST=.*|POSTGRES_HOST="localhost"|g' .env
        sed -i 's|POSTGRES_PORT=.*|POSTGRES_PORT="5433"|g' .env
        sed -i 's|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD="cdc_password_123"|g' .env
    else
        echo "Erro: .env.example não encontrado!"
        exit 1
    fi
fi

source .env

# 1.1 Verifica se o Docker Daemon está ativo
if ! docker info > /dev/null 2>&1; then
    echo "Docker Daemon não está em execução."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "A iniciar o Docker Desktop no macOS..."
        open -a Docker
    elif command -v systemctl > /dev/null 2>&1; then
        echo "A iniciar o serviço Docker no Linux..."
        sudo systemctl start docker
    else
        echo "Erro: Por favor, inicie o Docker manualmente."
        exit 1
    fi

    echo -n "A aguardar a inicialização do Docker"
    TIMEOUT=60
    ELAPSED=0
    while ! docker info > /dev/null 2>&1; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo ""
            echo "Erro: Tempo limite excedido aguardando o Docker."
            exit 1
        fi
        echo -n "."
    done
    echo ""
fi

# 2. Sobe o container do PostgreSQL via Docker Compose
echo "A iniciar container do PostgreSQL..."
docker compose up -d postgres-confluent

# 3. Aguarda o Healthcheck do Postgres
echo -n "A aguardar o PostgreSQL ficar pronto"
until [ "$(docker inspect --format='{{json .State.Health.Status}}' confluent-payments-postgres 2>/dev/null)" == '"healthy"' ]; do
    sleep 2
    echo -n "."
done
echo ""
echo "PostgreSQL pronto e operacional!"

# ---------------------------------------------------------
# ETAPAS CONFLUENT CLOUD
# ---------------------------------------------------------

echo "=== [1/5] Inicializando Setup da Fundação no Confluent Cloud ==="
if [ -f .env ]; then
    source .env
else
    echo "Erro: Ficheiro .env não encontrado."
    exit 1
fi

confluent environment use ${CONFLUENT_ENVIRONMENT_ID}
confluent kafka cluster use ${CONFLUENT_CLUSTER_ID}

echo "=== [2/5] Criando Service Accounts e ACLs ==="
PRODUCER_SA_ID=$(confluent iam service-account create desafio-producer --description "Producer SA for Payments CDC" -o json | jq -r '.id')
confluent kafka acl create --allow --service-account $PRODUCER_SA_ID --operation WRITE --prefix --topic-name "desafio-"

CONSUMER_SA_ID=$(confluent iam service-account create desafio-consumer --description "Consumer SA for Payments" -o json | jq -r '.id')
confluent kafka acl create --allow --service-account $CONSUMER_SA_ID --operation READ --prefix --topic-name "desafio-"
confluent kafka acl create --allow --service-account $CONSUMER_SA_ID --operation READ --prefix --consumer-group-name "desafio-"

echo "=== [3/5] Criando Tópicos do Pipeline ==="
confluent kafka topic create desafio-customers --partitions 3
confluent kafka topic create desafio-accounts --partitions 3
confluent kafka topic create desafio-cards --partitions 3
confluent kafka topic create desafio-merchants --partitions 3
confluent kafka topic create desafio-transactions --partitions 3
confluent kafka topic create desafio.fraud.detected --partitions 3

echo "=== [4/5] Ingestão CDC Iniciada ==="
confluent connect cluster create --config connectors/cdc-postgres-source.json

echo "=== Setup do Pipeline e Infraestrutura concluído com sucesso! ==="