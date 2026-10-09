# FriendshipTycoon

## 제목
- 우정회관 키우기

## 장르
- incremental
- tycoon

## 게임플레이
1. 기본 자금으로 income source를 구매하여 일정 시간당 일정량의 돈을 번다.
2. income source를 업그레이드하고, income을 multiply하는 여러 버튼들을 구매해 자금을 점점 불려 나간다.
3. 새로운 income source를 구매하고 과정을 반복한다. (경우에 따라서는 먼저 structure를 구매해야 다음 income source가 해금될 수 있다)
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
- 환생으로 확정된 누적 짬(`total_jjam`)과 현재 환생 보상 계산
- EconomyManager에 현재 짬 배율 전달
- (영구 구매는 일단 미구현)

### ErrorManager

- 공통 데이터·참조·수치 검증
- ID 누락·중복, 잘못된 리소스, 순환 해금 조건 검사
- 월드 노드, UI 필수 노드, 텍스처·애니메이션·클릭 영역 검사
- 오류 코드·발생 위치를 포함한 화면 메시지와 콘솔 기록
- 같은 오류의 중복 표시 방지 및 발생 횟수 기록

## 해금 조건

`ButtonData.unlock_condition`에 `UnlockCondition` 리소스를 연결한다.

| Type | 기준 | 설정 |
| --- | --- | --- |
| `MONEY` (0) | 현재 자금 | `amount` 이상이면 해금 |
| `TOTAL_JJAM` (1) | 환생으로 확정된 누적 짬 | `amount`에 0 이상 정수를 지정 |
| `BUTTON` (2) | 선행 버튼 구매 | `value`에 선행 버튼 ID 지정 |

- 기존 `UPGRADE` 자리를 `TOTAL_JJAM`으로 교체했다. 직렬화된 enum 번호는 유지하며, 기존 `MONEY`와 `BUTTON` 조건은 그대로 동작한다.
- 누적 짬은 `PrestigeManager.get_total_jjam()`으로 읽는다. 현재 자금으로 계산한 예상 환생 보상은 해금 기준에 포함하지 않는다.
- 환생 완료 신호(`prestige_changed`)를 받으면 `ButtonManager`가 해금 상태를 다시 계산한다.
- 기존 콘텐츠에 누적 짬 조건을 임의로 지정하지 않았다. 필요한 버튼의 리소스에서 `TOTAL_JJAM`과 `amount`를 설정하면 된다.

## 오류 처리

- `ErrorManager`는 가장 먼저 생성되는 Autoload이며, 오류 메시지는 HUD보다 위인 CanvasLayer 100에 표시한다. `PrestigeManager`는 짬 조건을 검사하는 `ButtonManager`보다 먼저 생성된다.
- 중복 ID는 첫 번째 항목을 임의로 선택하지 않고 조회·구매를 거절한다. 잘못된 수입원은 실행 상태에서 제외하며, 월드 구성이 잘못된 버튼은 구매할 수 없다. 필수 UI 노드가 없으면 해당 화면을 비활성화한다.
- 자금·배율의 유효하지 않은 수치, 소액 증감이 완전히 사라지는 정밀도 손실, 환생 재화의 정수 범위 초과를 알린다. 실패한 결제와 환생은 기존 상태를 유지한다. 큰 수 전용 수치 형식은 아직 구현하지 않았다.
- 같은 `code`와 `context`는 세션 중 한 번만 표시하고 발생 횟수를 누적한다. 서로 다른 오류는 확인 버튼으로 차례대로 볼 수 있으며, 이력은 최대 100개까지 보관한다. 한도를 넘으면 `ERROR_LIMIT` 알림으로 추가 오류가 있음을 알린다.
- 자금 부족, 아직 해금되지 않은 버튼, 중복 클릭, 보상 없는 환생은 정상적인 거절이므로 오류 창을 띄우지 않는다.

다른 게임 로직에서도 같은 경로로 오류를 보고한다.

```gdscript
ErrorManager.report_error("ERROR_CODE", "사용자에게 보여 줄 오류 설명", "발생 위치 또는 ID")
var errors := ErrorManager.get_errors() # 외부에서 수정할 수 없는 이력 사본
ErrorManager.clear_errors() # 이력·대기 메시지·중복 표시 상태 초기화
```

실행 중 보호 경로의 오류를 처리한다. 스크립트 문법 오류나 Autoload 생성 전의 `preload` 실패처럼 게임 시작 자체를 막는 오류는 Godot 디버거·로그에서 확인해야 한다.


## 렌더링
### 장면 깊이
- 하늘(-100) < 구름(-90) < 실내 뒷배경/벽지(-20) < 전경/창문(-10) < 가구/인물/조리대(0) < 앞쪽 테두리/기둥/주춧돌/천장(10) < 땅(20) < 구매 버튼(30) < 설명/생산 타이머/말풍선(40)
- 공통 레이어 이름과 값은 `scripts/RenderOrder.gd`에서 관리한다. 구매 종류(`ButtonData.Type`)와 효과는 렌더링 순서에 관여하지 않는다.
- 월드의 깊이는 `world_layout.tscn`에서 지정한다. 노드에 `SceneRenderLayer.gd`를 연결하고 인스펙터의 `Rendering > Render Layer`를 선택하면 된다. 자식은 부모 레이어를 상속하며, 벽지처럼 다른 깊이인 자식에는 별도로 레이어를 지정한다.
- 구매 후 생성되는 스프라이트는 원본의 부모까지 포함한 실제 z-index를 보존한다. 같은 깊이에서는 월드 레이아웃의 노드 순서를 따른다.
- 화면 설명/툴팁은 CanvasLayer 1, HUD는 CanvasLayer 2에 표시되어 HUD가 월드와 모든 월드 설명보다 앞에 그려진다.
- 회귀 검증: `godot --headless --path . res://tests/render_order_smoke.tscn`. 구매 목록을 역순으로 바꾸고 모든 게임 종류를 같게 설정한 뒤 실제 구매를 진행해, 복제된 스프라이트와 UI의 렌더링 깊이가 유지되는지 확인한다.

## 구조 및 버그 점검
- [점검 결과와 남아 있는 위험](docs/PROJECT_REVIEW.md)
- 계산·구매·환생 UI 회귀 검증: `godot --headless --path . res://tests/runtime_regression.tscn`.
- 누적 짬 해금·잘못된 데이터·오류 표시 검증: `godot --headless --path . res://tests/error_handling_smoke.tscn`.
