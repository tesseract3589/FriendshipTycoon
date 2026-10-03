# FriendshipTycoon

## 제목
- 우정회관 키우기

## 장르
- incremental
- tycoon

## 게임플레이
1. 기본 자금으로 income source를 구매하여 일정 시간당 일정량의 돈을 번다.
2. income source를 업그레이드하고, income을 multiply하는 여러 버튼들을 구매해 자금을 점점 불려 나간다.
3. 새로운 income source를 구매하고 과정을 반복한다.
4. 기하급수적으로 자금을 불리다 보면 '짬'이 모인다. (또 다른 재화)
5. 환생하면 모든 버튼이 초기화되는 대신 그동안 모인 '짬'의 수만큼 multiplier가 적용된다. (1짬 = +1% multiplier)
6. 짬을 사용하여 편의성 업그레이드를 구매할 수 있다. (버튼 원격 구매 등)
7. 짬 또한 기하급수적으로 오르게 된다. 어느 정도 짬이 모이면 2번째 prestige layer인 '재입대'를 할 수 있게 된다.
8. 재입대를 할 시 '무공훈장' 1개가 주어지며, 모든 income source의 생산 시간이 7배 줄어든다.
9. 무공훈장을 사용해 버튼 하나를 영구 구매할 수 있다. 이렇게 하면 어떤 prestige layer로도 초기화되지 않는다.

## 특징
- multiplier가 항상 파격적으로 적용되기 때문에 자금이 기하급수적으로 불어난다.
- integer 범위에서 벗어나는 연산을 해야 할 수 있어서 특수 formula가 필요하다. (10억원 이상은 과학적 표기법을 사용해야 한다)
- 시간 단위도 시간 multiplier에 따라 ps(피코세컨드)당 ~원, as(아토세컨드)당 ~원까지도 내려갈 수 있어서 이를 연산해 주는 특수 formula가 필요하고 과학적 표기법을 사용해야 한다.


## 역할 분담
### EconomyManager
- money
- global_multiplier

### IncomeManager
- Income Source 목록
- Source별 multiplier
- Source 활성화 상태
- 총 income 계산

### ButtonManager
- ButtonData 목록
- 가격
- 구매
- 해금 조건
- IncomeManager에 버튼 구매 신호와 효과 전달

### PrestigeManager
- 짬 환생
- 현재 짬
- EconomyManager에 현재 짬 배율 전달
- (영구 구매는 일단 미구현)
