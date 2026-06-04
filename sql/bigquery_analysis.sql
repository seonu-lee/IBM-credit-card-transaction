-- =============================================
-- BigQuery 분석 쿼리
-- 프로젝트: project-08140dda-e851-4d93-b88
-- 데이터셋: ibm_card_analysis
-- =============================================


-- =============================================
-- 1. EDA
-- =============================================

-- 1-1. 데이터 범위 파악
SELECT
    MIN(Year)                    AS min_year,
    MAX(Year)                    AS max_year,
    COUNT(DISTINCT Year)         AS year_count,
    COUNT(DISTINCT Month)        AS month_count,
    COUNT(DISTINCT User)         AS user_count,
    COUNT(DISTINCT merchant_name) AS merchant_count,
    COUNT(DISTINCT MCC)          AS mcc_count
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`;


-- 1-2. Amount 통계
SELECT
    MIN(Amount)                  AS min_amount,
    MAX(Amount)                  AS max_amount,
    ROUND(AVG(Amount), 2)        AS avg_amount,
    COUNTIF(Amount < 0)          AS negative_count,
    COUNT(*)                     AS total_count
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`;


-- 1-3. 음수 거래 상세 확인
SELECT
    use_chip,
    merchant_city,
    MCC,
    errors,
    Amount,
    COUNT(*)                     AS cnt
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
WHERE Amount < 0
GROUP BY use_chip, merchant_city, MCC, errors, Amount
ORDER BY cnt DESC
LIMIT 20;


-- 1-4. 음수 거래 오류 동반 비율
SELECT
    errors,
    COUNT(*)                     AS cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS ratio
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
WHERE Amount < 0
GROUP BY errors
ORDER BY cnt DESC;


-- 1-5. 사기 거래 비율 (원본 테이블 기준)
SELECT
    `Is Fraud_`                  AS is_fraud,
    COUNT(*)                     AS cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 4) AS ratio
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.transactions`
GROUP BY `Is Fraud_`;


-- 1-6. 오류 유형 분포
SELECT
    errors                       AS error_type,
    COUNT(*)                     AS cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 4) AS ratio
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
GROUP BY errors
ORDER BY cnt DESC;


-- 1-7. 결측치 확인
SELECT
    COUNTIF(User IS NULL)           AS user_null,
    COUNTIF(Amount IS NULL)         AS amount_null,
    COUNTIF(Year IS NULL)           AS year_null,
    COUNTIF(MCC IS NULL)            AS mcc_null,
    COUNTIF(merchant_city IS NULL)  AS city_null,
    COUNTIF(merchant_state IS NULL) AS state_null,
    COUNTIF(Zip IS NULL)            AS zip_null
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`;


-- 1-8. Amount 이상치 확인
SELECT
    COUNT(*)                                          AS total,
    COUNTIF(Amount > 5000)                            AS over_5000,
    COUNTIF(Amount > 10000)                           AS over_10000,
    ROUND(AVG(Amount), 2)                             AS avg_amount,
    ROUND(MIN(Amount), 2)                             AS min_amount,
    MAX(Amount)                                       AS max_amount
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
WHERE Amount > 0;


-- 1-9. MCC Top 20
SELECT
    MCC,
    COUNT(*)                     AS tx_count,
    COUNT(DISTINCT User)         AS user_count,
    ROUND(AVG(Amount), 2)        AS avg_amount,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS ratio
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
GROUP BY MCC
ORDER BY tx_count DESC
LIMIT 20;


-- 1-10. 연도별 거래 추이
SELECT
    Year,
    COUNT(*)                     AS tx_count,
    COUNT(DISTINCT User)         AS active_users,
    ROUND(AVG(Amount), 2)        AS avg_amount,
    ROUND(SUM(Amount), 2)        AS total_revenue
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
WHERE Amount > 0
GROUP BY Year
ORDER BY Year;

-- =============================================
-- 2. AARRR 퍼널 분석
-- =============================================

-- 2-1. Acquisition: 연도별 신규 유저 수
SELECT
    first_year,
    COUNT(DISTINCT User) AS new_users
FROM (
    SELECT
        User,
        MIN(Year) AS first_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
) AS first_tx
GROUP BY first_year
ORDER BY first_year;


-- 2-2. Activation: 첫 거래 후 30일 이내 재거래 비율
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
second_tx AS (
    SELECT
        c.User,
        MIN(c.date_int) AS second_date
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN first_tx f ON c.User = f.User
    WHERE c.date_int > f.first_date
    GROUP BY c.User
)
SELECT
    COUNT(DISTINCT f.User)  AS acquired_users,
    COUNT(DISTINCT s.User)  AS had_second_tx,
    COUNT(DISTINCT CASE WHEN (s.second_date - f.first_date) <= 30 THEN f.User END) AS activated_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN (s.second_date - f.first_date) <= 30 THEN f.User END)
        * 100.0 / COUNT(DISTINCT f.User), 2
    ) AS activation_rate
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User;


