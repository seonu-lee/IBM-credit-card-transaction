-- =============================================
-- BigQuery Views 생성
-- 프로젝트: project-08140dda-e851-4d93-b88
-- 데이터셋: ibm_card_analysis
-- =============================================

-- -----------------------------------------------
-- 1. clean_transactions
-- 사기 거래 제외 (Is Fraud_ = 'No')
-- 2020년 데이터 제외 (1월만 존재하여 불완전)
-- Amount '$' 제거 후 FLOAT64 변환
-- 파생 컬럼 추가 (date_int, year_month)
-- -----------------------------------------------
CREATE OR REPLACE VIEW `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` AS
SELECT
    User,
    Card,
    Year,
    Month,
    Day,
    Time,
    Amount,
    `Use Chip`                                       AS use_chip,
    `Merchant Name`                                  AS merchant_name,
    `Merchant City`                                  AS merchant_city,
    `Merchant State`                                 AS merchant_state,
    Zip,
    MCC,
    Errors_                                          AS errors,
    `Is Fraud_`                                      AS is_fraud,
    Year * 10000 + Month * 100 + Day                 AS date_int,
    Year * 100 + Month                               AS year_month
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.transactions`
WHERE `Is Fraud_` = FALSE
AND Year < 2020;


-- -----------------------------------------------
-- 2. ltv_transactions
-- clean_transactions 기반
-- 환불(Amount <= 0), 오류(errors IS NOT NULL),
-- 이상치(Amount > 5000) 제외
-- LTV · RFM 계산에 사용
-- -----------------------------------------------
CREATE OR REPLACE VIEW `project-08140dda-e851-4d93-b88.ibm_card_analysis.ltv_transactions` AS
SELECT *
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
WHERE Amount > 0
AND errors IS NULL
AND Amount <= 5000;