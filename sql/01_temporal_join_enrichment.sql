-- Temporal Join: Enriquecimento de Transações com Informações da Conta
CREATE TABLE desafio_transactions_enriched AS
SELECT 
    t.transaction_id,
    t.card_id,
    t.account_id,
    t.amount,
    t.merchant_id,
    t.transaction_time,
    a.customer_id,
    a.account_status,
    a.credit_limit
FROM desafio_transactions t
JOIN desafio_accounts FOR SYSTEM_TIME AS OF t.transaction_time AS a
    ON t.account_id = a.account_id;