-- 2-3. Retention: 첫 거래 다음 연도 재거래 비율
WITH first_year AS (
    SELECT
        User,
        MIN(Year) AS first_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
next_year_tx AS (
    SELECT DISTINCT c.User
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN first_year f ON c.User = f.User
    WHERE c.Year = f.first_year + 1
)
SELECT
    COUNT(DISTINCT f.User)  AS acquired_users,
    COUNT(DISTINCT n.User)  AS retained_users,
    ROUND(
        COUNT(DISTINCT n.User) * 100.0 / COUNT(DISTINCT f.User), 2
    ) AS retention_rate
FROM first_year f
LEFT JOIN next_year_tx n ON f.User = n.User;


-- 2-4. Revenue: 유저별 총 거래금액 요약
SELECT
    COUNT(DISTINCT User)            AS total_users,
    ROUND(AVG(total_amount), 2)     AS avg_ltv,
    ROUND(MIN(total_amount), 2)     AS min_ltv,
    ROUND(MAX(total_amount), 2)     AS max_ltv,
    COUNTIF(total_amount > 10000)   AS high_value_users
FROM (
    SELECT
        User,
        SUM(Amount) AS total_amount
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.ltv_transactions`
    GROUP BY User
) AS user_revenue;


-- 2-5. AARRR 순차 퍼널
WITH acquisition AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
activation AS (
    SELECT DISTINCT c.User
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN acquisition a ON c.User = a.User
    WHERE c.date_int > a.first_date
    AND (c.date_int - a.first_date) <= 30
),
retention AS (
    SELECT DISTINCT c.User
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN acquisition a ON c.User = a.User
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


-- 2-6. Activation × Retention 유저 세그멘테이션
WITH acquisition AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year)     AS first_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
second_tx AS (
    SELECT
        c.User,
        MIN(c.date_int) AS second_date
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN acquisition a ON c.User = a.User
    WHERE c.date_int > a.first_date
    GROUP BY c.User
),
next_year AS (
    SELECT DISTINCT c.User
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN acquisition a ON c.User = a.User
    WHERE c.Year = a.first_year + 1
),
user_flags AS (
    SELECT
        a.User,
        CASE WHEN (s.second_date - a.first_date) <= 30 THEN 1 ELSE 0 END AS is_activated,
        CASE WHEN n.User IS NOT NULL THEN 1 ELSE 0 END                    AS is_retained
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
    END                             AS user_type,
    COUNT(*)                        AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS ratio
FROM user_flags
GROUP BY user_type
ORDER BY user_count DESC;

-- =============================================
-- 3. Cohort 분석
-- =============================================

-- 3-1. Cohort Retention Matrix
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
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
        c.Year                        AS active_year,
        (c.Year - fc.cohort_year)     AS years_since_first
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
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
    COUNT(DISTINCT ua.User)           AS retained_users,
    cs.cohort_users,
    ROUND(COUNT(DISTINCT ua.User) * 100.0 / cs.cohort_users, 1) AS retention_rate
FROM user_activity ua
JOIN cohort_size cs ON ua.cohort_year = cs.cohort_year
GROUP BY ua.cohort_year, ua.years_since_first, cs.cohort_users
ORDER BY ua.cohort_year, ua.years_since_first;


-- 3-2. Cohort별 거래 빈도 · 금액 변화
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
cohort_size AS (
    SELECT
        cohort_year,
        COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort
    GROUP BY cohort_year
)
SELECT
    fc.cohort_year,
    (c.Year - fc.cohort_year)         AS years_since_first,
    COUNT(*)                          AS total_tx,
    COUNT(DISTINCT c.User)            AS active_users,
    cs.cohort_users,
    ROUND(COUNT(*) / COUNT(DISTINCT c.User), 1)              AS avg_tx_per_user,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END)
        / COUNT(DISTINCT c.User), 0)                         AS avg_revenue_per_user
FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
JOIN filtered_cohort fc ON c.User = fc.User
JOIN cohort_size cs ON fc.cohort_year = cs.cohort_year
WHERE c.Year >= fc.cohort_year
GROUP BY fc.cohort_year, years_since_first, cs.cohort_users
ORDER BY fc.cohort_year, years_since_first;


-- =============================================
-- 4. LTV 분석
-- =============================================

-- 4-1. 기간 보정 연간 LTV 계산
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year,
        MAX(Year) AS last_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
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
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.ltv_transactions` c
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


-- 4-2. 연간 LTV 요약 통계
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year,
        MAX(Year) AS last_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
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
        SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) AS total_revenue
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.ltv_transactions` c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
),
ltv_calc AS (
    SELECT
        fc.User,
        ROUND(ur.total_revenue /
            CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
                 ELSE (fc.last_year - fc.cohort_year)
            END, 0) AS annual_ltv
    FROM filtered_cohort fc
    JOIN user_revenue ur ON fc.User = ur.User
),
-- PERCENTILE_CONT는 윈도우 함수라 COUNT·AVG 등 집계함수와
-- 같은 SELECT 안에 쓸 수 없음 → stats / median CTE로 분리 후 합침
stats AS (
    SELECT
        COUNT(*)                  AS total_users,
        ROUND(AVG(annual_ltv), 0) AS avg_annual_ltv,
        ROUND(MIN(annual_ltv), 0) AS min_annual_ltv,
        ROUND(MAX(annual_ltv), 0) AS max_annual_ltv
    FROM ltv_calc
),
median AS (
    SELECT
        ROUND(PERCENTILE_CONT(annual_ltv, 0.5) OVER(), 0) AS median_annual_ltv
    FROM ltv_calc
    LIMIT 1
)
SELECT
    s.total_users,
    s.avg_annual_ltv,
    s.min_annual_ltv,
    s.max_annual_ltv,
    m.median_annual_ltv
FROM stats s, median m;

-- =============================================
-- 5. RFM 세그멘테이션
-- =============================================

-- 5-1. RFM 원본 계산
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
rfm_raw AS (
    SELECT
        c.User,
        -- Recency: 마지막 거래 연도가 높을수록 최근
        (2019 - MAX(c.Year))                                AS recency_years,
        -- Frequency: 연간 평균 거래 횟수
        ROUND(COUNT(*) /
            CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
                 ELSE (MAX(c.Year) - MIN(c.Year))
            END, 0)                                         AS frequency,
        -- Monetary: 연간 평균 거래금액
        ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) /
            CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
                 ELSE (MAX(c.Year) - MIN(c.Year))
            END, 0)                                         AS monetary
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
),
-- R 점수: recency_years 기준으로 직접 스코어링
-- F·M 점수: BigQuery에는 NTILE로 5분위 처리
rfm_scored AS (
    SELECT
        User,
        recency_years,
        frequency,
        monetary,
        CASE
            WHEN recency_years = 0  THEN 5
            WHEN recency_years <= 2 THEN 4
            WHEN recency_years <= 5 THEN 3
            WHEN recency_years <= 9 THEN 2
            ELSE 1
        END                                                 AS R,
        NTILE(5) OVER (ORDER BY frequency)                  AS F,
        NTILE(5) OVER (ORDER BY monetary)                   AS M
    FROM rfm_raw
),
rfm_classified AS (
    SELECT
        *,
        (R + F + M)                                         AS RFM_score,
        CASE
            WHEN (R + F + M) >= 13                          THEN 'VIP'
            WHEN (R + F + M) >= 10                          THEN 'Loyal'
            WHEN (R + F + M) >= 7                           THEN 'Potential'
            WHEN R <= 2 AND (F >= 3 OR M >= 3)              THEN 'At Risk'
            ELSE 'Dormant'
        END                                                 AS segment
    FROM rfm_scored
)
SELECT *
FROM rfm_classified
ORDER BY RFM_score DESC;


-- 5-2. 세그먼트별 요약
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions`
    GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year
    FROM cohort_base
    WHERE cohort_year >= 2002
),
rfm_raw AS (
    SELECT
        c.User,
        (2019 - MAX(c.Year))                                AS recency_years,
        ROUND(COUNT(*) /
            CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
                 ELSE (MAX(c.Year) - MIN(c.Year))
            END, 0)                                         AS frequency,
        ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) /
            CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
                 ELSE (MAX(c.Year) - MIN(c.Year))
            END, 0)                                         AS monetary
    FROM `project-08140dda-e851-4d93-b88.ibm_card_analysis.clean_transactions` c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
),
rfm_scored AS (
    SELECT
        User,
        recency_years,
        frequency,
        monetary,
        CASE
            WHEN recency_years = 0  THEN 5
            WHEN recency_years <= 2 THEN 4
            WHEN recency_years <= 5 THEN 3
            WHEN recency_years <= 9 THEN 2
            ELSE 1
        END                                                 AS R,
        NTILE(5) OVER (ORDER BY frequency)                  AS F,
        NTILE(5) OVER (ORDER BY monetary)                   AS M
    FROM rfm_raw
),
rfm_classified AS (
    SELECT
        *,
        (R + F + M)                                         AS RFM_score,
        CASE
            WHEN (R + F + M) >= 13                          THEN 'VIP'
            WHEN (R + F + M) >= 10                          THEN 'Loyal'
            WHEN (R + F + M) >= 7                           THEN 'Potential'
            WHEN R <= 2 AND (F >= 3 OR M >= 3)              THEN 'At Risk'
            ELSE 'Dormant'
        END                                                 AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(*)                        AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS ratio,
    ROUND(AVG(recency_years), 1)    AS avg_recency,
    ROUND(AVG(frequency), 0)        AS avg_frequency,
    ROUND(AVG(monetary), 0)         AS avg_monetary,
    ROUND(AVG(RFM_score), 1)        AS avg_rfm_score
FROM rfm_classified
GROUP BY segment
ORDER BY avg_rfm_score DESC;
