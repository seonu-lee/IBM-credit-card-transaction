import pandas as pd

df = pd.read_csv("C:\\Users\\seonu\\OneDrive\\바탕 화면\\archive (8)\\credit_card_transactions-ibm_v2.csv", nrows=5)
print(df.shape)
print(df.columns.tolist())
print(df.head())

############################

# 전체 행 수만 빠르게 확인
df = pd.read_csv("C:\\Users\\seonu\\OneDrive\\바탕 화면\\archive (8)\\credit_card_transactions-ibm_v2.csv", usecols=['User'])
print(f'전체 거래 수: {len(df):,}')

# users, cards는 작으니까 바로 확인
users = pd.read_csv("C:\\Users\\seonu\\OneDrive\\바탕 화면\\archive (8)\\sd254_users.csv")
cards = pd.read_csv("C:\\Users\\seonu\\OneDrive\\바탕 화면\\archive (8)\\sd254_cards.csv")
print(f'유저 수: {len(users):,}')
print(f'카드 수: {len(cards):,}')