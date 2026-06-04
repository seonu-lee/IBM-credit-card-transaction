# IBM 신용카드 거래 데이터 분석 - 노트북 코드 정리

## notebooks/01_data_loading.ipynb

```python
import pandas as pd
import sqlite3
import os

DB_PATH = r'..\data\db\fintech.db'
RAW_DIR = r'..\data\raw'

conn = sqlite3.connect(DB_PATH)

# 1. users, cards 먼저
print("1/3 users, cards 적재 중...")
users = pd.read_csv(os.path.join(RAW_DIR, 'sd254_users.csv'))
cards = pd.read_csv(os.path.join(RAW_DIR, 'sd254_cards.csv'))
users.to_sql('users', conn, if_exists='replace', index=False)
cards.to_sql('cards', conn, if_exists='replace', index=False)
print(f"users: {len(users):,}행 / cards: {len(cards):,}행 완료")

# 2. transactions chunk 스트리밍
print("2/3 transactions 적재 중... (10~20분 소요)")
chunk_size = 100000
total = 0
first_chunk = True

for chunk in pd.read_csv(
    os.path.join(RAW_DIR, 'credit_card_transactions-ibm_v2.csv'),
    chunksize=chunk_size
):
    chunk.to_sql(
        'transactions',
        conn,
        if_exists='replace' if first_chunk else 'append',
        index=False
    )
    total += len(chunk)
    first_chunk = False
    print(f"  적재 완료: {total:,}행", end='\r')

print(f"\n3/3 완료! 총 {total:,}행")

# 3. 확인
for table in ['transactions', 'users', 'cards']:
    count = pd.read_sql(f"SELECT COUNT(*) as cnt FROM {table}", conn)
    print(f"{table}: {count['cnt'].values[0]:,}행")

conn.close()
```

---

## notebooks/02_eda.ipynb

### Cell 2 - 테이블 기본 구조 확인

```python
# Cell 2 - 테이블 기본 구조 확인

for table in ['transactions', 'users', 'cards']:
    count = pd.read_sql(f"SELECT COUNT(*) as cnt FROM {table}", conn)
    print(f"{table}: {count['cnt'].values[0]:,}행")
```

### Cell 3 - transactions 샘플 확인

```python
# Cell 3 - transactions 샘플 확인

trans_sample = pd.read_sql("SELECT * FROM transactions LIMIT 5", conn)
print("=== 컬럼 목록 ===")
print(trans_sample.columns.tolist())
print("\n=== 샘플 데이터 ===")
print(trans_sample)
```

### users 테이블 구조 확인

```python
# users 테이블 구조 확인
users_sample = pd.read_sql("SELECT * FROM users LIMIT 5", conn)
print("=== 컬럼 목록 ===")
print(users_sample.columns.tolist())
print("\n=== 샘플 데이터 ===")
print(users_sample)
```

### Cell 4 - 데이터 범위 파악

```python
# Cell 4 - 데이터 범위 파악

range_query = """
SELECT
    MIN(Year) AS min_year,
    MAX(Year) AS max_year,
    COUNT(DISTINCT Year) AS year_count,
    COUNT(DISTINCT Month) AS month_count,
    COUNT(DISTINCT User) AS user_count,
    COUNT(DISTINCT "Merchant Name") AS merchant_count,
    COUNT(DISTINCT MCC) AS mcc_count
FROM transactions
"""
print(pd.read_sql(range_query, conn))
```

### Cell 5 - Amount 전처리 확인

```python
# Cell 5 - Amount 전처리 확인

amount_query = """
SELECT
    MIN(CAST(REPLACE(Amount, '$', '') AS FLOAT)) AS min_amount,
    MAX(CAST(REPLACE(Amount, '$', '') AS FLOAT)) AS max_amount,
    ROUND(AVG(CAST(REPLACE(Amount, '$', '') AS FLOAT)), 2) AS avg_amount,
    SUM(CASE WHEN CAST(REPLACE(Amount, '$', '') AS FLOAT) < 0 
        THEN 1 ELSE 0 END) AS negative_count,
    COUNT(*) AS total_count
FROM transactions
"""
print(pd.read_sql(amount_query, conn))
```

### 음수 거래 상세 확인

```python
# 음수 거래 상세 확인
negative_query = """
SELECT
    use_chip,
    merchant_name,
    merchant_city,
    MCC,
    errors,
    Amount,
    COUNT(*) as cnt
FROM clean_transactions
WHERE Amount < 0
GROUP BY use_chip, MCC
ORDER BY cnt DESC
LIMIT 20
"""
neg_df = pd.read_sql(negative_query, conn)
print(neg_df)
```

### 음수 거래에서 오류 동반 비율

```python
# 음수 거래에서 오류 동반 비율
negative_error_query = """
SELECT
    errors,
    COUNT(*) as cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as ratio
FROM clean_transactions
WHERE Amount < 0
GROUP BY errors
ORDER BY cnt DESC
"""
print(pd.read_sql(negative_error_query, conn))
```

### Cell 6 - 사기 거래 비율

```python
# Cell 6 - 사기 거래 비율

fraud_query = """
SELECT
    "Is Fraud?" AS is_fraud,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 4) AS ratio
FROM transactions
GROUP BY "Is Fraud?"
"""
print(pd.read_sql(fraud_query, conn))
```

### Cell 7 - Errors? 결측치 패턴

```python
# Cell 7 - Errors? 결측치 패턴

error_query = """
SELECT
    "Errors?" AS error_type,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions), 4) AS ratio
FROM transactions
GROUP BY "Errors?"
ORDER BY count DESC
"""
print(pd.read_sql(error_query, conn))
```

### Cell 8 - 전처리된 분석용 뷰 생성

