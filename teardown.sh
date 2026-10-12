#!/usr/bin/env bash
set -e

echo "=== [1/3] Removendo Connectors e Flink Statements ==="
confluent connect cluster delete PostgresCdcSourceV2_Payments --force || true

echo "=== [2/3] Removendo Tópicos e ACLs ==="
confluent kafka topic delete desafio-customers || true
confluent kafka topic delete desafio-accounts || true
confluent kafka topic delete desafio-cards || true
confluent kafka topic delete desafio-merchants || true
confluent kafka topic delete desafio-transactions || true
confluent kafka topic delete desafio.fraud.detected || true

echo "=== [3/3] Removendo Service Accounts ==="
PRODUCER_ID=$(confluent iam service-account list -o json | jq -r '.[] | select(.name=="desafio-producer") | .id')
CONSUMER_ID=$(confluent iam service-account list -o json | jq -r '.[] | select(.name=="desafio-consumer") | .id')

[ -n "$PRODUCER_ID" ] && confluent iam service-account delete $PRODUCER_ID
[ -n "$CONSUMER_ID" ] && confluent iam service-account delete $CONSUMER_ID

echo "=== Teardown finalizado. Todos os recursos foram destruídos com sucesso. ==="