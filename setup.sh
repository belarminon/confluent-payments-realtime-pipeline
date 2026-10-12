#!/usr/bin/env bash
set -e

echo "=== [1/4] Inicializando Setup da Fundação no Confluent Cloud ==="
source .env

confluent environment use ${CONFLUENT_ENVIRONMENT_ID}
confluent kafka cluster use ${CONFLUENT_CLUSTER_ID}

echo "=== [2/4] Criando Service Accounts e ACLs ==="
# Criar SA Produtor
PRODUCER_SA_ID=$(confluent iam service-account create desafio-producer --description "Producer SA for Payments CDC" -o json | jq -r '.id')
confluent kafka acl create --allow --service-account $PRODUCER_SA_ID --operation WRITE --prefix --topic-name "desafio-"

# Criar SA Consumidor
CONSUMER_SA_ID=$(confluent iam service-account create desafio-consumer --description "Consumer SA for Payments" -o json | jq -r '.id')
confluent kafka acl create --allow --service-account $CONSUMER_SA_ID --operation READ --prefix --topic-name "desafio-"
confluent kafka acl create --allow --service-account $CONSUMER_SA_ID --operation READ --prefix --consumer-group-name "desafio-"

echo "=== [3/4] Criando Tópicos do Pipeline ==="
confluent kafka topic create desafio-customers --partitions 3
confluent kafka topic create desafio-accounts --partitions 3
confluent kafka topic create desafio-cards --partitions 3
confluent kafka topic create desafio-merchants --partitions 3
confluent kafka topic create desafio-transactions --partitions 3
confluent kafka topic create desafio.fraud.detected --partitions 3

echo "=== [4/4] Ingestão CDC Iniciada ==="
confluent connect cluster create --config connectors/cdc-postgres-source.json

echo "=== Setup concluído com sucesso! ==="