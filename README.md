# IBM Credit Card Transaction Analysis

> 2,400만 건의 IBM 합성 신용카드 거래 데이터를 활용한 핀테크 도메인 데이터 분석 포트폴리오

---

##  프로젝트 개요

| 항목 | 내용 |
|---|---|
| 데이터 | IBM 합성 신용카드 거래 데이터 (Kaggle) |
| 규모 | 24,386,900건 · 유저 2,000명 · 카드 6,146장 |
| 기간 | 1991 ~ 2019년 |
| 분석 환경 | Python 3.11 · SQLite · MySQL · Tableau Public |
| 목적 | 핀테크 DA 포트폴리오 — 전처리부터 대시보드까지 end-to-end 파이프라인 구축 |

---

##  파일 구조

```
IBM-credit-card-transaction/
├── data/
│   ├── raw/                  # 원본 CSV 3개
│   ├── db/                   # fintech.db (SQLite)
│   └── tableau/              # 분석 결과 CSV 6개
│       ├── aarrr_funnel.csv
│       ├── yearly_trend.csv
│       ├── cohort_behavior.csv
│       ├── rfm_segments.csv
│       ├── ab_test_result.csv
│       └── mcc_category.csv
├── notebooks/
│   ├── 01_data_loading.ipynb
│   ├── 02_eda.ipynb
│   ├── 03_aarrr_funnel.ipynb
│   ├── 04_cohort_ltv.ipynb
│   ├── 05_ab_test.ipynb
│   └── 06_mysql_upload.ipynb
├── sql/
├── outputs/
├── .gitignore
└── README.md
```

---

##  분석 환경

- **Python** 3.11 (conda 가상환경: `ibm-card-analysis`)
- **패키지**: pandas, numpy, scipy, statsmodels, matplotlib, seaborn, sqlalchemy, pymysql
- **DB**: SQLite (fintech.db) · MySQL (ibm_card_analysis)
- **시각화**: Tableau Public

---

##  분석 내용

### 1. 데이터 로딩 (`01_data_loading.ipynb`)

- 2.18GB CSV를 chunk 스트리밍 방식으로 SQLite에 적재
- chunk size 100,000 · 총 24,386,900행 적재 완료

### 2. EDA (`02_eda.ipynb`)

- 결측치 확인: `Errors?` 컬럼 외 주요 컬럼 결측 없음
- 이상치 분석: Amount $5,000 초과 건 별도 처리
- 사기 거래 비율 확인 후 분석 대상에서 제외
- 2020년 데이터 불완전(1월만 존재) 확인 후 제외
- 분석용 뷰 생성: `clean_transactions`, `ltv_transactions`
- MCC 카테고리별 거래 패턴 분석 (Top 20)

### 3. AARRR 퍼널 분석 (`03_aarrr_funnel.ipynb`)

순차 퍼널 방식으로 단계별 전환율 산출

| 단계 | 정의 | 결과 |
|---|---|---|
| Acquisition | 첫 거래 발생 유저 | 1,657명 |
| Activation | 첫 거래 후 30일 내 재거래 | 66.0% |
| Retention | 다음 연도에도 거래 | 97.5% |

- Activation × Retention 교차 분석으로 유저 4개 유형 분류
  - 진성 유저 / 초반 반짝 유저 / 느린 정착형 유저 / 이탈 유저

### 4. Cohort 분석 (`04_cohort_ltv.ipynb`)

- 2002년 이후 코호트 대상 (안정적 데이터 구간)
- Cohort Retention Matrix: 연도별 잔존율 히트맵
- Cohort별 거래 빈도 · 평균 거래금액 변화 추이

### 5. LTV 분석 (`04_cohort_ltv.ipynb`)

- 기간 보정 연간 LTV 산출 (총 거래금액 / 활동 연수)
- 연간 LTV 중앙값: **$43,170**
- 환불·오류·이상치($5,000 초과) 제외한 `ltv_transactions` 기준

### 6. RFM 세그멘테이션 (`04_cohort_ltv.ipynb`)

Recency · Frequency · Monetary 점수화 후 5개 세그먼트 분류

| 세그먼트 | 비율 |
|---|---|
| VIP | 31.5% |
| Loyal | 33.6% |
| Potential | 32.5% |
| At Risk | 0.1% |
| Dormant | 2.3% |

### 7. A/B 테스트 (`05_ab_test.ipynb`)

- Power Analysis로 필요 샘플 수 산출
- 실제 데이터 기반 Activation율을 벤치마크로 활용
- z-test 기반 시뮬레이션으로 유의미한 개선 효과 검증

- 수치 불일치 노트
  : AARRR 퍼널의 Activation(66.0%)과 A/B 테스트 대조군 전환율(67.7%) 간 차이는 분석 대상 모집단이 다르기 때문이다.

  - AARRR: clean_transactions 기준 전체 유저 1,657명
  - A/B 테스트: RFM 세그멘테이션과 일관성을 유지하기 위해 cohort_year >= 2002 조건을 적용한 유저만 대상으로 함

  2002년 이전 코호트 유저는 관측 기간이 길어 데이터 특성이 상이하므로 제외하였으며, 해당 유저들의 Activation율이 상대적으로 낮아 이들을 제외하면 전체 비율이 소폭 상승한다.

### 8. MySQL 업로드 (`06_mysql_upload.ipynb`)

- 50명 샘플 데이터를 MySQL에 적재
- 서비스 DB 구조 재현 목적 (SQLite = DW · MySQL = 서비스 DB)

---

##  Tableau Public 대시보드

[🔗 대시보드 바로가기](https://public.tableau.com/views/IBM_17802005644720/IBMCreditCard?:language=ko-KR&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link) 

6개 시트 → 1개 통합 대시보드

- 연도별 거래 추이
- AARRR 퍼널
- Cohort Retention 히트맵
- RFM 세그먼트 분포
- A/B 테스트 결과
- MCC 카테고리 분석

---

##  주요 인사이트

- **높은 Retention(97.5%)**: 한 번 정착한 유저는 이탈이 거의 없음. 신규 유저 Activation 전략이 핵심 레버
- **VIP + Loyal = 65%**: 전체 유저의 2/3가 고가치 세그먼트. 유지 비용 대비 수익성 우수
- **Activation 병목(66%)**: 첫 거래 후 30일 내 재거래 유도가 최우선 과제
- **연간 LTV 중앙값 $43,170**: 고액 거래 중심 포트폴리오 특성 반영

---

##  기술 스택

`Python` `Pandas` `SQLite` `MySQL` `SQLAlchemy` `Matplotlib` `Seaborn` `Tableau Public` `Jupyter Notebook`