```python
# Cell 8 - 전처리된 분석용 뷰 생성

create_view_query = """
CREATE VIEW IF NOT EXISTS clean_transactions AS
SELECT
    User,
    Card,
    Year,
    Month,
    Day,
    Time,
    -- Amount에서 '$' 제거 후 FLOAT 변환
    CAST(REPLACE(Amount, '$', '') AS FLOAT) AS Amount,
    "Use Chip" AS use_chip,
    "Merchant Name" AS merchant_name,
    "Merchant City" AS merchant_city,
    "Merchant State" AS merchant_state,
    Zip,
    MCC,
    "Errors?" AS errors,
    "Is Fraud?" AS is_fraud,
    -- 날짜 통합 컬럼 추가
    Year * 10000 + Month * 100 + Day AS date_int,
    Year * 100 + Month AS year_month
FROM transactions
WHERE "Is Fraud?" = 'No'
"""

conn.execute(create_view_query)
conn.commit()

# 확인
check = pd.read_sql("SELECT COUNT(*) as cnt FROM clean_transactions", conn)
print(f"clean_transactions: {check['cnt'].values[0]:,}행")
print(f"제외된 사기 거래: {24386900 - check['cnt'].values[0]:,}건")
```

### Cell 9 - LTV용 뷰 (추가로 환불·오류 제외)

```python
# Cell 9 - LTV용 뷰 (추가로 환불·오류 제외)

create_ltv_view_query = """
CREATE VIEW IF NOT EXISTS ltv_transactions AS
SELECT *
FROM clean_transactions
WHERE Amount > 0
AND errors IS NULL
"""

conn.execute(create_ltv_view_query)
conn.commit()

check_ltv = pd.read_sql("SELECT COUNT(*) as cnt FROM ltv_transactions", conn)
print(f"ltv_transactions: {check_ltv['cnt'].values[0]:,}행")
```

### Cell 10 - 결측치 확인

```python
# Cell 10 - 결측치 확인

null_query = """
SELECT
    SUM(CASE WHEN User IS NULL THEN 1 ELSE 0 END) AS user_null,
    SUM(CASE WHEN Amount IS NULL THEN 1 ELSE 0 END) AS amount_null,
    SUM(CASE WHEN Year IS NULL THEN 1 ELSE 0 END) AS year_null,
    SUM(CASE WHEN MCC IS NULL THEN 1 ELSE 0 END) AS mcc_null,
    SUM(CASE WHEN merchant_city IS NULL THEN 1 ELSE 0 END) AS city_null,
    SUM(CASE WHEN merchant_state IS NULL THEN 1 ELSE 0 END) AS state_null,
    SUM(CASE WHEN Zip IS NULL THEN 1 ELSE 0 END) AS zip_null
FROM clean_transactions
"""
print("=== 결측치 확인 ===")
print(pd.read_sql(null_query, conn))
```

### Cell 11 - 이상치 확인 (Amount)

```python
# Cell 11 - 이상치 확인 (Amount)

outlier_query = """
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN Amount > 5000 THEN 1 ELSE 0 END) AS over_5000,
    SUM(CASE WHEN Amount > 10000 THEN 1 ELSE 0 END) AS over_10000,
    ROUND(AVG(Amount), 2) AS avg,
    -- 분포 파악용
    ROUND(MIN(Amount), 2) AS min_amount,
    MAX(Amount) AS max_amount
FROM clean_transactions
WHERE Amount > 0
"""
print("=== Amount 이상치 확인 ===")
print(pd.read_sql(outlier_query, conn))
```

### Cell 12 - MCC 카테고리 분석

```python
# Cell 12 - MCC 카테고리 분석

mcc_query = """
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
"""
print("=== MCC Top 20 ===")
mcc_df = pd.read_sql(mcc_query, conn)
print(mcc_df)
```

### Cell 15 - 연도별 거래 추이

```python
# Cell 15 - 연도별 거래 추이

yearly_query = """
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
"""
yearly = pd.read_sql(yearly_query, conn)
print(yearly)
```

### Cell 16 - 2020년 데이터 월 범위 확인

```python
# Cell 16 - 2020년 데이터 월 범위 확인

year_month_query= """
SELECT
    year_month,
    count(*) AS tx_count
FROM clean_transactions
WHERE year == 2020
GROUP BY year_month
"""
year_month_df = pd.read_sql(year_month_query, conn)
print(year_month_df)
```

### Cell 18 - 2020년 제외한 최종 분석 뷰 재생성

```python
# Cell 18 - 2020년 제외한 최종 분석 뷰 재생성

# 기존 뷰 삭제 후 재생성
conn.execute("DROP VIEW IF EXISTS clean_transactions")
conn.execute("DROP VIEW IF EXISTS ltv_transactions")

conn.execute("""
CREATE VIEW clean_transactions AS
SELECT
    User,
    Card,
    Year,
    Month,
    Day,
    Time,
    CAST(REPLACE(Amount, '$', '') AS FLOAT) AS Amount,
    "Use Chip" AS use_chip,
    "Merchant Name" AS merchant_name,
    "Merchant City" AS merchant_city,
    "Merchant State" AS merchant_state,
    Zip,
    MCC,
    "Errors?" AS errors,
    "Is Fraud?" AS is_fraud,
    Year * 10000 + Month * 100 + Day AS date_int,
    Year * 100 + Month AS year_month
FROM transactions
WHERE "Is Fraud?" = 'No'
AND Year < 2020
""")

conn.execute("""
CREATE VIEW ltv_transactions AS
SELECT *
FROM clean_transactions
WHERE Amount > 0
AND errors IS NULL
-- 이상치가 평균을 왜곡할 수 있어 LTV 계산에서는 제외
AND Amount <= 5000
""")

conn.commit()

# 확인
for view in ['clean_transactions', 'ltv_transactions']:
    count = pd.read_sql(f"SELECT COUNT(*) as cnt FROM {view}", conn)
    print(f"{view}: {count['cnt'].values[0]:,}행")
```

