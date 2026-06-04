-- =============================================
-- 01_schema.sql
-- SQLite 분석용 View 생성
-- DB: data/db/fintech.db
-- =============================================
-- 참고: SQLite에서는 Amount가 '$1234.56' 형태의 STRING으로 저장됨
--       → CAST(REPLACE(Amount, '$', '') AS FLOAT)로 변환 필요
--       BigQuery 버전은 sql/bigquery_views.sql 참고
-- =============================================


-- -----------------------------------------------
-- 1. clean_transactions
-- 사기 거래 제외 ("Is Fraud?" = 'No')
-- 2020년 데이터 제외 (1월만 존재하여 불완전)
-- Amount '$' 제거 후 FLOAT 변환
-- 파생 컬럼 추가 (date_int, year_month)
-- -----------------------------------------------
CREATE VIEW IF NOT EXISTS clean_transactions AS
SELECT
    User,
    Card,
    Year,
    Month,
    Day,
    Time,
    CAST(REPLACE(Amount, '$', '') AS FLOAT)  AS Amount,
    "Use Chip"                               AS use_chip,
    "Merchant Name"                          AS merchant_name,
    "Merchant City"                          AS merchant_city,
    "Merchant State"                         AS merchant_state,
    Zip,
    MCC,
    "Errors?"                                AS errors,
    "Is Fraud?"                              AS is_fraud,
    Year * 10000 + Month * 100 + Day         AS date_int,
    Year * 100 + Month                       AS year_month
FROM transactions
WHERE "Is Fraud?" = 'No'
AND Year < 2020;


-- -----------------------------------------------
-- 2. ltv_transactions
-- clean_transactions 기반
-- 환불(Amount <= 0), 오류(errors IS NOT NULL),
-- 이상치(Amount > 5000) 제외
-- LTV · RFM 계산에 사용
-- -----------------------------------------------
CREATE VIEW IF NOT EXISTS ltv_transactions AS
SELECT *
FROM clean_transactions
WHERE Amount > 0
AND errors IS NULL
AND Amount <= 5000;
