-- =============================================
-- 04_ab_test.sql
-- A/B 테스트 데이터 추출 (SQLite)
-- DB: data/db/fintech.db
-- 전제: 01_schema.sql 실행 후 사용
-- 참고: 실제 A/B 테스트 시뮬레이션 및 통계 검정은
--       notebooks/05_ab_test.ipynb 참고
-- =============================================


-- -----------------------------------------------
-- A/B 테스트용 Activation 데이터 추출
-- 실제 Activation율을 대조군 벤치마크로 활용
-- activated = 1: 첫 거래 후 30일 이내 재거래
-- activated = 0: 미활성화
-- -----------------------------------------------
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year,
        MIN(Month)    AS first_month,
        MIN(Day)      AS first_day
    FROM clean_transactions
    GROUP BY User
),
second_tx AS (
    SELECT
        c.User,
        MIN(c.date_int) AS second_date
    FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    WHERE c.date_int > f.first_date
    GROUP BY c.User
)
SELECT
    f.User,
    f.first_date,
    s.second_date,
    CASE
        WHEN s.second_date IS NULL              THEN 0
        WHEN (s.second_date - f.first_date) <= 30 THEN 1
        ELSE 0
    END AS activated
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User;