---

## notebooks/03_aarrr_funnel.ipynb

### Cell 2 - Acquisition: 연도별 신규 유저 수

```python
# Cell 2 - Acquisition: 연도별 신규 유저 수

acquisition_query = """
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
ORDER BY first_year
"""

acquisition = pd.read_sql(acquisition_query, conn)
print("=== Acquisition: 연도별 신규 유저 ===")
print(acquisition)
```

### 유저 수 확인 쿼리

```python
# 유저 수 확인 쿼리

# 1. 전체 transactions에서 유저 수
q1 = pd.read_sql("SELECT COUNT(DISTINCT User) as cnt FROM transactions", conn)
print(f"전체 transactions 유저 수: {q1['cnt'].values[0]}")

# 2. 사기 제외 후
q2 = pd.read_sql("SELECT COUNT(DISTINCT User) as cnt FROM transactions WHERE \"Is Fraud?\" = 'No'", conn)
print(f"사기 제외 후 유저 수: {q2['cnt'].values[0]}")

# 3. 2020년 제외 후
q3 = pd.read_sql("SELECT COUNT(DISTINCT User) as cnt FROM clean_transactions", conn)
print(f"2020년 제외 후 유저 수: {q3['cnt'].values[0]}")

# 4. users 테이블
q4 = pd.read_sql("SELECT COUNT(DISTINCT person) as cnt FROM users", conn)
print(f"users 테이블 유저 수: {q4['cnt'].values[0]}")
```

### Cell 4 - Activation: 첫 거래 후 30일 이내 재거래 비율

```python
# Cell 4 - Activation: 첫 거래 후 30일 이내 재거래 비율

activation_query = """
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year) AS first_year
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
LEFT JOIN second_tx s ON f.User = s.User
"""

activation = pd.read_sql(activation_query, conn)
print("=== Activation ===")
print(activation)
```

### Cell 5 - Retention: 첫 거래 다음 연도에도 거래한 유저 비율

```python
# Cell 5 - Retention: 첫 거래 다음 연도에도 거래한 유저 비율

retention_query = """
WITH first_year AS (
    SELECT
        User,
        MIN(Year) AS first_year
    FROM clean_transactions
    GROUP BY User
),
next_year_tx AS (
    SELECT DISTINCT
        c.User
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
LEFT JOIN next_year_tx n ON f.User = n.User
"""

retention = pd.read_sql(retention_query, conn)
print("=== Retention (1년 후) ===")
print(retention)
```

### Cell 6 - Revenue: 유저별 총 거래금액

```python
# Cell 6 - Revenue: 유저별 총 거래금액

revenue_query = """
SELECT
    COUNT(DISTINCT User) AS total_users,
    ROUND(AVG(total_amount), 2) AS avg_ltv,
    ROUND(MIN(total_amount), 2) AS min_ltv,
    ROUND(MAX(total_amount), 2) AS max_ltv,
    -- 중앙값 대신 사분위수
    COUNT(CASE WHEN total_amount > 10000 THEN 1 END) AS high_value_users
FROM (
    SELECT
        User,
        SUM(Amount) AS total_amount
    FROM ltv_transactions
    GROUP BY User
)
"""

revenue = pd.read_sql(revenue_query, conn)
print("=== Revenue ===")
print(revenue)
```

### Cell 8 - Activation × Retention 교차 분석

```python
# Cell 8 - Activation × Retention 교차 분석

cross_query = """
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year) AS first_year
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
),
next_year AS (
    SELECT DISTINCT
        c.User
    FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    WHERE c.Year = f.first_year + 1
),
user_flags AS (
    SELECT
        f.User,
        CASE WHEN (s.second_date - f.first_date) <= 30
            THEN 1 ELSE 0 END AS is_activated,
        CASE WHEN n.User IS NOT NULL
            THEN 1 ELSE 0 END AS is_retained
    FROM first_tx f
    LEFT JOIN second_tx s ON f.User = s.User
    LEFT JOIN next_year n ON f.User = n.User
)
SELECT
    CASE
        WHEN is_activated = 1 AND is_retained = 1 THEN '진성 유저'
        WHEN is_activated = 1 AND is_retained = 0 THEN '초반 반짝 유저'
        WHEN is_activated = 0 AND is_retained = 1 THEN '느린 정착형 유저'
        ELSE '이탈 유저'
    END AS user_type,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM first_tx), 2) AS ratio
FROM user_flags
GROUP BY user_type
ORDER BY user_count DESC
"""

cross = pd.read_sql(cross_query, conn)
print("=== Activation × Retention 유저 세그멘테이션 ===")
print(cross)
```

### Cell 10 - AARRR 순차 FUNNEL

```python
# Cell 10 - AARRR 순차 FUNNEL

funnel_query = """
WITH 
-- Step 1: Acquisition (첫 거래 유저)
acquisition AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year) AS first_year
    FROM clean_transactions
    GROUP BY User
),
-- Step 2: Activation (Acquisition 유저 중 30일 내 재거래)
activation AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
    JOIN acquisition a ON c.User = a.User
    WHERE c.date_int > a.first_date
    AND (c.date_int - a.first_date) <= 30
),
-- Step 3: Retention (Activation 유저 중 다음 연도에도 거래)
retention AS (
    SELECT DISTINCT c.User
    FROM clean_transactions c
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
LEFT JOIN retention r ON a.User = r.User
"""

funnel = pd.read_sql(funnel_query, conn)
print("=== 순차 퍼널 ===")
print(funnel)
print(f"\nAcquisition → Activation : {funnel['activation'].values[0]/funnel['acquisition'].values[0]*100:.1f}%")
print(f"Activation  → Retention  : {funnel['retention'].values[0]/funnel['activation'].values[0]*100:.1f}%")
```

