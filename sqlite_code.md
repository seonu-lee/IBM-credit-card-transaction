**[01_data_loading.ipynb]**
- 쿼리 목적: 테이블 행 수 확인
```sql
SELECT COUNT(*) as cnt FROM {table}
```

---

**[02_eda.ipynb]**

- 쿼리 목적: 테이블 샘플 확인
```sql
SELECT * FROM transactions LIMIT 5
SELECT * FROM users LIMIT 5
```

- 쿼리 목적: 데이터 범위 파악
```sql
SELECT
    MIN(Year) AS min_year,
    MAX(Year) AS max_year,
    COUNT(DISTINCT Year) AS year_count,
    COUNT(DISTINCT Month) AS month_count,
    COUNT(DISTINCT User) AS user_count,
    COUNT(DISTINCT "Merchant Name") AS merchant_count,
    COUNT(DISTINCT MCC) AS mcc_count
FROM transactions
```

- 쿼리 목적: Amount 전처리 및 통계 확인
```sql
SELECT
    MIN(CAST(REPLACE(Amount, '$', '') AS FLOAT)) AS min_amount,
    MAX(CAST(REPLACE(Amount, '$', '') AS FLOAT)) AS max_amount,
    ROUND(AVG(CAST(REPLACE(Amount, '$', '') AS FLOAT)), 2) AS avg_amount,
    SUM(CASE WHEN CAST(REPLACE(Amount, '$', '') AS FLOAT) < 0 THEN 1 ELSE 0 END) AS negative_count,
    COUNT(*) AS total_count
FROM transactions
```

- 쿼리 목적: 음수 거래 상세 확인
```sql
SELECT use_chip, merchant_name, merchant_city, MCC, errors, Amount, COUNT(*) as cnt
FROM clean_transactions
WHERE Amount < 0
GROUP BY use_chip, MCC
ORDER BY cnt DESC
LIMIT 20
```

- 쿼리 목적: 음수 거래 오류 동반 비율
```sql
SELECT
    errors,
    COUNT(*) as cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as ratio
FROM clean_transactions
WHERE Amount < 0
GROUP BY errors
ORDER BY cnt DESC
```

- 쿼리 목적: 사기 거래 비율
```sql
SELECT
    "Is Fraud?" AS is_fraud,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 4) AS ratio
FROM transactions
GROUP BY "Is Fraud?"
```

- 쿼리 목적: Errors? 결측치 패턴
```sql
SELECT
    "Errors?" AS error_type,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 4) AS ratio
FROM transactions
GROUP BY "Errors?"
ORDER BY count DESC
```

- 쿼리 목적: 분석용 뷰 생성 (사기 제외, 2020년 제외, Amount 변환)
```sql
CREATE VIEW clean_transactions AS
SELECT
    User, Card, Year, Month, Day, Time,
    CAST(REPLACE(Amount, '$', '') AS FLOAT) AS Amount,
    "Use Chip" AS use_chip,
    "Merchant Name" AS merchant_name,
    "Merchant City" AS merchant_city,
    "Merchant State" AS merchant_state,
    Zip, MCC,
    "Errors?" AS errors,
    "Is Fraud?" AS is_fraud,
    Year * 10000 + Month * 100 + Day AS date_int,
    Year * 100 + Month AS year_month
FROM transactions
WHERE "Is Fraud?" = 'No'
AND Year < 2020
```

- 쿼리 목적: LTV용 뷰 생성 (환불·오류·이상치 제외)
```sql
CREATE VIEW ltv_transactions AS
SELECT *
FROM clean_transactions
WHERE Amount > 0
AND errors IS NULL
AND Amount <= 5000
```

- 쿼리 목적: 결측치 확인
```sql
SELECT
    SUM(CASE WHEN User IS NULL THEN 1 ELSE 0 END) AS user_null,
    SUM(CASE WHEN Amount IS NULL THEN 1 ELSE 0 END) AS amount_null,
    SUM(CASE WHEN Year IS NULL THEN 1 ELSE 0 END) AS year_null,
    SUM(CASE WHEN MCC IS NULL THEN 1 ELSE 0 END) AS mcc_null,
    SUM(CASE WHEN merchant_city IS NULL THEN 1 ELSE 0 END) AS city_null,
    SUM(CASE WHEN merchant_state IS NULL THEN 1 ELSE 0 END) AS state_null,
    SUM(CASE WHEN Zip IS NULL THEN 1 ELSE 0 END) AS zip_null
FROM clean_transactions
```

