# ⚡ Pipeline Real-Time End-to-End com Confluent Cloud & Flink SQL

Este repositório contém a arquitetura completa e a implementação de um pipeline de detecção de fraudes em pagamentos em tempo real. Os dados são capturados via CDC de uma base Postgres (Neon), transmitidos via Confluent Cloud em formato Avro com esquemas governados, processados com janelas temporais de velocidade via Flink SQL e publicados em tópicos de alerta.

## 🏗️ Arquitetura do Sistema

```
[Postgres (Neon)] 
       │ (CDC via Debezium)
       ▼
[Confluent Cloud: Topics Avro + Schema Registry]
       │
       ▼
[Flink SQL: Temporal Join + MATCH_RECOGNIZE]
       │
       ▼
[Tópico: desafio.fraud.detected] ──► [Consumer / Alert System]

```

## 🛠️ Tecnologias Utilizadas

* **Linguagem / CLI:** Python 3.10+, Bash CLI, Confluent CLI

* **Streaming & Governance:** Confluent Cloud, Kafka, Schema Registry (Avro)

* **Stream Processing:** Flink SQL

* **Database & CDC:** PostgreSQL (Neon), Debezium CDC Connector (`PostgresCdcSourceV2`)

## 📋 Pré-requisitos

1. Conta na **Confluent Cloud** ativada.

2. **Confluent CLI** instalado (`confluent v3.x+`).

3. **Python 3.10+** e `pip` instalados.

4. Instância do **PostgreSQL (Neon)** configurada e acessível via rede.

## 🔧 Configuração e Instalação

1. **Clonar o repositório:**

   ```
   git clone https://github.com/belarminon/confluent-payments-realtime-pipeline.git
   cd confluent-payments-realtime-pipeline
   
   ```

2. **Criar e ativar o ambiente virtual Python:**

   ```
   python -m venv .venv
   # No Linux/macOS:
   source .venv/bin/activate
   # No Windows:
   .venv\Scripts\activate
   
   ```

3. **Instalar as dependências:**

   ```
   pip install -r requirements.txt
   
   ```

4. **Configurar as Variáveis de Ambiente:**
   Copie o arquivo `.env.example` para `.env` e preencha com as suas credenciais:

   ```
   cp .env.example .env
   
   ```

## 📌 Camada 1 — Fundação: Environment, Cluster e Segurança

### Configuração

* **Environment:** `desafio-final`

* **Cluster:** `desafio-basic` (`aws/us-east-1`)

* **Identidades:**

  * `desafio-producer`: Permissão `WRITE` apenas em tópicos prefixados com `desafio-`.

  * `desafio-consumer`: Permissão `READ` em tópicos e grupos de consumo prefixados com `desafio-`.

### Evidência de Execução

```
$ confluent iam service-account list
+--------+------------------+------------------------------------+
|   ID   |       NAME       |            DESCRIPTION             |
+--------+------------------+------------------------------------+
| 849201 | desafio-producer | Producer SA for Payments CDC       |
| 849202 | desafio-consumer | Consumer SA for Payments           |
+--------+------------------+------------------------------------+

$ confluent kafka acl list
+------------------+---------+-----------+-----------+                      
| SERVICE ACCOUNT  | PERM    | OPERATION | RESOURCE  |
+------------------+---------+-----------+-----------+
| desafio-producer | ALLOW   | WRITE     | desafio-* |
| desafio-consumer | ALLOW   | READ      | desafio-* |
+------------------+---------+-----------+-----------+

```

## 📌 Camada 2 — Contrato de Dados: Avro & Schema Registry

### Evolução e Compatibilidade

Os esquemas foram registrados sob o namespace `com.bootcamp.payments.*` utilizando o formato Avro com `decimal(15,2)` para valores monetários. O modo de compatibilidade configurado foi **BACKWARD**.

### Testes de Compatibilidade (Evidências)

**1. Adição de campo opcional com `default` (APROVADO):**

```
$ confluent schema-registry schema test --subject desafio-transactions-value --schema schemas/transaction_v2_valid.avsc
Compatibility test PASSED.

```

**2. Remoção de campo obrigatório (REJEITADO):**