---

## notebooks/04_cohort_ltv.ipynb

### Cell 2 - Cohort 기준 정의

```python
# Cell 2 - Cohort 기준 정의
# 유저별 첫 거래 연도 (30년치 데이터라서 월 말고 연도로 구분)= Cohort 기준

cohort_base_query = """
SELECT
    User,
    MIN(Year) AS cohort_year
FROM clean_transactions
GROUP BY User
"""

cohort_base = pd.read_sql(cohort_base_query, conn)
print(f"전체 유저 수: {len(cohort_base):,}명")
print(f"Cohort 연도 범위: {cohort_base['cohort_year'].min()} ~ {cohort_base['cohort_year'].max()}")
print(cohort_base['cohort_year'].value_counts().sort_index()) # Cohort별 유저 수 확인
```

### Cell 3 - Cohort Retention Matrix 계산

```python
# Cell 3 - Cohort Retention Matrix 계산

cohort_retention_query = """
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year
    FROM clean_transactions
    WHERE Year >= 2002
    GROUP BY User
),
user_activity AS (
    SELECT DISTINCT
        c.User,
        cb.cohort_year,
        c.Year AS active_year,
        (c.Year - cb.cohort_year) AS years_since_first
    FROM clean_transactions c
    JOIN cohort_base cb ON c.User = cb.User
    WHERE c.Year >= cb.cohort_year
),
cohort_size AS (
    SELECT
        cohort_year,
        COUNT(DISTINCT User) AS cohort_users
    FROM cohort_base
    GROUP BY cohort_year
)
SELECT
    ua.cohort_year,
    ua.years_since_first,
    COUNT(DISTINCT ua.User) AS retained_users,
    cs.cohort_users,
    ROUND(COUNT(DISTINCT ua.User) * 100.0 / cs.cohort_users, 1) AS retention_rate
FROM user_activity ua
JOIN cohort_size cs ON ua.cohort_year = cs.cohort_year
GROUP BY ua.cohort_year, ua.years_since_first
ORDER BY ua.cohort_year, ua.years_since_first
"""

cohort_data = pd.read_sql(cohort_retention_query, conn)
print(f"데이터 shape: {cohort_data.shape}")
print(cohort_data.head(20))
```

### 확인용 쿼리

```python
# 확인용 쿼리
check_query = """
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year
    FROM clean_transactions
    WHERE Year >= 2002
    GROUP BY User
)
SELECT cohort_year, COUNT(*) as user_count
FROM cohort_base
GROUP BY cohort_year
ORDER BY cohort_year
"""
print(pd.read_sql(check_query, conn))
```

### Cell 3 수정 - Cohort Retention Matrix

```python
# Cell 3 수정 - Cohort Retention Matrix

cohort_retention_query = """
WITH cohort_base AS (
    -- 전체 데이터에서 진짜 첫 거래 연도
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
        c.Year AS active_year,
        (c.Year - fc.cohort_year) AS years_since_first
    FROM clean_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    WHERE c.Year >= fc.cohort_year
),
cohort_size AS (
    SELECT cohort_year, COUNT(DISTINCT User) AS cohort_users
    FROM filtered_cohort
    GROUP BY cohort_year
)
SELECT
    ua.cohort_year,
    ua.years_since_first,
    COUNT(DISTINCT ua.User) AS retained_users,
    cs.cohort_users,
    ROUND(COUNT(DISTINCT ua.User) * 100.0 / cs.cohort_users, 1) AS retention_rate
FROM user_activity ua
JOIN cohort_size cs ON ua.cohort_year = cs.cohort_year
GROUP BY ua.cohort_year, ua.years_since_first
ORDER BY ua.cohort_year, ua.years_since_first
"""

cohort_data = pd.read_sql(cohort_retention_query, conn)

# 2002년 코호트 유저 수 확인
print("코호트별 유저 수 확인:")
print(cohort_data[cohort_data['years_since_first']==0][['cohort_year','cohort_users']])
```

### Cell 6 - 코호트별 거래 빈도·금액 변화

```python
# Cell 6 - 코호트별 거래 빈도·금액 변화

cohort_behavior_query = """
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
    (c.Year - fc.cohort_year) AS years_since_first,
    COUNT(*) AS total_tx,
    COUNT(DISTINCT c.User) AS active_users,
    cs.cohort_users,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT c.User), 1) AS avg_tx_per_user,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END)
        / COUNT(DISTINCT c.User), 0) AS avg_revenue_per_user
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
JOIN cohort_size cs ON fc.cohort_year = cs.cohort_year
WHERE c.Year >= fc.cohort_year
GROUP BY fc.cohort_year, years_since_first
ORDER BY fc.cohort_year, years_since_first
"""

cohort_behavior = pd.read_sql(cohort_behavior_query, conn)

# 확인
print("2002년 코호트 유저 수:", cohort_behavior[cohort_behavior['cohort_year']==2002]['cohort_users'].values[0])
print(cohort_behavior.head(10))
```

### 2011, 2012년 코호트 유저 특성 확인

