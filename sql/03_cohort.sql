-- =============================================
-- 03_cohort.sql
-- Cohort · LTV · RFM 분석 (SQLite)
-- DB: data/db/fintech.db
-- 전제: 01_schema.sql 실행 후 사용
-- =============================================


-- =============================================
-- 1. Cohort 분석
-- =============================================

-- -----------------------------------------------
-- 1-1. Cohort Retention Matrix
-- 2002년 이후 코호트 대상 (안정적 데이터 구간)
-- -----------------------------------------------
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM clean_transactions
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
user_activity AS (
    SELECT DISTINCT
        c.User,
        fc.cohort_year,
        c.Year                    AS active_year,
        (c.Year - fc.cohort_year) AS years_since_first
    FROM clean_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    WHERE c.Year >= fc.cohort_year
),
cohort_size AS (
    SELECT
        cohort_year,
        COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort
    GROUP BY cohort_year
)
SELECT
    ua.cohort_year,
    ua.years_since_first,
    COUNT(DISTINCT ua.User)                                          AS retained_users,
    cs.cohort_users,
    ROUND(COUNT(DISTINCT ua.User) * 100.0 / cs.cohort_users, 1)     AS retention_rate
FROM user_activity ua
JOIN cohort_size cs ON ua.cohort_year = cs.cohort_year
GROUP BY ua.cohort_year, ua.years_since_first
ORDER BY ua.cohort_year, ua.years_since_first;


-- -----------------------------------------------
-- 1-2. Cohort별 거래 빈도 · 금액 변화
-- -----------------------------------------------
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year
    FROM clean_transactions
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
cohort_size AS (
    SELECT cohort_year, COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort
    GROUP BY cohort_year
)
SELECT
    fc.cohort_year,
    (c.Year - fc.cohort_year)                                        AS years_since_first,
    COUNT(*)                                                         AS total_tx,
    COUNT(DISTINCT c.User)                                           AS active_users,
    cs.cohort_users,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT c.User), 1)               AS avg_tx_per_user,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END)
        / COUNT(DISTINCT c.User), 0)                                 AS avg_revenue_per_user
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
JOIN cohort_size cs ON fc.cohort_year = cs.cohort_year
WHERE c.Year >= fc.cohort_year
GROUP BY fc.cohort_year, years_since_first
ORDER BY fc.cohort_year, years_since_first;


-- =============================================
-- 2. LTV 분석
-- =============================================

-- -----------------------------------------------
-- 2-1. 기간 보정 연간 LTV 계산
-- 총 거래금액 / 활동 연수 = 연간 평균 거래금액
-- 활동 연수 0인 경우 1로 보정 (0으로 나누기 방지)
-- -----------------------------------------------
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year,
        MAX(Year) AS last_year
    FROM clean_transactions
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year, last_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
user_revenue AS (
    SELECT
        c.User,
        SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) AS total_revenue,
        COUNT(*)                                               AS total_tx
    FROM ltv_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
)
SELECT
    fc.User,
    fc.cohort_year,
    fc.last_year,
    CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
         ELSE (fc.last_year - fc.cohort_year)
    END                                                        AS active_years,
    ur.total_revenue,
    ur.total_tx,
    ROUND(ur.total_revenue /
        CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
             ELSE (fc.last_year - fc.cohort_year)
        END, 0)                                                AS annual_ltv,
    ROUND(ur.total_tx /
        CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
             ELSE (fc.last_year - fc.cohort_year)
        END, 0)                                                AS annual_tx
FROM filtered_cohort fc
JOIN user_revenue ur ON fc.User = ur.User
ORDER BY annual_ltv DESC;


-- =============================================
-- 3. RFM 세그멘테이션
-- =============================================

-- -----------------------------------------------
-- 3-1. RFM 원본 계산
-- R: 마지막 거래 연도 기준 (2019 - MAX(Year))
-- F: 연간 평균 거래 횟수
-- M: 연간 평균 거래금액
-- F·M 점수화는 Python pd.qcut으로 처리 (notebooks/04_cohort_ltv.ipynb 참고)
-- -----------------------------------------------
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year
    FROM clean_transactions
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
)
SELECT
    c.User,
    (2019 - MAX(c.Year))                                    AS recency_years,
    ROUND(COUNT(*) * 1.0 /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
             ELSE (MAX(c.Year) - MIN(c.Year))
        END, 0)                                             AS frequency,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
             ELSE (MAX(c.Year) - MIN(c.Year))
        END, 0)                                             AS monetary
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
GROUP BY c.User;