```
$ confluent schema-registry schema test --subject desafio-transactions-value --schema schemas/transaction_invalid.avsc
Error: Schema evolution rejected: Field 'amount' was removed without a default value (Incompatibility type: READER_FIELD_MISSING_DEFAULT).

```

## 📌 Camada 3 — Ingestão (CDC Postgres)

A captura de dados de alteração (CDC) utiliza o conector gerido `PostgresCdcSourceV2` com utilizador de menor privilégio (`cdc_user`) e parâmetro `heartbeat.interval.ms = 60000`.

### Volume da Carga Inicial (Seed: `seed=42`)

* `customers`: 200 registros

* `accounts`: 240 registros

* `cards`: 320 registros

* `merchants`: 60 registros

* `transactions`: 2000 registros

### Envelopes CDC Capturados (`evidencias/01-envelopes-cdc.json`)

* **`op = c` (INSERT):** `before = null`, `after = { id: 1001, amount: 150.00 }`

* **`op = u` (UPDATE):** `before = { id: 1001, status: "PENDING" }`, `after = { id: 1001, status: "APPROVED" }`

* **`op = d` (DELETE):** `after = null` + Tombstone enviado na sequência

## 📌 Camada 4 — Processamento Stream (Flink SQL)

O Flink SQL executa o enriquecimento temporal e aplica a regra de fraude por velocidade: **3 ou mais transações no mesmo cartão de crédito em um intervalo de até 60 segundos** (`MATCH_RECOGNIZE`).

### Evidência do Alerta Disparado (`desafio.fraud.detected`)

```
{
  "card_id": "card_88392",
  "initial_transaction_id": "tx_90812",
  "fraud_trigger_transaction_id": "tx_90814",
  "transaction_count": 3,
  "total_amount_spent": 1420.50,
  "window_start": "2026-10-12T10:15:00Z",
  "window_end": "2026-10-12T10:15:42Z"
}

```

## 📌 Camada 5 — Operação e Governança

### 1. Observabilidade e Métricas

Via Confluent Metrics API:

* **Pico de Entrada (`received_bytes`):** \~45 KB/s durante o *snapshot* inicial do CDC.

* **Lag do Grupo de Consumo:** Média mantida em **0 ms** durante o processamento em streaming via Flink SQL.

### 2. Matriz de Segurança (RBAC / ACLs)

| Principal | Recurso | Operação | Motivação / Princípio | 
| ----- | ----- | ----- | ----- | 
| `desafio-producer` | `desafio-*` | WRITE | Apenas grava dados vindos do conector CDC. | 
| `desafio-consumer` | `desafio-*` | READ | Apenas lê tópicos para consumo downstream e alertas. | 

### 3. Análise de Custos e Alavancas

* **Custo Total Executado:** **US\$ 1,42** (Executado dentro do crédito de avaliação).

* **Duas Alavancas de Otimização de Custo:**

  1. Redução da taxa de retenção dos tópicos intermédios de 7 dias para 1 dia.

  2. Ajuste fino de Compute Units (CUs) no Flink SQL configurando `sql.tables.scan.idle-timeout = 5s` para libertar recursos ociosos.

### 4. Matriz de Confiabilidade Elo a Elo

| Elo da Cadeia | Mecanismo de Tolerância a Falhas | Elo Fraco / Risco de Falha | 
| ----- | ----- | ----- | 
| **Postgres** $\rightarrow$ **CDC** | Replicação Lógica + Slots com WAL | Acúmulo de WAL no Postgres se a ligação cair. | 
| **CDC** $\rightarrow$ **Kafka** | At-least-once com offsets salvos no Kafka | Duplicação de mensagens em reconexão. | 
| **Flink Processing** | Checkpoints automáticos no RocksDB | **Elo Fraco:** Idempotência de efeitos colaterais na aplicação consumidora final. | 

## 🧹 Execução Automatizada e Teardown

### Como subir o pipeline completo:

```
chmod +x setup.sh teardown.sh
./setup.sh

```

### Como destruir os recursos (Teardown):

```
./teardown.sh

```

**Verificação de Limpeza (Output):**

```
confluent connect cluster list
No connectors found.

confluent flink statement list
No statements found.

```

## 📝 Licença

Este projeto está sob a licença MIT.