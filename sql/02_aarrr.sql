-- =============================================
-- 02_aarrr.sql
-- AARRR 퍼널 분석 (SQLite)
-- DB: data/db/fintech.db
-- 전제: 01_schema.sql 실행 후 사용
-- =============================================


-- -----------------------------------------------
-- 1. Acquisition: 연도별 신규 유저 수
-- -----------------------------------------------
SELECT
    first_year,
    COUNT(DISTINCT User) AS new_users
FROM (
    SELECT
        User,
        MIN(Year) AS first_year
    FROM clean_transactions
    GROUP BY User
) first_tx
GROUP BY first_year
ORDER BY first_year;


-- -----------------------------------------------
-- 2. Activation: 첫 거래 후 30일 이내 재거래 비율
-- date_int = Year*10000 + Month*100 + Day 정수 뺄셈으로 날짜 차이 계산
-- -----------------------------------------------
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
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
    COUNT(DISTINCT f.User) AS acquired_users,
    COUNT(DISTINCT s.User) AS had_second_tx,
    COUNT(DISTINCT CASE
        WHEN (s.second_date - f.first_date) <= 30
        THEN f.User
    END) AS activated_users,
    ROUND(
        COUNT(DISTINCT CASE
            WHEN (s.second_date - f.first_date) <= 30
            THEN f.User
        END) * 100.0 / COUNT(DISTINCT f.User), 2
    ) AS activation_rate
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User;


-- -----------------------------------------------
-- 3. Retention: 첫 거래 다음 연도 재거래 비율
-- -----------------------------------------------
WITH first_year AS (
    SELECT
        User,
        MIN(Year) AS first_year
    FROM clean_transactions
    GROUP BY User
),
next_year_tx AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
    JOIN first_year f ON c.User = f.User
    WHERE c.Year = f.first_year + 1
)
SELECT
    COUNT(DISTINCT f.User) AS acquired_users,
    COUNT(DISTINCT n.User) AS retained_users,
    ROUND(
        COUNT(DISTINCT n.User) * 100.0 / COUNT(DISTINCT f.User), 2
    ) AS retention_rate
FROM first_year f
LEFT JOIN next_year_tx n ON f.User = n.User;


-- -----------------------------------------------
-- 4. Revenue: 유저별 총 거래금액 요약
-- -----------------------------------------------
SELECT
    COUNT(DISTINCT User)            AS total_users,
    ROUND(AVG(total_amount), 2)     AS avg_ltv,
    ROUND(MIN(total_amount), 2)     AS min_ltv,
    ROUND(MAX(total_amount), 2)     AS max_ltv,
    COUNT(CASE WHEN total_amount > 10000 THEN 1 END) AS high_value_users
FROM (
    SELECT
        User,
        SUM(Amount) AS total_amount
    FROM ltv_transactions
    GROUP BY User
);


-- -----------------------------------------------
-- 5. AARRR 순차 퍼널
-- Acquisition → Activation → Retention 순차 적용
-- -----------------------------------------------
WITH acquisition AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
    FROM clean_transactions
    GROUP BY User
),
activation AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
    JOIN acquisition a ON c.User = a.User
    WHERE c.date_int > a.first_date
    AND (c.date_int - a.first_date) <= 30
),
retention AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
    JOIN acquisition a  ON c.User = a.User
    JOIN activation act ON c.User = act.User
    WHERE c.Year = a.first_year + 1
)
SELECT
    COUNT(DISTINCT a.User)   AS acquisition,
    COUNT(DISTINCT act.User) AS activation,
    COUNT(DISTINCT r.User)   AS retention
FROM acquisition a
LEFT JOIN activation act ON a.User = act.User
LEFT JOIN retention r   ON a.User = r.User;


-- -----------------------------------------------
-- 6. Activation × Retention 유저 세그멘테이션
-- -----------------------------------------------
WITH acquisition AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
    FROM clean_transactions
    GROUP BY User
),
second_tx AS (
    SELECT
        c.User,
        MIN(c.date_int) AS second_date
    FROM clean_transactions c
    JOIN acquisition a ON c.User = a.User
    WHERE c.date_int > a.first_date
    GROUP BY c.User
),
next_year AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
    JOIN acquisition a ON c.User = a.User
    WHERE c.Year = a.first_year + 1
),
user_flags AS (
    SELECT
        a.User,
        CASE WHEN (s.second_date - a.first_date) <= 30
            THEN 1 ELSE 0 END AS is_activated,
        CASE WHEN n.User IS NOT NULL
            THEN 1 ELSE 0 END AS is_retained
    FROM acquisition a
    LEFT JOIN second_tx s ON a.User = s.User
    LEFT JOIN next_year n ON a.User = n.User
)
SELECT
    CASE
        WHEN is_activated = 1 AND is_retained = 1 THEN '진성 유저'
        WHEN is_activated = 1 AND is_retained = 0 THEN '초반 반짝 유저'
        WHEN is_activated = 0 AND is_retained = 1 THEN '느린 정착형 유저'
        ELSE '이탈 유저'
    END                                                      AS user_type,
    COUNT(*)                                                 AS user_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM acquisition), 2) AS ratio
FROM user_flags
GROUP BY user_type
ORDER BY user_count DESC;
