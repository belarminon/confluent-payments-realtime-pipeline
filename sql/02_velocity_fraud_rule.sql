-- Regra de Velocidade: 3+ transações no mesmo cartão num intervalo <= 60 segundos
CREATE TABLE desafio_fraud_detected AS
SELECT 
    card_id,
    FIRST_VALUE(transaction_id) AS initial_transaction_id,
    LAST_VALUE(transaction_id) AS fraud_trigger_transaction_id,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount_spent,
    window_start,
    window_end
FROM desafio_transactions
MATCH_RECOGNIZE (
    PARTITION BY card_id
    ORDER BY transaction_time
    MEASURES
        FIRST(T.transaction_id) AS initial_transaction_id,
        LAST(T.transaction_id) AS fraud_trigger_transaction_id,
        MATCH_ROWTIME() AS window_end,
        FIRST(T.transaction_time) AS window_start
    ONE ROW PER MATCH
    PATTERN (T{3,})
    WITHIN INTERVAL '60' SECOND
    DEFINE
        T AS T.transaction_id IS NOT NULL
)
GROUP BY card_id, window_start, window_end;