```python
# 2011, 2012년 코호트 유저 특성 확인
check_query = """
SELECT
    cb.cohort_year,
    COUNT(DISTINCT cb.User) AS user_count,
    ROUND(AVG(u."FICO Score"), 0) AS avg_fico,
    ROUND(AVG(CAST(REPLACE(u."Yearly Income - Person", '$', '') AS FLOAT)), 0) AS avg_income,
    ROUND(AVG(u."Current Age"), 1) AS avg_age
FROM (
    SELECT User, MIN(Year) AS cohort_year
    FROM clean_transactions
    GROUP BY User
) cb
JOIN users u ON cb.User = u.rowid - 1
WHERE cb.cohort_year BETWEEN 2009 AND 2014
GROUP BY cb.cohort_year
ORDER BY cb.cohort_year
"""
print(pd.read_sql(check_query, conn))
```

### 실제 관찰된 평균 사용 기간

```python
# 실제 관찰된 평균 사용 기간
actual_lifespan_query = """
WITH cohort_base AS (
    SELECT
        User,
        MIN(Year) AS cohort_year,
        MAX(Year) AS last_year,
        (MAX(Year) - MIN(Year)) AS observed_years
    FROM clean_transactions
    GROUP BY User
)
SELECT
    cohort_year,
    COUNT(*) AS user_count,
    ROUND(AVG(observed_years), 1) AS avg_observed_years,
    ROUND(MIN(observed_years), 1) AS min_years,
    ROUND(MAX(observed_years), 1) AS max_years
FROM cohort_base
WHERE cohort_year >= 2002
AND cohort_year <= 2018
GROUP BY cohort_year
ORDER BY cohort_year
"""
print(pd.read_sql(actual_lifespan_query, conn))
```

### Cell 10 - 기간 보정 연간 LTV 계산

```python
# Cell 10 - 기간 보정 연간 LTV 계산

ltv_query = """
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year, MAX(Year) AS last_year
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
        COUNT(*) AS total_tx
    FROM ltv_transactions c
    JOIN filtered_cohort fc ON c.User = fc.User
    GROUP BY c.User
)
SELECT
    fc.User,
    fc.cohort_year,
    fc.last_year,
    CASE
        WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1 -- 0으로 나누는 경우 방지 
        ELSE (fc.last_year - fc.cohort_year)
    END AS active_years,
    ur.total_revenue,
    ur.total_tx,
    ROUND(ur.total_revenue /
        CASE
            WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
            ELSE (fc.last_year - fc.cohort_year)
        END, 0) AS annual_ltv, -- 총 거래금액 / 활동 연수 = 연간 평균 거래금액
    ROUND(ur.total_tx /
        CASE
            WHEN (fc.last_year - fc.cohort_year) = 0 THEN 1
            ELSE (fc.last_year - fc.cohort_year)
        END, 0) AS annual_tx -- 총 거래횟수 / 활동 연수 = 연간 평균 거래횟수
FROM filtered_cohort fc
JOIN user_revenue ur ON fc.User = ur.User
"""

ltv_df = pd.read_sql(ltv_query, conn)
print(f"LTV 계산 완료: {len(ltv_df):,}명")
print(ltv_df.describe())
```

### Cell 12 - RFM 계산

```python
# Cell 12 - RFM 계산

rfm_query = """
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
    -- Recency: 마지막 거래 연도가 높을수록 최근
    (2019 - MAX(c.Year)) AS recency_years,
    -- Frequency: 연간 평균 거래 횟수
    ROUND(COUNT(*) * 1.0 /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
        ELSE (MAX(c.Year) - MIN(c.Year)) END, 0) AS frequency,
    -- Monetary: 연간 평균 거래금액
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END) /
        CASE WHEN (MAX(c.Year) - MIN(c.Year)) = 0 THEN 1
        ELSE (MAX(c.Year) - MIN(c.Year)) END, 0) AS monetary
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
GROUP BY c.User
"""

rfm_df = pd.read_sql(rfm_query, conn)
print(f"RFM 계산 완료: {len(rfm_df):,}명")
print(rfm_df.describe())
```

### Cell 16 - 세그먼트별 행동 비교

```python
# Cell 16 - 세그먼트별 행동 비교

# rfm_df에 segment 붙여서 transactions와 조인
segment_behavior_query = """
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
    c.MCC,
    c.Amount,
    c.use_chip,
    c.Year,
    c.Month
FROM clean_transactions c
JOIN filtered_cohort fc ON c.User = fc.User
WHERE c.Amount > 0
"""

behavior_df = pd.read_sql(segment_behavior_query, conn)

# rfm_df의 segment 붙이기
behavior_df = behavior_df.merge(
    rfm_df[['User', 'segment']], on='User', how='left'
)
print(f"행동 데이터: {len(behavior_df):,}행")
display(behavior_df['segment'].value_counts())
```

---

## notebooks/05_ab_test.ipynb

### Cell 1 - 라이브러리 및 DB 연결

```python
# notebooks/05_ab_test.ipynb
# Cell 1 - 라이브러리 및 DB 연결

import pandas as pd
import sqlite3
import numpy as np
from scipy import stats
import statsmodels.stats.power as smp
import matplotlib.pyplot as plt
import seaborn as sns

DB_PATH = r'..\data\db\fintech.db'
conn = sqlite3.connect(DB_PATH)
print("DB 연결 완료")
```

### Cell 5 - 실제 데이터 기반 시뮬레이션 준비

```python
# Cell 5 - 실제 데이터 기반 시뮬레이션 준비
# 첫 거래 후 30일 내 재거래 여부 데이터 추출

activation_query = """
WITH first_tx AS (
    SELECT
        User,
        MIN(date_int) AS first_date,
        MIN(Year) AS first_year,
        MIN(Month) AS first_month,
        MIN(Day) AS first_day
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
        WHEN s.second_date IS NULL THEN 0
        WHEN (s.second_date - f.first_date) <= 30 THEN 1
        ELSE 0
    END AS activated
FROM first_tx f
LEFT JOIN second_tx s ON f.User = s.User
"""

activation_df = pd.read_sql(activation_query, conn)
print(f"전체 유저: {len(activation_df):,}명")
print(f"Activated: {activation_df['activated'].sum():,}명")
print(f"실제 Activation율: {activation_df['activated'].mean():.4f} ({activation_df['activated'].mean()*100:.1f}%)")
```