- 쿼리 목적: Amount 이상치 확인
```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN Amount > 5000 THEN 1 ELSE 0 END) AS over_5000,
    SUM(CASE WHEN Amount > 10000 THEN 1 ELSE 0 END) AS over_10000,
    ROUND(AVG(Amount), 2) AS avg,
    ROUND(MIN(Amount), 2) AS min_amount,
    MAX(Amount) AS max_amount
FROM clean_transactions
WHERE Amount > 0
```

- 쿼리 목적: MCC Top 20 분석
```sql
SELECT
    MCC,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT User) AS user_count,
    ROUND(AVG(Amount), 2) AS avg_amount,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM clean_transactions), 2) AS ratio
FROM clean_transactions
GROUP BY MCC
ORDER BY tx_count DESC
LIMIT 20
```

- 쿼리 목적: 연도별 거래 추이
```sql
SELECT
    Year,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT User) AS active_users,
    ROUND(AVG(Amount), 2) AS avg_amount,
    ROUND(SUM(Amount), 2) AS total_revenue
FROM clean_transactions
WHERE Amount > 0
GROUP BY Year
ORDER BY Year
```

---

**[03_aarrr_funnel.ipynb]**

- 쿼리 목적: Acquisition - 연도별 신규 유저 수
```sql
SELECT first_year, COUNT(DISTINCT User) AS new_users
FROM (
    SELECT User, MIN(Year) AS first_year
    FROM clean_transactions
    GROUP BY User
) first_tx
GROUP BY first_year
ORDER BY first_year
```

- 쿼리 목적: Activation - 첫 거래 후 30일 이내 재거래 비율
```sql
WITH first_tx AS (
    SELECT User, MIN(date_int) AS first_date, MIN(Year) AS first_year
    FROM clean_transactions GROUP BY User
),
second_tx AS (
    SELECT c.User, MIN(c.date_int) AS second_date
    FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    WHERE c.date_int > f.first_date
    GROUP BY c.User
)
SELECT
    COUNT(DISTINCT f.User) AS acquired_users,
    COUNT(DISTINCT s.User) AS had_second_tx,
    COUNT(DISTINCT CASE WHEN (s.second_date - f.first_date) <= 30 THEN f.User END) AS activated_users,
    ROUND(COUNT(DISTINCT CASE WHEN (s.second_date - f.first_date) <= 30 THEN f.User END)
        * 100.0 / COUNT(DISTINCT f.User), 2) AS activation_rate
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User
```

- 쿼리 목적: Retention - 첫 거래 다음 연도 재거래 비율
```sql
WITH first_year AS (
    SELECT User, MIN(Year) AS first_year
    FROM clean_transactions GROUP BY User
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
    ROUND(COUNT(DISTINCT n.User) * 100.0 / COUNT(DISTINCT f.User), 2) AS retention_rate
FROM first_year f
LEFT JOIN next_year_tx n ON f.User = n.User
```

- 쿼리 목적: Revenue - 유저별 총 거래금액 요약
```sql
SELECT
    COUNT(DISTINCT User) AS total_users,
    ROUND(AVG(total_amount), 2) AS avg_ltv,
    ROUND(MIN(total_amount), 2) AS min_ltv,
    ROUND(MAX(total_amount), 2) AS max_ltv,
    COUNT(CASE WHEN total_amount > 10000 THEN 1 END) AS high_value_users
FROM (
    SELECT User, SUM(Amount) AS total_amount
    FROM ltv_transactions GROUP BY User
)
```

- 쿼리 목적: AARRR 순차 퍼널
```sql
WITH acquisition AS (
    SELECT User, MIN(date_int) AS first_date, MIN(Year) AS first_year
    FROM clean_transactions GROUP BY User
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
    JOIN acquisition a ON c.User = a.User
    JOIN activation act ON c.User = act.User
    WHERE c.Year = a.first_year + 1
)
SELECT
    COUNT(DISTINCT a.User) AS acquisition,
    COUNT(DISTINCT act.User) AS activation,
    COUNT(DISTINCT r.User) AS retention
FROM acquisition a
LEFT JOIN activation act ON a.User = act.User
LEFT JOIN retention r ON a.User = r.User
```