### Cell 6 앞에 추가 - rfm_df 다시 계산

```python
# Cell 6 앞에 추가 - rfm_df 다시 계산

rfm_query = """
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
"""

rfm_df = pd.read_sql(rfm_query, conn)

# R 점수
def recency_score(years):
    if years == 0:    return 5
    elif years <= 2:  return 4
    elif years <= 5:  return 3
    elif years <= 9:  return 2
    else:             return 1

rfm_df['R'] = rfm_df['recency_years'].apply(recency_score)
rfm_df['F'] = pd.qcut(rfm_df['frequency'].rank(method='first'),
                       q=5, labels=[1,2,3,4,5]).astype(int)
rfm_df['M'] = pd.qcut(rfm_df['monetary'].rank(method='first'),
                       q=5, labels=[1,2,3,4,5]).astype(int)
rfm_df['RFM_score'] = rfm_df['R'] + rfm_df['F'] + rfm_df['M']

def classify_rfm(row):
    score = row['RFM_score']
    r = row['R']
    f = row['F']
    m = row['M']
    if score >= 13:   return 'VIP'
    elif score >= 10: return 'Loyal'
    elif score >= 7:  return 'Potential'
    elif r <= 2 and (f >= 3 or m >= 3): return 'At Risk'
    else:             return 'Dormant'

rfm_df['segment'] = rfm_df.apply(classify_rfm, axis=1)
print(f"RFM 완료: {len(rfm_df):,}명")
print(rfm_df['segment'].value_counts())
```

### Cell 8 - z-test 통계 검정

```python
# Cell 8 - z-test 통계 검정

from statsmodels.stats.proportion import proportions_ztest, proportion_confint

count = np.array([
    treatment_sim['activated'].sum(),
    control['activated'].sum()
])
nobs = np.array([n_per_group, n_per_group])

z_stat, p_value = proportions_ztest(count, nobs, alternative='larger')

print("=== 통계 검정 결과 (단측 z-test) ===")
print(f"Z 통계량: {z_stat:.4f}")
print(f"p-value: {p_value:.4f}")
print(f"유의수준 α: 0.05")
print(f"\n결론: {'✓ 귀무가설 기각 (통계적으로 유의미)' if p_value < 0.05 else '✗ 귀무가설 채택 (유의미하지 않음)'}")

ci_control = proportion_confint(
    control['activated'].sum(), n_per_group, alpha=0.05, method='normal')
ci_treatment = proportion_confint(
    treatment_sim['activated'].sum(), n_per_group, alpha=0.05, method='normal')

print(f"\n대조군 95% 신뢰구간: [{ci_control[0]:.3f}, {ci_control[1]:.3f}]")
print(f"실험군 95% 신뢰구간: [{ci_treatment[0]:.3f}, {ci_treatment[1]:.3f}]")
```

---

## notebooks/06_mysql_upload.ipynb

### 샘플 200명 추출 및 Tableau용 CSV 저장

```python
# VS Code에서 실행
# notebooks/06_mysql_upload.ipynb

import pandas as pd
import sqlite3
import random

# SQLite에서 샘플 200명 추출
DB_PATH = r'..\data\db\fintech.db'
conn_sqlite = sqlite3.connect(DB_PATH)

random.seed(42)
sample_users = random.sample(range(2000), 200)

print("샘플 유저 추출 중...")

# transactions 샘플
trans_sample = pd.read_sql(f"""
    SELECT * FROM transactions
    WHERE User IN ({','.join(map(str, sample_users))})
    AND "Is Fraud?" = 'No'
    AND Year < 2020
""", conn_sqlite)

# users, cards 샘플
users_sample = pd.read_sql(f"""
    SELECT * FROM users
    WHERE rowid - 1 IN ({','.join(map(str, sample_users))})
""", conn_sqlite)

cards_sample = pd.read_sql(f"""
    SELECT * FROM cards
    WHERE User IN ({','.join(map(str, sample_users))})
""", conn_sqlite)

conn_sqlite.close()

print(f"transactions: {len(trans_sample):,}행")
print(f"users: {len(users_sample):,}행")
print(f"cards: {len(cards_sample):,}행")

# CSV로 저장 (MySQL import용)
trans_sample.to_csv(r'..\data\raw\trans_sample.csv', index=False)
users_sample.to_csv(r'..\data\raw\users_sample.csv', index=False)
cards_sample.to_csv(r'..\data\raw\cards_sample.csv', index=False)
print("CSV 저장 완료!")
```

### transactions 50명 샘플 MySQL 업로드

```python
import pandas as pd
import sqlite3
import random
from sqlalchemy import create_engine

# SQLite에서 50명만 추출
DB_PATH = r'..\data\db\fintech.db'
conn_sqlite = sqlite3.connect(DB_PATH)

random.seed(42)
sample_users_50 = random.sample(range(2000), 50)

print("50명 샘플 추출 중...")

trans_50 = pd.read_sql(f"""
    SELECT * FROM transactions
    WHERE "User" IN ({','.join(map(str, sample_users_50))})
    AND "Is Fraud?" = 'No'
    AND Year < 2020
""", conn_sqlite)

conn_sqlite.close()
print(f"transactions: {len(trans_50):,}행")

# MySQL 업로드
engine = create_engine('mysql+pymysql://root:**@localhost:3306/ibm_card_analysis')

print("MySQL 업로드 중...")
trans_50.to_sql(
    'transactions',
    engine,
    if_exists='replace',
    index=False,
    chunksize=50000
)
print(f"완료! {len(trans_50):,}행")
```

### users, cards 50명 샘플 MySQL 업로드

```python
import pandas as pd
import sqlite3
import random
from sqlalchemy import create_engine

DB_PATH = r'..\data\db\fintech.db'
conn_sqlite = sqlite3.connect(DB_PATH)

# 아까 50명 샘플 동일하게 사용
random.seed(42)
sample_users_50 = random.sample(range(2000), 50)

# users 50명 추출
users_50 = pd.read_sql(f"""
    SELECT * FROM users
    WHERE rowid - 1 IN ({','.join(map(str, sample_users_50))})
""", conn_sqlite)

# cards 50명 추출
cards_50 = pd.read_sql(f"""
    SELECT * FROM cards
    WHERE User IN ({','.join(map(str, sample_users_50))})
""", conn_sqlite)

conn_sqlite.close()

print(f"users: {len(users_50)}명")
print(f"cards: {len(cards_50)}개")

# MySQL 업로드
engine = create_engine('mysql+pymysql://root:**@localhost:3306/ibm_card_analysis')

users_50.to_sql('users', engine, if_exists='replace', index=False)
cards_50.to_sql('cards', engine, if_exists='replace', index=False)
print("완료!")
```

### Tableau용 CSV 추출 (SQLite 전체 데이터 기반)

```python
# Tableau용 CSV 추출 (SQLite 전체 데이터 기반)
import pandas as pd
import sqlite3

DB_PATH = r'..\data\db\fintech.db'
conn = sqlite3.connect(DB_PATH)
OUTPUT = r'..\data\tableau'

import os
os.makedirs(OUTPUT, exist_ok=True)

# 1. AARRR 퍼널
aarrr = pd.read_sql("""
WITH first_tx AS (
    SELECT User, MIN(date_int) AS first_date, MIN(Year) AS first_year
    FROM clean_transactions GROUP BY User
),
activation AS (
    SELECT DISTINCT c.User FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    WHERE c.date_int > f.first_date
    AND (c.date_int - f.first_date) <= 30
),
retention AS (
    SELECT DISTINCT c.User FROM clean_transactions c
    JOIN first_tx f ON c.User = f.User
    JOIN activation a ON c.User = a.User
    WHERE c.Year = f.first_year + 1
)
SELECT
    'Acquisition' AS stage, COUNT(DISTINCT f.User) AS users, 1 AS order_num FROM first_tx f
UNION ALL
SELECT 'Activation', COUNT(DISTINCT a.User), 2 FROM first_tx f JOIN activation a ON f.User = a.User
UNION ALL
SELECT 'Retention', COUNT(DISTINCT r.User), 3 FROM first_tx f JOIN activation a ON f.User = a.User JOIN retention r ON f.User = r.User
""", conn)
aarrr.to_csv(f'{OUTPUT}/aarrr_funnel.csv', index=False)
print("1. AARRR 완료")

# 2. 연도별 거래 추이
yearly = pd.read_sql("""
SELECT Year,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT User) AS active_users,
    ROUND(AVG(Amount), 2) AS avg_amount,
    ROUND(SUM(CASE WHEN Amount > 0 THEN Amount ELSE 0 END), 0) AS total_revenue
FROM clean_transactions
WHERE Amount > 0
GROUP BY Year ORDER BY Year
""", conn)
yearly.to_csv(f'{OUTPUT}/yearly_trend.csv', index=False)
print("2. 연도별 추이 완료")

# 3. Cohort 거래 빈도
cohort = pd.read_sql("""
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year FROM clean_transactions GROUP BY User
),
filtered AS (
    SELECT User, cohort_year FROM cohort_base WHERE cohort_year >= 2002
)
SELECT fc.cohort_year, (c.Year - fc.cohort_year) AS years_since_first,
    COUNT(DISTINCT c.User) AS active_users,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT c.User), 1) AS avg_tx_per_user,
    ROUND(SUM(CASE WHEN c.Amount > 0 THEN c.Amount ELSE 0 END)
        / COUNT(DISTINCT c.User), 0) AS avg_revenue_per_user
FROM clean_transactions c
JOIN filtered fc ON c.User = fc.User
WHERE c.Year >= fc.cohort_year
AND (c.Year - fc.cohort_year) BETWEEN 1 AND 17
GROUP BY fc.cohort_year, years_since_first
ORDER BY fc.cohort_year, years_since_first
""", conn)
cohort.to_csv(f'{OUTPUT}/cohort_behavior.csv', index=False)
print("3. Cohort 완료")

# 4. RFM 세그먼트
rfm = pd.read_sql("""
WITH cohort_base AS (
    SELECT User, MIN(Year) AS cohort_year FROM clean_transactions GROUP BY User
),
filtered AS (SELECT User, cohort_year FROM cohort_base WHERE cohort_year >= 2002)
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
JOIN filtered fc ON c.User = fc.User
GROUP BY c.User
""", conn)

def recency_score(y):
    if y == 0: return 5
    elif y <= 2: return 4
    elif y <= 5: return 3
    elif y <= 9: return 2
    else: return 1

import numpy as np
rfm['R'] = rfm['recency_years'].apply(recency_score)
rfm['F'] = pd.qcut(rfm['frequency'].rank(method='first'), q=5, labels=[1,2,3,4,5]).astype(int)
rfm['M'] = pd.qcut(rfm['monetary'].rank(method='first'), q=5, labels=[1,2,3,4,5]).astype(int)
rfm['RFM_score'] = rfm['R'] + rfm['F'] + rfm['M']

def classify_rfm(row):
    score, r, f, m = row['RFM_score'], row['R'], row['F'], row['M']
    if score >= 13: return 'VIP'
    elif score >= 10: return 'Loyal'
    elif score >= 7: return 'Potential'
    elif r <= 2 and (f >= 3 or m >= 3): return 'At Risk'
    else: return 'Dormant'

rfm['segment'] = rfm.apply(classify_rfm, axis=1)
rfm.to_csv(f'{OUTPUT}/rfm_segments.csv', index=False)
print("4. RFM 완료")

# 5. A/B 테스트 결과
ab_result = pd.DataFrame({
    'group': ['대조군', '실험군(임의)', '실험군(벤치마크)'],
    'conversion_rate': [67.7, 79.1, 75.6],
    'n': [316, 316, 316],
    'p_value': [None, 0.0006, 0.0137]
})
ab_result.to_csv(f'{OUTPUT}/ab_test_result.csv', index=False)
print("5. A/B 테스트 완료")

# 6. MCC 카테고리별 거래
mcc = pd.read_sql("""
SELECT MCC,
    COUNT(*) AS tx_count,
    ROUND(AVG(Amount), 2) AS avg_amount,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM clean_transactions), 2) AS ratio
FROM clean_transactions
WHERE Amount > 0
GROUP BY MCC
ORDER BY tx_count DESC
LIMIT 20
""", conn)
mcc_mapping = {
    5411:'슈퍼마켓', 5499:'식료품점', 5541:'주유소', 5812:'음식점',
    5912:'약국', 4829:'금융서비스', 4784:'교통(유료도로)', 5300:'대형마트',
    4121:'택시/차량', 7538:'자동차수리', 5814:'패스트푸드', 5311:'백화점',
    4900:'공과금', 5310:'할인마트', 5813:'주류', 5942:'서점',
    4814:'통신', 5211:'건축자재', 7832:'영화관', 5921:'편의점'
}
mcc['category'] = mcc['MCC'].map(mcc_mapping).fillna('기타')
mcc.to_csv(f'{OUTPUT}/mcc_category.csv', index=False)
print("6. MCC 카테고리 완료")

conn.close()
print("\n전체 CSV 추출 완료! data/tableau/ 폴더 확인해봐요")
```