---

**[04_cohort_ltv.ipynb]**

- 쿼리 목적: Cohort Retention Matrix
```sql
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year
    FROM clean_transactions GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year FROM cohort_base WHERE cohort_year >= 2002
),
user_activity AS (
    SELECT DISTINCT c.User, fc.cohort_year, c.Year AS active_year,
        (c.Year - fc.cohort_year) AS years_since_first
    FROM clean_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    WHERE c.Year >= fc.cohort_year
),
cohort_size AS (
    SELECT cohort_year, COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort GROUP BY cohort_year
)
SELECT
    ua.cohort_year, ua.years_since_first,
    COUNT(DISTINCT ua.User) AS retained_users,
    cs.cohort_users,
    ROUND(COUNT(DISTINCT ua.User) * 100.0 / cs.cohort_users, 1) AS retention_rate
FROM user_activity ua
JOIN cohort_size cs ON ua.cohort_year = cs.cohort_year
GROUP BY ua.cohort_year, ua.years_since_first
ORDER BY ua.cohort_year, ua.years_since_first
```

- 쿼리 목적: Cohort별 거래 빈도·금액 변화
```sql
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year FROM clean_transactions GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year FROM cohort_base WHERE cohort_year >= 2002
),
cohort_size AS (
    SELECT cohort_year, COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort GROUP BY cohort_year
)
SELECT
    fc.cohort_year,
    (c.Year - fc.cohort_year) AS years_since_first,
    COUNT(*) AS total_tx,
    COUNT(DISTINCT c.User) AS active_users,
    cs.cohort_users,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT c.User), 1) AS avg_tx_per_user,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) / COUNT(DISTINCT c.User), 0) AS avg_revenue_per_user
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
JOIN cohort_size cs ON fc.cohort_year = cs.cohort_year
WHERE c.Year >= fc.cohort_year
GROUP BY fc.cohort_year, years_since_first
ORDER BY fc.cohort_year, years_since_first
```

- 쿼리 목적: 연간 LTV 계산 (기간 보정)
```sql
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year, MAX(Year) AS last_year
    FROM clean_transactions GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year, last_year FROM cohort_base WHERE cohort_year >= 2002
),
user_revenue AS (
    SELECT c.User,
        SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) AS total_revenue,
        COUNT(*) AS total_tx
    FROM ltv_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
)
SELECT
    fc.User, fc.cohort_year, fc.last_year,
    CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
         ELSE (fc.last_year - fc.cohort_year) END AS active_years,
    ur.total_revenue, ur.total_tx,
    ROUND(ur.total_revenue / CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
        ELSE (fc.last_year - fc.cohort_year) END, 0) AS annual_ltv,
    ROUND(ur.total_tx / CASE WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
        ELSE (fc.last_year - fc.cohort_year) END, 0) AS annual_tx
FROM filtered_cohort fc
JOIN user_revenue ur ON fc.User = ur.User
```

- 쿼리 목적: RFM 계산
```sql
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year FROM clean_transactions GROUP BY User
),
filtered_cohort AS (
    SELECT User, cohort_year FROM cohort_base WHERE cohort_year >= 2002
)
SELECT
    c.User,
    (2019 - MAX(c.Year)) AS recency_years,
    ROUND(COUNT(*) * 1.0 /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
        ELSE (MAX(c.Year) - MIN(c.Year)) END, 0) AS frequency,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
        ELSE (MAX(c.Year) - MIN(c.Year)) END, 0) AS monetary
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
GROUP BY c.User
```

---

**[05_ab_test.ipynb]**

- 쿼리 목적: A/B 테스트용 Activation 데이터 추출
```sql
WITH first_tx AS (
    SELECT User, MIN(date_int) AS first_date, MIN(Year) AS first_year,
        MIN(Month) AS first_month, MIN(Day) AS first_day
    FROM clean_transactions GROUP BY User
),
second_tx AS (
    SELECT c.User, MIN(c.date_int) AS second_date
    FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    WHERE c.date_int > f.first_date
    GROUP BY c.User
)
SELECT
    f.User, f.first_date, s.second_date,
    CASE
        WHEN s.second_date IS NULL THEN 0
        WHEN (s.second_date - f.first_date) <= 30 THEN 1
        ELSE 0
    END AS activated
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User
```