---

## notebooks/07_bigquery_upload.ipynb

### BigQuery 클라이언트 초기화

```python
import pandas as pd
from google.cloud import bigquery
from pathlib import Path

# 프로젝트 설정
PROJECT_ID = "project-08140dda-e851-4d93-b88"
DATASET_ID = "ibm_card_analysis"
DATA_DIR = Path("../data/tableau")

# BigQuery 클라이언트 초기화 (ADC 자동 참조)
client = bigquery.Client(project=PROJECT_ID)
print(f"인증 완료: {client.project}")
```

### Tableau용 CSV → BigQuery 업로드

```python
def upload_csv_to_bq(file_name: str, table_name: str):
    file_path = DATA_DIR / file_name
    df = pd.read_csv(file_path)
    
    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    
    job_config = bigquery.LoadJobConfig(
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()  # 완료까지 대기
    
    table = client.get_table(table_id)
    print(f"[완료] {table_name} → {table.num_rows}행 {len(table.schema)}열 업로드")

# 업로드 대상 목록
targets = [
    ("aarrr_funnel.csv",    "aarrr_funnel"),
    ("yearly_trend.csv",    "yearly_trend"),
    ("cohort_behavior.csv", "cohort_behavior"),
    ("rfm_segments.csv",    "rfm_segments"),
    ("ab_test_result.csv",  "ab_test_result"),
    ("mcc_category.csv",    "mcc_category"),
]

for file_name, table_name in targets:
    upload_csv_to_bq(file_name, table_name)
```

### GCS 버킷 연결

```python
from google.cloud import storage

# GCS 설정
BUCKET_NAME = "ibm-card-raw-data"
RAW_DIR = Path("../data/raw")

# GCS 클라이언트 초기화
storage_client = storage.Client(project=PROJECT_ID)
bucket = storage_client.bucket(BUCKET_NAME)

print(f"GCS 버킷 연결 완료: {BUCKET_NAME}")
```

### 원본 CSV → GCS 업로드

```python
import os

def upload_to_gcs(file_name: str):
    file_path = RAW_DIR / file_name
    blob = bucket.blob(file_name)
    
    file_size = os.path.getsize(file_path) / (1024 ** 2)  # MB
    print(f"업로드 시작: {file_name} ({file_size:.1f} MB)")
    
    blob.upload_from_filename(str(file_path))
    print(f"[완료] GCS 업로드: gs://{BUCKET_NAME}/{file_name}\n")

raw_files = [
    "credit_card_transactions-ibm_v2.csv",
    "sd254_cards.csv",
    "sd254_users.csv",
]

for file_name in raw_files:
    upload_to_gcs(file_name)
```

### GCS → BigQuery 로드

```python
def load_gcs_to_bq(file_name: str, table_name: str):
    uri = f"gs://{BUCKET_NAME}/{file_name}"
    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    
    job_config = bigquery.LoadJobConfig(
    autodetect=True,
    source_format=bigquery.SourceFormat.CSV,
    skip_leading_rows=1,
    write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    column_name_character_map="V2",
)
    
    print(f"BigQuery 로드 시작: {uri}")
    job = client.load_table_from_uri(uri, table_id, job_config=job_config)
    job.result()  # 완료까지 대기
    
    table = client.get_table(table_id)
    print(f"[완료] {table_name} → {table.num_rows:,}행 {len(table.schema)}열 로드\n")

targets = [
    ("credit_card_transactions-ibm_v2.csv", "transactions"),
    ("sd254_cards.csv",                     "cards"),
    ("sd254_users.csv",                     "users"),
]

for file_name, table_name in targets:
    load_gcs_to_bq(file_name, table_name)
```