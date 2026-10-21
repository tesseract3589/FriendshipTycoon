# 우정회관 키우기 · Game Overview

**스포일러 포함.** FriendshipTycoon 프로젝트의 게임 규칙, 코드 구조, 데이터 편집법과 제작 기록을 모은 문서. 현재 작업 트리의 코드·리소스를 기준으로 정리했다(2026-10-21). 수치는 Resource 스크립트의 기본값과 각 `.tres`의 재정의를 함께 적용한 값이다.

## 목차

- [게임 개요와 구현 범위](#게임-개요와-구현-범위)
- [프로젝트 구조](#프로젝트-구조)
- [해금 조건](#해금-조건)
- [수입과 업그레이드](#수입과-업그레이드)
- [짬 환생과 우측 패널](#짬-환생과-우측-패널)
- [큰 수 표시와 계산](#큰-수-표시와-계산)
- [로컬 진행 저장](#로컬-진행-저장)
- [구매 버튼 배치](#구매-버튼-배치)
- [게임 이벤트와 폰 DM](#게임-이벤트와-폰-dm)
- [오류 처리](#오류-처리)
- [렌더링](#렌더링)
- [아트와 애니메이션 제작 기록](#아트와-애니메이션-제작-기록)
- [앱 아이콘](#앱-아이콘)
- [실행과 검증](#실행과-검증)

## 게임 개요와 구현 범위

장르는 incremental / tycoon이다. 수입원을 구매하고 레벨업과 구매 효과로 생산량·속도를 높여 회관을 확장한다. 가격·수입·배율이 커지는 진행에 맞춰 큰 수 계산을 지원한다.

### 현재 구현

1. 새 게임은 자금 0원과 모든 수입원 미구매 상태로 시작한다. 무료 자판기를 구매해 생산을 시작한다.
2. 자판기, 간부식당, 간부목욕탕, 부식의민족의 네 수입원을 레벨업하고, 구조물·시설·인물 버튼을 구매해 다음 항목을 해금한다. 현재 `ButtonManager.buttons`에는 32개 버튼이 등록되어 있다. `lab`에는 티타늄 철골 구매가 있지만 연구실 수입원은 아직 등록되어 있지 않다.
3. 짬통(`jjamtong`) 첫 구매로 짬 시스템을 영구 해금한다. 실시간 짬은 `floor(해금 이후 이번 환생의 누적 수익 / 3,300,000,000,000)`이며 첫 환생 전에는 400짬을 추가한다. 지출은 이 수익 장부를 줄이지 않는다.
4. 환생하면 실시간 짬을 확정 짬으로 옮기고 자금·일반 구매·수입원 레벨과 생산 상태를 초기화한다. 첫 환생부터 `1 + 확정 짬 × 0.01`의 수입 배율을 적용한다. `total_jjam`은 확정 짬과 실시간 짬의 합이며, 해금 조건과 수입 배율은 서로 다른 짬 값을 사용한다.
5. 이벤트, 자동/수동 저장, 툴팁·생산 타이머·화면 밖 해금 버튼 안내를 제공한다.

### 향후 기획

아래는 기존 게임 기획이며 현재 플레이 가능한 시스템으로 구현되어 있지 않다.

| 기획 | 예정 동작 |
| --- | --- |
| 짬 편의성 업그레이드 | 짬을 소비해 버튼 원격 구매 등 구매 |
| 재입대 | 두 번째 환생 단계. 무공훈장 레벨 상승, 생산 시간 50배 단축 |
| 명예의 전당 | 짬 환생·재입대에도 유지되는 버튼과 전체 수입 배율 업그레이드 |
| 초월·카르마 | 전당 꼭대기에서 해금하는 마지막 환생·엔딩. 카르마로 영구 구매 지정(전당 제외) |

`ButtonData.permanent_bought`와 환생 시 영구 구매를 보존하는 처리는 있지만, 카르마 소비로 영구 구매를 지정하는 UI·시스템은 없다. `PrestigeManager`가 현재 관리하는 환생 재화는 짬뿐이다.

## 프로젝트 구조

Godot 4.7 프로젝트다. 시작 장면은 `scenes/main.tscn`이며 `project.godot`에 등록되어 있다. Mobile 렌더러와 `canvas_items` 화면 확장을 사용한다.

| 위치 | 역할 / 편집 대상 |
| --- | --- |
| `autoload/` | 자금·수입·구매·환생·이벤트·저장 등 공통 상태와 신호 |
| `scenes/main.gd` | 시작 시 저장 복원, 월드/UI 구성, 카메라와 입력 연결 |
| `scripts/JjamPrestigePresentation.gd` | 짬통 소개의 카메라·입력 잠금, 환생 암전·초기화·고양이 연출 |
| `scenes/world_layout.tscn` | 월드 오브젝트, 구매 ID, 스프라이트, HoverArea, 깊이 |
| `scenes/button_layout.tscn` | 구매 버튼·설명의 편집기 배치와 표시 스타일 |
| `scripts/ResourceInit/` | 버튼·조건·수입원·이벤트·대화 Resource 정의 |
| `data/buttons/`, `data/conditions/` | 개별 구매 데이터와 해금 조건 |
| `data/IncomeSources/` | 네 수입원의 기본 생산량·시간·레벨업 곡선 |
| `data/events/`, `data/events/dialogues/` | 이벤트 설정과 폰 DM 대화 |
| `data/animations/` | 애니메이션 프레임 리소스 |
| `data/effects/`, `ui/effects/` | 환생 고양이 이펙트의 설정과 재사용 장면 |
| `scripts/` | 큰 수·표시·렌더링·배치·애니메이션 등의 공용 로직 |
| `ui/` | 수입원·업그레이드·툴팁·저장·개발자 도구·이벤트 화면 |
| `assets/` | 이미지·폰트 등 게임 자산 |
| `tests/`, `logs/` | 검증 장면과 밸런스 테스트 결과 |
| `saves/` | 디버그 실행의 로컬 진행 데이터 |

### Autoload 책임과 순서

아래 순서대로 `project.godot`에서 생성한다. `ErrorManager`는 검증 대상보다 먼저, `PrestigeManager`는 짬 해금을 검사하는 `ButtonManager`보다 먼저 생성된다.

| 순서 | 객체 | 책임 |
| --- | --- | --- |
| 1 | `ErrorManager` | 공통 데이터·참조·수치 검증, 오류 UI·기록·중복 억제 |
| 2 | `SoundManager` | 배경음·효과음 재생과 음량 |
| 3 | `EconomyManager` | 자금과 입출금 잔여값, 전체 수입·시간 배율, 개발자 배율 |
| 4 | `IncomeManager` | 수입원 실행 상태와 업그레이드, 전체·이번 환생의 누적 수익과 잔여값 |
| 5 | `PrestigeManager` | 짬 영구 해금, 확정·실시간·합계 짬, 환생 횟수와 수입 보너스 |
| 6 | `ButtonManager` | 등록된 버튼, 해금·가격·구매·효과 적용, 환생 초기화와 상태 신호 |
| 7 | `TooltipManager` | 화면 툴팁 생성·배치·표시 |
| 8 | `RightPanelManager` | 등록된 우측 패널의 열기·닫기와 상호 배제 |
| 9 | `EventManager` | 이벤트 조건·추첨·진행·쿨타임, 일회성 결과·영구 해금, DM 보상 예약 |
| 10 | `SaveManager` | 슬롯 파일 검증·이전·저장·복원, 종료·백그라운드 자동 저장 |

`IncomeManager.sources`, `ButtonManager.buttons`, `EventManager.events`에 등록해야 게임 로직이 해당 데이터를 사용한다. 파일만 추가해도 자동 등록되지는 않는다. 수입원 실행 상태는 매니저의 딕셔너리로 관리하며, 버튼의 `bought`·`permanent_bought`는 `ButtonData` 리소스에 보관한다. 저장 복원 시에는 여러 매니저의 상태를 먼저 적용하고 화면 갱신 신호를 보낸다.

## 해금 조건

버튼은 `ButtonData.unlock_condition`, 이벤트는 `GameEventData.unlock_condition`에 `UnlockCondition` 리소스를 연결한다. 조건이 없으면 해금 조건 자체는 항상 충족하며, 구매 자금이나 이벤트 쿨타임 같은 나머지 검사는 별도로 적용한다.

| Type | 기준 | 설정 |
| --- | --- | --- |
| `MONEY` (0) | 현재 자금 | `amount` 이상. `large_amount`가 있으면 이를 대신 사용 |
| `TOTAL_JJAM` (1) | 확정 짬 + 실시간 짬 | `amount`에 정수 범위 내 0 이상 정수 지정 |
| `BUTTON` (2) | 선행 버튼 구매 | `value`에 등록된 선행 버튼 ID 지정 |

기존 `UPGRADE` 자리를 `TOTAL_JJAM`으로 교체했고 enum 번호는 유지했다. 현재 `PrestigeManager.get_total_jjam()`은 확정 짬과 실시간 짬의 합을 반환하므로, 첫 해금의 400짬도 환생 전에 해금 기준에 포함된다. 버튼 상태는 자금 변경·환생 완료 신호와 구매 완료 처리에서 다시 계산한다. 이벤트는 자체 갱신에서 조건을 검사한다. `large_amount`는 큰 MONEY 조건에 사용하며 `TOTAL_JJAM` 조건에는 `amount`를 사용한다.

## 수입과 업그레이드

### 현재 수입원 설정

아래 값은 각 `data/IncomeSources/*.tres`의 기본값이다. 구매 효과·환생·개발자 배율을 적용하기 전 값이며 기본 레벨은 1이다.

| 수입원 ID | 기본 회당 수입 | 기본 생산 시간 | 첫 업그레이드 가격 | 수입 성장 간격 | 간격당 배율 |
| --- | --- | --- | --- | --- | --- |
| `vending_machine` | 10원 | 5초 | 10원 | 60레벨 | 10,000배 |
| `restaurant` | 10,000원 | 12초 | 5,000원 | 60레벨 | 10,000배 |
| `spa` | 50,000,000원 | 100초 | 10,000,000원 | 60레벨 | 10,000배 |
| `bumin` | 20,000,000,000원 | 300초 | 500,000,000원 | 60레벨 | 10,000배 |

### 가격과 생산량 곡선

현재 레벨을 `L`, 구매한 업그레이드 횟수를 `k = L - 1`로 놓는다.

```text
다음 업그레이드 가격 = upgrade_base_cost × (1 + upgrade_cost_linear_growth × k)
                      × 2^(k / upgrade_cost_doubling_levels)
레벨 L의 회당 수입 = 기본 회당 수입 × upgrade_income_growth_multiplier^(k / upgrade_income_growth_levels)
```

현재 네 수입원은 `IncomeSourceData`의 가격 기본값인 `upgrade_cost_linear_growth = 0.96`, `upgrade_cost_doubling_levels = 3.0`을 사용한다. 수입 성장 기본값은 `upgrade_income_growth_levels = 60`, `upgrade_income_growth_multiplier = 10000.0`이며 각 `.tres`의 **Upgrade Income**에서 조절한다.

지수 곡선은 Lv.1을 기본 수입으로 두고 **Lv.61에서 10,000배, Lv.121에서 1억 배, Lv.181에서 1조 배**가 된다. 레벨당 배율은 `10000^(1/60) ≈ 1.1659144012`로 약 **+16.59%**다. 매 레벨 같은 비율로 성장하며, 60레벨마다 별도 보너스를 지급하는 처리는 없다. 가격 곡선과 수입 곡선은 독립적으로 조정한다.

수입은 매번 기본 수입과 목표 레벨에서 직접 계산하며 마지막 결과만 캐시한다. 기본 수입·큰 수 기본 수입·성장 간격·성장 배율이 바뀌면 캐시를 다시 계산하며 환생 시 초기화한다. 멀리 떨어진 레벨도 레벨 수만큼 반복하지 않고 큰 수의 10진 지수를 계산하므로, Lv.100,001처럼 네이티브 실수 범위를 넘는 수입도 처리한다. 다음 레벨 미리보기와 실제 구매 후 수입은 같은 계산을 사용한다.

수입원 업그레이드는 같은 수입원에 대한 동기 재호출을 결제·알림이 끝날 때까지 거절한다. 결제 성공 시 잔액과 레벨을 함께 반영한 뒤 신호를 발행하므로 신호 안에서 저장해도 일관된 진행을 기록한다. 처리 중 환생·초기화·불러오기가 발생하면 이전 업그레이드의 후속 처리는 중단한다. 서로 다른 수입원의 업그레이드와 호출 완료 뒤의 순차 구매는 허용한다.

업그레이드 버튼은 이미지가 실제로 표시된 부분을 눌러야 구매·홀드가 시작된다. 종횡비를 유지하며 그린 이미지 주변의 빈 공간과 투명한 모서리는 클릭 영역에서 제외한다. 버튼을 누른 뒤 마우스가 밖으로 나가도 홀드는 계속 유지되며, 밖에서 마우스를 떼면 반복 구매가 중지된다.

### 지급과 화면 표시

수입원·전체 배율을 적용한 회당 금액은 원 단위로 반올림한다. 양수가 0으로 반올림되면 원래 소액을 누적한다. 완료 회차는 프레임마다 모아 원 단위로 지급하며 소수 원과 계산 잔여값은 수입원에 보관한다.

툴팁과 업그레이드 패널의 초당 수입은 회당 금액을 생산 주기로 나눈 값이다. 현재 기본 자판기는 `10원/회, 초당 2원`(5초 주기)이다. HUD 총수입도 반올림 전 초당 수입을 합산한 뒤 표시한다. 업그레이드 패널은 다음 레벨과 현재 레벨의 회당 금액 차이를 보여준다. 큰 수 가격의 구매 가능 여부도 `BigNumber.compare()`로 검사한다.

## 짬 환생과 우측 패널

### 짬의 구분과 수익 장부

| 상태 | 의미 |
| --- | --- |
| `jjam_unlocked` | 짬통 첫 구매로 켜지는 슬롯별 영구 해금. 환생으로 꺼지지 않음 |
| `banked_jjam` | 환생으로 확정한 짬. 수입 보너스의 기준 |
| `live_jjam` / `current_jjam` | 이번 환생에서 확정할 실시간 짬. 아직 수입 보너스를 주지 않음 |
| `total_jjam` | 확정 짬 + 실시간 짬. `TOTAL_JJAM` 해금 조건의 기준 |
| `initial_jjam_pending` | 첫 해금 후 첫 환생 전까지 400짬을 더하는 상태 |
| `prestige_count` | 새 짬 환생의 실행 횟수. 첫 환생 전용 이벤트의 판단 기준 |
| `transition_in_progress` | 환생 중복 요청을 막는 상태. 환생 요청 시 켜지고 연출 종료·로드 시 해제 |

`IncomeManager.total_earned_income`은 전체 누적 수익, `jjam_earned_income`은 짬 첫 해금 이후 이번 환생까지의 수익이다. 수입원 지급, 거래 수락이 처리되어 예약된 폰 DM 보상, 개발자 도구의 자금 추가를 수익으로 기록한다. 수입원 지급과 개발자 자금은 `EconomyManager.add_income()`을 통하며, DM은 예약 시 한 번 기록하고 실제 입금에서는 중복 기록하지 않는다. 지출은 수익을 줄이지 않고 각 장부의 계산 잔여값도 저장한다.

현재 `PrestigeManager.money_per_jjam = 3300000000000.0`(3.3조 원), `boost_per_jjam = 1.0`(1%)다. 실시간 짬은 `floor(jjam_earned_income / money_per_jjam)`이고 첫 환생 전에는 400을 더한다. 첫 환생을 한 번도 하지 않았다면 수입 보너스는 0%, 환생 후에는 `1 + banked_jjam × boost_per_jjam / 100`이다. 현재 짬 소비 기능은 없다.

### 해금과 환생 연출

`jjamtong`은 현재 `bumin` 구매 후 해금되며 가격은 1조 원이다. 짬 해금에 더해 전체 생산 속도 3배 구매 효과를 적용한다. 첫 구매의 `jjamtong_intro` 이벤트는 `JjamPrestigePresentation`이 처리한다. UI·입력을 잠그고 짬통으로 카메라 이동·확대, 고양이 빼꼼 애니메이션, 1초 대기, 기존 줌 복귀 후 UI·입력을 복구한다. 일회성 이벤트이므로 환생 후 짬통을 다시 구매해도 소개를 반복하지 않는다.

환생 UI는 `PrestigeManager.request_prestige()`를 호출한다. 0.35초 동안 암전한 뒤 `jjam_prestige()`로 실시간 짬을 확정하고, 이번 환생의 수익·자금·일반 구매·수입원 레벨·구매 배율과 생산 상태를 초기화한다. 영구 구매 버튼은 재적용하고 짬 영구 해금·확정 짬·전체 누적 수익·일회성 이력·이벤트 영구 해금·개발자 배율은 유지한다. 진행 중 DM은 거절 처리하고 이전 진행의 지연 입금은 새 진행으로 넘기지 않는다. 자세한 보상 처리는 [보상 입금 연출](#보상-입금-연출)을 참고한다.

카메라를 초기 위치·줌으로 돌리고 우측 패널을 닫은 뒤 0.3초 대기, 0.55초 동안 화면을 밝힌다. 이후 `data/effects/jjam_prestige_cats.tres` 설정으로 고양이 30개가 0.3초에 걸쳐 나타나며, 각각 0.12초의 등장과 1초의 흡수 동작으로 우측 짬 버튼에 모인다. 재사용 장면은 `ui/effects/jjam_cat_effect.tscn`이다. 슬롯 변경 시 진행 중 소개·환생 연출과 남은 이펙트를 취소하고 UI·입력을 복구한다.

### 우측 패널 관리

`RightPanelManager.register_panel(control)`로 업그레이드·짬 환생 패널을 등록한다. `open_panel()`·`toggle_panel()`로 열면 다른 등록 패널을 닫고 툴팁을 숨긴다. 저장 화면도 열릴 때 등록 패널을 닫으며 개발자 도구는 별도로 표시한다.

고양이 예고를 확인하면 우측에 잠긴 짬 버튼이 나타나고, 짬 시스템 해금 후 사용할 수 있다. `ui/jjam_prestige_panel.tscn`에서 확정·실시간 짬과 수입 보너스를 표시한다. 우측 버튼이나 구매된 짬통 클릭으로 열 수 있으며, 창 크기에 따라 열 배치와 스크롤을 조정한다. 새 우측 화면은 같은 관리자에 등록해 상호 배제 규칙을 공유한다.

## 큰 수 표시와 계산

[큰 수의 이름](https://ko.wikipedia.org/wiki/큰_수의_이름)의 이만체진을 사용한다. 10,000원부터 10,000배마다 단위를 바꾸며 소수점 다섯째 자리에서 반올림한 뒤 끝의 0과 불필요한 소수점을 생략한다.

`만(10^4) → 억(10^8) → 조 → 경 → 해 → 자 → 양 → 구 → 간 → 정 → 재 → 극 → 항하사 → 아승기 → 나유타 → 불가사의 → 무량대수(10^68)`

| 원래 값 | 표시 |
| --- | --- |
| 12,345.6원 | 1.2346만원 |
| 12,340원 | 1.234만원 |
| 100,000,000원 | 1억원 |
| 2,200,000,000원 | 22억원 |
| 10^68원 | 1무량대수원 |
| 10^72원 | 1 × 10^72원 |
| 1.234567 × 10^401원 | 1.2346 × 10^401원 |

10,000 무량대수(10^72)부터는 가수를 1 이상 10 미만으로 맞춘 `가수 × 10^지수`를 사용한다. 예: `2.2008 × 10^381원`. 표시 반올림으로 현재 단위의 10,000에 도달하면 다음 단위로 올린다. 초당 수입은 10,000 미만에서 최대 소수점 두 자리, 그 이상에서 최대 네 자리로 반올림하며 동일하게 끝의 0을 생략한다. 시간 단위 표기의 고정 자릿수는 유지한다.

일반 금액은 1만 미만에서 최대 소수점 두 자리로 표시하며, 표시 자릿수보다 작은 양수는 과학적 표기법으로 보존한다. 1만 미만의 숫자는 쉼표로 자릿수를 구분하지 않는다. 예: `1234원`, `1234.5원/초`.

HUD의 현재 자금은 1만원 미만에서 소수점 없이 표시하고, 1만원부터 소수점 네 자리를 고정으로 표시한다. 예: `327원`, `9999원`, `1.0000만원`, `22.0000억원`. 필요 자금과 초당 수입 등 다른 표시는 끝의 0을 생략한다.

### 계산 자료형

`scripts/BigNumber.gd`는 일반 값에 기존 `float` 계산을 사용한다. 표현 범위를 넘는 값은 가수와 십진 지수를 별도로 저장한다. 자금, 수입, 수입 배율, 업그레이드 가격, 환생 짬과 보상 계산에 적용한다. 반환값은 일반 수치 또는 `BigNumber`이므로 금융 값의 연산·비교는 `add`, `subtract`, `multiply`, `divide`, `compare`를 사용한다.

가수·지수 값은 15자리 십진 유효숫자로 정규화한다. 정수 가수를 이용해 가까운 지수끼리 정확히 정렬한 뒤 더하거나 빼며, 생성자·일반 숫자 변환·음수·0·반올림에서도 같은 규칙을 사용한다. 지원 지수 범위는 ±1,000,000,000이다. 범위를 넘거나 유효하지 않은 값은 기존 검증 경로에서 거절한다.

일반 `add`는 한 번의 계산에서 표현 정밀도보다 작은 부분을 버릴 수 있다. 반복 입출금에는 `add_with_residual`로 큰 값과 부호 있는 잔여값을 분리한다. 지갑의 `money_correction`과 수입원별 `source_pending_corrections`가 이를 보관하며, 잔액에 즉시 표현되지 않는 작은 입출금도 누적·차감한다. 잔여값은 감당 가능한 크기로 모이면 주 값에 합쳐진다. 정확한 임의 정밀도 산술은 아니며 각 부분의 유효숫자는 제한된다.

완료 회차는 프레임마다 묶어서 지급한다. 회당 수입의 기존 원 단위 반올림을 유지하되 양수가 0으로 반올림되는 경우에는 원래의 소액을 누적한다. 원 단위 금액만 지갑에 지급하고 소수 원은 수입원에 남긴다. 큰 지급액 때문에 소수 원이 사라지지 않도록 두 부분을 분리하며, 완료 회차 자체가 `float`를 넘으면 가수·지수 회차로 계산한다. 지급 콜백 중 초기화·환생·불러오기가 실행되면 이전 미지급액을 복원하지 않는다.

수입은 기본 수입에 `성장 배율^((레벨 - 1) / 성장 간격)`을 직접 적용한다. 높은 레벨도 반복 합산이나 누적 증가분 근사 없이 10진 지수로 계산한다. 결과는 큰 수 형식으로 유지하고 실제 회당 지급액은 기존 반올림 규칙을 적용한다. 시간과 생산 타이머는 기존 `float`를 유지한다.

### 입력과 저장

- 개발자 도구의 자금과 수입 배율에 `1e10000` 같은 값을 입력할 수 있다. 시간 배율은 기존 유한한 양수 범위를 사용한다.
- 버튼의 `large_price`에 `1.25e500` 등을 지정하면 `price` 대신 사용한다. 비워 두면 기존 가격을 사용한다.
- 수입원 `IncomeSourceData`의 `large_base_income`에 `1.25e500` 등을 지정하면 `base_income` 대신 기본 회당 수입으로 사용한다. 비워 두면 기존 값을 사용한다. 레벨별 수입 증가와 수입 배율은 이 기본값에 적용하며, 입력을 변경하면 수입 캐시도 다시 계산한다.
- MONEY 해금 조건의 `large_amount`도 같은 방식으로 `amount`를 대체한다.
- 저장 시 큰 값은 `decimal_mantissa`와 `decimal_exponent`의 딕셔너리로 기록한다. 일반 숫자 저장도 읽으며, 현재 짬 시스템의 int64 범위 정수는 정수로 저장하고 초대형 짬은 근사 값으로 전환한다. 옛 짬 시스템의 보유량은 아래 호환 처리에 따라 폐기한다.
- 지갑의 잔여값과 수입원별 잔여값도 부호를 유지해 저장한다. 해당 필드가 없는 기존 저장은 0으로 복원한다. 잔액 직접 교체·환생·새 게임에서는 이전 지갑 잔여값을 초기화한다.

### 검증

`godot --headless --path . res://tests/big_numbers.tscn --fixed-fps 60`

단위 경계·자리올림, 10^10000 규모의 계산·HUD·개발자 입력·저장 복원, 큰 가격의 구매와 업그레이드, 정수 범위를 넘는 환생, 지수 수입의 정확도와 계산 시간, 기존 저장의 호환성을 검사한다. `big_numbers`의 환생 관련 일부 검사는 현재 환생 시스템과 일치하지 않아 별도 수정이 필요하다.

`godot --headless --path . res://tests/big_number_payments.tscn --fixed-fps 60`

일반·가수/지수 혼합 산술과 상쇄, 작은 입출금 누적, 1·30·60·144 FPS의 여러 수입원, 소수 원 회차, `float`를 넘는 완료 회차, 지급 성공·실패 콜백의 초기화·불러오기, 잔여값 저장 복원과 기존 저장 호환성을 검사한다.

### 시간 표시

생산 주기와 툴팁의 시간은 소수 둘째 자리까지 표시한다. 현재 단위에서 `0.01` 미만이면 `s → ms → μs → ns → ps → fs → as → zs → ys → rs → qs` 순서로 1,000배씩 변환한다. 예: `0.0099s`는 `9.90ms`. `0.01qs` 미만에서는 `qs`를 유지하고 과학적 표기법을 사용한다. 구현은 `scripts/NumberFormatter.gd`에 있다.

## 로컬 진행 저장

- 게임 실행 파일 옆에 `saves` 폴더를 만든다. 디버그 빌드는 `res://saves`에 저장한다. `autosave.cfg`의 자동 저장 슬롯 1개와 `slot_01.cfg`~`slot_10.cfg`의 수동 슬롯 10개를 생성하며, 아직 진행을 저장하지 않은 슬롯은 비어 있음으로 표시한다.
- **자동 저장 슬롯**은 번호 없이 주황색으로 표시한다. 게임 종료 시 저장하고 다음 실행 때 자동으로 불러온다. 화면 우측 상단 **저장** 버튼을 누르면 슬롯 선택 창이 열리며, 자동 슬롯은 수동 저장을 막는다. 선택된 슬롯은 흰색 테두리로 표시한다. 모바일에서는 백그라운드 전환 시에도 자동 저장한다.
- 슬롯 1~10은 수동 저장용이다. 슬롯을 선택한 뒤 **저장** 또는 **불러오기**를 누른다. 덮어쓰기와 불러오기는 확인 창을 거친다. 저장 시각과 자금이 표시된다.
- 빈 슬롯도 **불러오기**로 선택할 수 있다. 새 게임 시작 안내를 확인하면 자금·구매·업그레이드·환생 진행을 모두 초기화하여 자판기도 구매하지 않은 상태로 시작한다. 빈 슬롯은 저장하기 전까지 비어 있으며, 다른 슬롯의 저장 데이터는 유지된다. 자동 저장 슬롯이 비어 있는 경우에도 다음 실행은 초기 상태로 시작한다.
- 선택한 슬롯의 **초기화** 버튼을 누르면 되돌릴 수 없다는 경고 창이 뜬다. **초기화**를 확인해야 해당 슬롯의 저장 데이터를 비우며, **취소**하면 유지한다. 현재 플레이 진행은 유지하며, 비어 있는 슬롯은 초기화 버튼을 비활성화한다. 자동 저장 슬롯도 초기화할 수 있고, 게임 종료 시 현재 진행으로 다시 자동 저장됨을 경고 창에 안내한다.
- 이전 구성의 자동 슬롯 1은 `autosave.cfg`로, 수동 슬롯 2~10은 새 슬롯 1~9로 옮긴다. 새 수동 슬롯 10은 비어 있는 상태로 추가한다. 원본 파일 내용은 `legacy_slots_v1.cfg`에 백업하고, 중간에 이동이 실패하면 다음 초기화에서 백업을 기준으로 재시도한다.
- 자금과 입출금 잔여값, 전체·수입원·개발자 배율, 수입원 활성화·레벨·남은 생산 시간·미지급 수입과 잔여값, 버튼 구매·영구 구매 상태, 환생 재화를 저장한다. 불러올 때 구매 효과를 다시 적용하지 않는다. 게임을 끈 동안의 수입은 계산하지 않는다.
- 짬 영구 해금·확정/실시간/합계 짬·첫 400짬 지급 상태·환생 횟수, 전체/이번 환생 누적 수익과 잔여값도 저장한다. 로드 시 실시간·합계 짬은 복원한 수익 장부와 설정을 기준으로 다시 계산한다. 새 짬 시스템 버전이 없는 옛 저장에서는 기존 짬을 폐기하고 전역 배율에 포함된 옛 짬 보너스를 제거한다. 짬통 구매 여부로 영구 해금을 복구하며, 새 형식의 첫 환생 전에는 확정 짬을 0으로 복원한다.
- 파일 전체를 검증한 뒤 진행을 복원한다. 저장은 임시 파일을 완성한 뒤 교체하므로 쓰기 실패 시 이전 파일을 유지한다. 시작 시 손상된 자동 저장을 발견하면 다음 자동 저장 전에 `.invalid` 사본을 보존한다. 저장 위치에 쓰기 권한이 없으면 오류를 표시한다. 강제 프로세스 종료·전원 차단에는 종료 저장을 보장할 수 없다.
- 이벤트 쿨타임·일회성 진행/결과·영구 해금 기록과 아직 입금되지 않은 확정 보상도 저장한다. 진행 중 대화는 불러올 때 취소한다. 자세한 내용은 [이벤트 저장](#저장과-다른-이벤트)을 참고한다.
- 저장 테스트: `godot --headless --path . res://tests/save_system.tscn`. `.godot` 아래 별도 저장소에서 슬롯·파일 이전·복원·손상·쓰기 실패·저장 UI와 자동 저장을 검사하도록 구성되어 있다. 일반 종료와 종료 요청을 나눠 검사하려면 `-- --close-request` 옵션으로 추가 실행한다. 일부 테스트의 기대값·UI 경로는 현행 코드와 다르므로 [테스트 장면](#테스트-장면)의 주의점을 함께 확인한다. 저장을 사용하는 테스트는 플레이어의 `saves/` 대신 별도 저장소를 사용한다.

## 구매 버튼 배치

- `scenes/button_layout.tscn`을 Godot의 2D 편집기에서 열면 모든 구매 버튼과 설명의 배치를 확인할 수 있다. `WorldReference`는 현재 `world_layout`을 흐리게 표시하는 잠긴 참고용 인스턴스다.
- `Buttons/그룹/버튼 ID/PurchaseButton`을 움직이면 구매 버튼 위치가 바뀌고, 같은 ID의 `InfoLabel`을 움직이면 설명 위치가 바뀐다. ID 노드를 움직이면 둘을 함께 옮길 수 있다. 크기와 스케일도 이 씬에서 지정한다.
- 저장 후 게임을 다시 실행하면 `button_layout`의 버튼·설명 노드를 복제해 좌표·크기·텍스처·글꼴·테두리 설정을 그대로 사용한다. 게임은 참고용 씬을 숨기고 복제한 UI에 해금·구매 처리와 최소 화면 크기 보정을 연결한다. 설명 내용은 최신 `ButtonData`에서 갱신한다.
- 버튼과 설명의 배치는 이 씬에서만 관리한다. 월드 오브젝트 위치를 바꾼 경우 참고용 배치를 보고 버튼 위치도 조정한다.
- `res://data/buttons`의 버튼 리소스를 열고 `Purchase Description > Description`에 여러 줄 설명을 입력한다. 비워 두면 효과 설명을 자동으로 사용한다. `button_layout`의 각 ID 노드는 해당 리소스에 연결되어 설명·이름·가격·효과를 수정하면 편집기 미리보기가 즉시 갱신된다. 설명은 `InfoLabel.text`에 별도로 저장하지 않는다.
- 새 월드 구매 버튼을 추가할 때에는 `Buttons` 아래에 버튼 ID와 같은 이름의 `Node2D`를 만들고 `scripts/ButtonLayoutEntry.gd`를 연결한다. `Button Data`에 해당 버튼 리소스를 지정하고, 수입원 관련 효과라면 `Income Source`도 지정한다. 자식으로 `PurchaseButton`(`TextureButton`)과 `InfoLabel`(`Label`)을 넣는다. ID가 누락되거나 중복되면 오류를 표시하고 해당 버튼의 구매를 막는다.

## 게임 이벤트와 폰 DM

`EventManager`는 Autoload로 등록되어 있습니다. 이벤트 등록, 발생 조건, 확률,
중복 방지, 종료 및 쿨타임은 이 매니저에서 관리합니다.

현재 `EventManager.events`에는 `phone_dm`, `camera_tutorial`, `cat_watching`, `jjamtong_intro`의 네 이벤트가 등록되어 있습니다. 짬통 소개의 카메라·고양이 연출은 [짬 환생과 우측 패널](#짬-환생과-우측-패널)에서 설명합니다.

### 공통 이벤트 설정

| 속성 | 의미 |
| --- | --- |
| `trigger = Instant` | `unlock_condition`과 쿨타임 등 실행 조건을 충족하면 즉시 시작 |
| `trigger = Random` | 실행 조건을 충족한 동안 지정된 주기마다 확률 추첨 |
| `roll_interval_seconds` | Random의 추첨 간격(초). 기본 1초 |
| `chance_per_roll` | Random의 한 번 추첨당 확률. 0.03은 3% |
| `cooldown_seconds` | 종료 후 같은 이벤트가 다시 시작하기까지의 최소 대기 시간. 스크립트 기본 300초, 현재 폰 DM은 150초 |
| `one_off` | 현재 저장 슬롯에서 최초 한 번만 실행. 표시 기록은 환생해도 유지 |
| `no_prestige_only` | 첫 환생 전만 실행 가능. 한 번도 실행하지 않았더라도 환생 후에는 차단 |
| `permanent_unlock` | 조건을 한 번 충족하면 해당 슬롯에서 해금을 유지. 첫 환생 전 제한·쿨타임 등 나머지 발동 검사는 계속 적용 |

`Instant`를 선택하면 인스펙터의 `roll_interval_seconds`와 `chance_per_roll`이
읽기 전용으로 비활성화됩니다. `Random`으로 바꾸면 다시 편집할 수 있습니다.
예를 들어 주기 10초, 확률 0.25는 **10초마다 한 번, 매번 25%**를 뜻합니다.
추첨 시간은 해금 조건과 쿨타임을 모두 충족한 뒤부터 계산하며 생산 배율과는 무관합니다.
카메라 소개·환생 연출로 `presentation_locked`가 켜진 동안에는 이벤트 대화·쿨타임·추첨 진행을 멈춥니다. 수입원 생산은 별도 로직으로 계속 진행됩니다.

버튼 구매 조건은 `unlock_condition`의 `BUTTON`과 `value`에서만 지정합니다.
금액(`MONEY`)이나 누적 짬(`TOTAL_JJAM`)도 같은 방식으로 Instant/Random에 사용할 수 있습니다.

`One Off`와 `No Prestige Only`는 별개의 실제 동작 옵션입니다. 카메라 튜토리얼은
둘 다 사용하여 첫 환생 전에 슬롯당 한 번만 표시합니다. 고양이 이벤트도 두 옵션을 모두 사용하므로 첫 환생 이후에는 발생하지 않습니다.

### 회관 주춧돌 카메라 튜토리얼

`res://data/events/camera_tutorial_event.tres`는 회관 주춧돌(`hall_foundation`)을
처음 구매할 때 시작하는 일회성 이벤트입니다. `trigger`는 `Instant`,
`unlock_condition`은 `BUTTON: hall_foundation`, `one_off`와 `no_prestige_only`는 `true`입니다.
확률 추첨을 하지 않으며 환생 이후에는 발생하지 않습니다.

표시 여부는 **각 저장 슬롯의 `events.camera_tutorial.consumed`**에 저장합니다.
현재 슬롯을 불러올 때 그 슬롯의 기록으로 교체하며, 다른 새 슬롯에서 시작하면
튜토리얼을 다시 한 번 볼 수 있습니다. 환생은 이 기록을 초기화하지 않습니다.
슬롯을 초기화한 뒤 새 게임으로 불러오면 해당 진행의 기록도 초기화됩니다.

기존 저장에 이 항목이 없으면 주춧돌 구매 여부 또는 환생 기록으로 이전 진행을
판단하여, 이미 진행한 플레이에서 안내를 다시 띄우지 않습니다.

표시와 페이드는 `res://ui/CameraTutorial.gd`에서 담당합니다. Windows에서는
"마우스 드래그/휠로 카메라 조정", 모바일에서는 "터치 및 드래그로 카메라 조정"을
보여주고, 카메라 조작 시 이벤트를 종료하며 1.5초 동안 서서히 사라집니다.
슬롯 변경 시 진행 중이거나 사라지는 중인 이전 슬롯의 안내도 숨깁니다.

### 짬 환생 시스템 예고

`res://data/events/cat_watching_event.tres`는 `front_door`를 해당 저장 진행에서
처음 구매하면 발생하는 일회성 이벤트입니다. 진행 여부는 다른 일회성 이벤트처럼
각 슬롯의 `events.cat_watching.consumed`에 저장하고, 환생해도 다시 표시하지 않습니다.
`no_prestige_only = true`이므로 첫 환생 전에만 발생합니다. 첫 환생 전에 문을 구매하지 않았다면 이후에는 발생하지 않습니다. 기존 저장에서 이미 문을 구매했거나 환생했다면 이전 진행으로 처리합니다.

확인 결과는 `events.cat_watching.result = "acknowledged"`로 저장하며, 이 결과가 우측 잠긴 짬 버튼의 표시 기준입니다. 새 형식의 저장에서 확인 전에 중단한 예고는 로드 시 다시 볼 수 있도록 처리합니다. 확인 결과가 없던 옛 저장의 진행 기록은 확인 완료로 호환 처리합니다.

연출은 `res://ui/cat_watching_event.tscn`과 `res://ui/CatWatchingEvent.gd`에서
편집합니다. 일반 HUD보다 높은 이벤트 레이어(5)에 표시하며 개발자 도구(10)는
그보다 위에 표시됩니다. 화면 전체를 살짝 어둡게 하고 중앙에 고양이 실루엣,
"무언가가 당신을 주시합니다..." 문구와 `Button_sus.png` 버튼을 보여줍니다.
버튼을 누르면 0.5초 동안 음영·오라·문구·버튼이 사라지고 실루엣은 작아집니다.
퇴장 중에도 배경 클릭, 터치 및 카메라 조작을 막으며 슬롯 변경 시 즉시 숨깁니다.

오라는 `res://assets/sprites/Cat/cat_aura_smoke.tres`의 부드러운 연무 텍스처를
사용하는 스프라이트와 고양이 주변에서 바깥으로 퍼지는 `CPUParticles2D`로 만듭니다.
별도 이미지 파일 없이 Godot의 그라데이션 리소스에서 색상과 농도를 수정할 수 있습니다.

### 폰 DM 설정

Godot 인스펙터에서 `res://data/events/phone_dm_event.tres`를 열면 다음 값을
수정할 수 있습니다.

| 속성 | 현재 적용값 / 의미 |
| --- | --- |
| `unlock_condition` | `UnlockCondition` 리소스. 현재는 `BUTTON`, `bumin` 구매 완료 |
| `permanent_unlock` | `true`. 한 번 해금하면 환생으로 `bumin` 구매가 초기화되어도 유지 |
| `trigger` | `Random` |
| `roll_interval_seconds` | 1초마다 한 번 추첨 |
| `chance_per_roll` | 매 추첨 0.03(3%) |
| `cooldown_seconds` | 이벤트 종료 후 150초. 플레이 시간 기준 |
| `initial_offer_income_seconds` | 60. 시작 시점의 전체 초당 수입 × 60초, 원 단위 반올림 |
| `minimum_offer_amount` | 10,000원. 최초 제시액의 최솟값. 해금된 DM은 환생 직후 생산 수입이 0이어도 발동 가능 |
| `breakdown_chances` | 각 흥정의 결렬 확률: 0.1, 0.3, 0.5 |
| `offer_increase_range` | 두 번째·세 번째 제시 금액의 증가율: 0.2~0.5 |
| `final_offer_increase_range` | 마지막 제시 금액의 증가율: 0.5~1.0 |
| `message_interval_seconds` | 말풍선 간 간격: 0.85초 |
| `result_display_seconds` | 최종 결과를 읽을 시간: 2초(스크립트 기본값은 2.5초) |
| `dialogues` | 이벤트마다 동일 확률로 한 대화를 선택하는 목록 |

기본 조건은 `res://data/conditions/events/phone_dm_unlock.tres`에 있습니다.
다른 `UnlockCondition` 리소스로 교체하면 MONEY, TOTAL_JJAM, BUTTON 조건을
동일한 양식으로 사용할 수 있습니다.
DM은 `permanent_unlock = true`이므로 조건 충족 이력을 저장합니다. 최초 제시액은 `max(round(전체 초당 수입 × 60초), 10,000원)`을 사용하며, 이후 흥정은 해당 제시액에서 증가합니다.

### 대화 추가

`res://data/events/dialogues/`의 대화 하나를 복제하고 아래 내용을 편집한 뒤,
이벤트 설정의 `dialogues` 배열에 추가하세요. 한 리소스에 한 연락처의 대화
전체가 모여 있습니다. 금액 자리에는 `{amount}`를 사용합니다.

| 대화 단계 | 리소스 속성 |
| --- | --- |
| 인사말 / 도입부 | `greeting` / `introduction` |
| 흥정1 / 반응-거절1 | `offer_1` / `refusal_1` |
| 흥정2 / 반응-거절2 | `offer_2` / `refusal_2` |
| 흥정3 / 반응-거절3 | `offer_3` / `refusal_3` |
| 마지막 제시 | `final_offer` |
| 반응-수락 / 반응-결렬 | `acceptance` / `breakdown` |
| 플레이어 수락 / 흥정 / 거절 | `player_accept` / `player_bargain` / `player_reject` |

순서도에 맞춰 **총 4번의 금액 제시, 최대 3번의 추가 흥정**을 진행합니다.
마지막 제시에서는 수락·거절만 가능합니다. NPC 반응-거절을 먼저 출력한 뒤
결렬 여부를 판정하며, 수락할 때만 현재 제시액을 한 번 지급합니다.

폰 UI는 `res://ui/phone_dm_panel.tscn`에 있으며 Main의 HUD 아래에 배치됩니다.
폰 영역은 클릭·터치와 스크롤을 받으며, 해당 영역의 입력으로 월드 버튼을
누르거나 카메라를 이동·확대하지 않습니다.

### 보상 입금 연출

수락하면 보상을 예약하고, 폰이 내려간 뒤 자금 표시 옆에 `+1.2345억원`처럼
추가 금액을 소수점 네 자리로 표시합니다. 0.35초의 폰 퇴장 대기, 0.2초의
등장 모션과 0.4초의 표시 유지 후, 0.85초 동안 보상 금액이 빠르게 줄어들면서
그만큼 실제 자금이 증가합니다. 보상 표시는 자금 쪽으로 이동하며 작아지고,
자금은 밝게 반짝입니다. 가로 공간이 부족하면 자금 창 아래에 표시합니다.

연출은 `res://ui/EventRewardDeposit.gd`에서 조절합니다. 일반 수입은 계속
더해지며, 저장할 때에는 아직 입금되지 않은 확정 보상도 함께 반영합니다.
불러오기는 기존 입금 연출을 취소하므로 보상을 중복 지급하지 않습니다.

짬 환생 시 아직 진행 중인 DM은 거절로 끝냅니다. 수락 결과를 표시 중이어서 보상이 예약되어 있다면 그 보상과 기록한 수익도 취소합니다. 이미 대화가 끝나 입금 연출로 넘어간 확정 보상은 수익 장부에 반영되어 있지만, 아직 지갑에 입금되지 않은 금액을 환생 후 자금에 이어서 지급하지는 않습니다.

### 개발자 도구와 발동 확률

**디버그 빌드에서만 O 키**로 개발자 도구를 열면 이벤트별 남은 쿨타임, 발동을 막는 조건,
다음 추첨까지의 시간, 이번 대기의 추첨 횟수와 마지막 결과를 실시간으로 봅니다.
튜토리얼 같은 일회성 이벤트는 `이벤트 이름 · 진행됨/미진행` 한 줄로만 표시합니다.
현재 슬롯에 저장된 진행 기록을 사용하며 발동 버튼은 표시하지 않습니다.
`즉시 발동`은 테스트용으로 확률 추첨과 쿨타임을 건너뛰며, 해금 조건·중복 방지는 유지합니다.
일반 자동 발동은 쿨타임을 그대로 적용하며, 강제 발동한 이벤트도 종료 후 새 쿨타임을 시작합니다.
발동할 수 없을 때에는 버튼이 비활성화되고 그 이유가 표시됩니다.
이벤트 시간은 개발자 생산 시간 배율에 영향을 받지 않습니다.

Random은 쿨타임 종료 직후의 발동을 보장하지 않습니다. 1초 주기·추첨당 3%에서 평균 대기 시간은
약 33.3초이며, 쿨타임 이후 60초 동안 미발동할 확률은 `0.97^60 ≈ 16.1%`입니다.
불러올 때 저장된 쿨타임은 현재 설정값 이하로 제한합니다. 예를 들어 남아 있는 5분은 현재 폰 DM 설정의 150초 이하로 제한됩니다.

### 저장과 다른 이벤트

기존 저장 형식과 호환되도록 이벤트 쿨타임을 선택 항목으로 저장합니다.
일회성 이벤트는 `consumed`·`result`를, 영구 해금 이벤트는 추가로 `unlocked`를 함께 저장합니다. 현재 슬롯을 불러오면 해당 슬롯의 기록으로 교체합니다. 옛 DM 기록에 영구 해금 필드가 없으면 남은 쿨타임·현재 구매 조건과 짬통 선행 구매 이력을 이용해 해금을 복구합니다.
진행 중인 대화는 불러올 때 취소하며 해당 이벤트의 전체 쿨타임을 적용합니다.
대화를 다시 재생해서 보상을 중복 수령하지 않습니다. 게임을 끈 동안에는
쿨타임이 줄어들지 않습니다.

다른 이벤트는 `GameEventData` 또는 이를 상속한 리소스를 만들어
`EventManager.events`에 등록하세요. 런타임 등록은 `register_event()`를 사용합니다.
`event_started(event_data)`에서 해당 이벤트의 연출을 시작하고,
종료 시 `finish_event(event_id, result)`를 호출하면 공통 쿨타임이 적용됩니다.

## 오류 처리

- `ErrorManager`는 가장 먼저 생성되는 Autoload이며, 오류 메시지는 HUD보다 위인 CanvasLayer 100에 표시한다. `PrestigeManager`는 짬 조건을 검사하는 `ButtonManager`보다 먼저 생성된다.
- 버튼·수입원의 중복 ID는 조회·구매를 거절한다. 이벤트는 잘못된 리소스·중복 ID의 추가 등록을 거절하며 이미 등록한 정의는 유지한다. 잘못된 수입원은 실행 상태에서 제외하고 월드 구성이 잘못된 버튼은 구매를 막는다. `require_node()`·`initialize_component()`를 사용하는 UI는 필수 노드가 없으면 오류를 보고하고 동작을 중단한다. 모든 UI가 이 검증 경로를 사용하는 것은 아니다.
- 공통 검증 경로는 자금·배율의 유효하지 않은 수치와 큰 수의 지원 지수 범위 초과를 알리고 잘못된 결과를 거절한다. 매우 큰 값은 약 15자리 유효숫자로 계산하며, 잔액에 즉시 표현되지 않는 작은 입출금은 별도 잔여값으로 누적한다. 수입원별 소수 원과 계산 잔여값도 보관하고 저장한다. 환생 짬도 정수 범위를 넘으면 근사 큰 수로 계산한다.
- 같은 `code`와 `context`는 세션 중 한 번만 표시하고 발생 횟수를 누적한다. 서로 다른 오류는 확인 버튼으로 차례대로 볼 수 있으며, 이력은 최대 100개까지 보관한다. 한도를 넘으면 `ERROR_LIMIT` 알림으로 추가 오류가 있음을 알린다.
- 자금 부족, 아직 해금되지 않은 버튼, 중복 클릭, 보상 없는 환생은 정상적인 거절이므로 오류 창을 띄우지 않는다.

다른 게임 로직에서도 같은 경로로 오류를 보고한다.

```gdscript
ErrorManager.report_error("ERROR_CODE", "사용자에게 보여 줄 오류 설명", "발생 위치 또는 ID")
var errors := ErrorManager.get_errors() # 외부에서 수정할 수 없는 이력 사본
ErrorManager.clear_errors() # 이력·대기 메시지·중복 표시 상태 초기화
```

명시적으로 공통 검증을 호출한 오류를 처리한다. 실행 중 잘못된 타입 비교·null 접근 같은 엔진 스크립트 오류, 문법 오류, Autoload 생성 전의 `preload` 실패는 자동으로 가로채지 않으므로 Godot 디버거·로그에서 확인해야 한다.

## 렌더링

### 장면 깊이

- 하늘(-100) < 구름(-90) < 실내 뒷배경/벽지(-20) < 전경/창문(-10) < 가구/인물/조리대(0) < 앞쪽 테두리/기둥/주춧돌/천장(10) < 땅(20) < 땅 가림막(25) < 구매 버튼(30) < 설명/생산 타이머/말풍선(40)
- 공통 레이어 이름과 값은 `scripts/RenderOrder.gd`에서 관리한다. 구매 종류(`ButtonData.Type`)와 효과는 렌더링 순서에 관여하지 않는다.
- 월드의 깊이는 `world_layout.tscn`에서 구매/해금 ID를 가진 각 오브젝트의 `SceneRenderLayer.gd`로 지정한다. 인스펙터의 `Rendering > Render Layer`를 선택하면 되며, `VendingMachine`, `Restaurant`, `Spa`, `Bumin`, `Lab` 같은 지역 그룹은 배치를 묶는다. 한 오브젝트를 구성하는 자식들은 해당 오브젝트의 레이어를 상속하고, 벽지처럼 다른 깊이가 필요한 자식에만 별도로 레이어를 지정한다.
- 구매 후 생성되는 스프라이트는 원본의 부모까지 포함한 실제 z-index를 보존한다. 같은 깊이에서는 월드 레이아웃의 노드 순서를 따른다.
- 화면 레이어는 설명/툴팁(1) < HUD·우측 패널(2) < 우측 버튼(3) < 저장 화면(4) < 고양이 이벤트(5) < 환생 암전·고양이 이펙트(6) < 개발자 도구(10) < 오류 메시지(100) 순서다. 같은 화면 레이어 안에서는 노드 깊이와 순서를 따른다. 일부 레이어는 원본 씬에 고정 배치하지 않고 실행 중 생성해 컨트롤을 옮긴다.

### 구매 배율 효과의 수입원 크기 연출

- `SOURCE_MULTIPLIER`와 `SOURCE_SPEED_MULTIPLIER` 효과를 구매하면 해당 수입원 이미지가 튀어오르듯 커졌다가 원래 크기로 돌아온다. `GLOBAL_MULTIPLIER`와 `GLOBAL_TIME_MULTIPLIER`는 구매되어 활성화된 모든 수입원에 동시에 적용한다.
- `WorldPurchaseButton`의 실제 구매 완료 신호에서 대상 수입원의 `purchased_visuals`에 `SizePopMotion.pulse()`를 호출한다. 0.1초 동안 기본 크기의 110%까지 커지고, 0.2초 동안 복귀하므로 총 0.3초다. 마우스 영역과 생산 타이머의 크기는 유지한다.
- 연속 적용 시 이전 트윈을 종료하고 현재 표시 크기에서 다시 시작한다. 복귀 목표는 최초 기본 크기로 보관해 트윈 도중의 커진 값을 새 기준으로 삼지 않는다. 수입원 최초 구매의 등장 트윈과 겹쳐도 같은 기본 크기를 사용한다.
- 환생·진행 초기화 등으로 구매 그림이 숨겨지면 트윈을 취소하고 기본 크기를 즉시 복원한다. 재구매 시에도 크기 변화가 누적되지 않는다.
- 구매 실패, 효과 없음, 배율 1배는 이 연출을 시작하지 않는다. 저장 복원·툴팁·자금 표시 갱신도 구매 완료 신호를 발생시키지 않으므로 연출을 다시 시작하지 않는다.

## 아트와 애니메이션 제작 기록

고양이 원본·실루엣·짬통 애니메이션·앱 아이콘의 제작 정보와 원문 프롬프트를 보존한다. 긴 프롬프트는 아래에서 펼쳐 볼 수 있다.

### 고양이 기본 스프라이트

- Asset: `res://assets/sprites/Cat/Cat_idle.png`
- Tool: built-in `image_gen` (generation followed by a color-finish refinement).
- Format: PNG with transparent alpha; single full-body sitting pose.
- Art direction: simple geometric shapes, a small orange/cream palette, bold black outlines, a clear silhouette matching the game's existing props.

#### Generation prompt

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: stylized-concept
Asset type: one production-ready 2D cat sprite for the Godot side-view game FriendshipTycoon.
Primary request: Create ONE cute cat in the simple geometric, simple-color, clear, black-outline cartoon style of the existing game props viewed in this conversation.
Subject and pose: a small friendly orange-and-cream cat, sitting upright in a relaxed idle pose. A broad round head, simple triangular ears, a compact oval body, two short front paws and one simple curved tail curling beside the body. Body in a slight three-quarter view oriented toward the right, face turned toward the viewer. Two tiny solid black oval eyes, a small triangular nose and a tiny curved W mouth. Readable cute silhouette even at 64 pixels tall.
Style/medium: very simple flat 2D game sprite, clean geometric shapes, smooth crisp edges. Uniform bold SOLID BLACK outlines around the silhouette and major overlapping parts, approximately 12-14 px at 1024 px canvas size, rounded joins. Flat solid-color fills only.
Color palette: warm light orange for the coat; pale cream for a single muzzle and belly patch and paw tips; muted pink for inner ears and tiny nose; solid black for outlines and facial marks. Only a few large simple markings, no detailed fur. Equal simple treatment across all parts.
Composition/framing: a single complete full-body cat centered on a square canvas, ears, feet, whiskers and tail fully inside the frame with about 10% clear padding. Place all feet on the same horizontal baseline. One static pose, one sprite, no sheet.
Background: actual transparent alpha everywhere outside the cat, including spaces between the legs and the tail. No floor and no cast shadow.
Constraints: no text, no labels, no watermark, no props, no collar, no accessories, no background scene. No gradient, texture, fur rendering, realistic anatomy, shading, highlights, 3D render, pixel art, sketchy strokes, giant sparkling anime eyes, white sticker border or drop shadow. Make the geometry simple and the expression warm.
```

</details>

#### Final refinement prompt

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: style-transfer
Asset type: final static transparent 2D game cat sprite.
Input image 1 is the EDIT TARGET: the orange sitting cat just generated.
Change only the coloring finish: turn every colored region into a perfectly even, opaque solid flat fill. Make this look like a very clean simple vector cartoon exported as PNG. Remove ALL grain, paper texture, speckle, color variation, lighting, gradients, shadow and highlights from the orange coat, cream patches, pink ears and nose, and orange tabby markings. Use exactly these six solid interior colors: coat #FFA344, markings #D96C21, cream #FFF0CD, pink #F58B94, black #000000, and no other interior fill colors. Smooth antialiasing is allowed only on the shape boundaries. All interior shapes must be fully opaque.
Keep the exact same cute character, pose, full-body silhouette, facial expression, paws, head size, curled tail, stripe locations, framing and uniform bold black outlines. Preserve the transparent background and transparent gaps. Do not add or remove any body parts. No sticker border, no text, no background, no floor, no shadow. Produce only the finished single cat sprite, full body visible.
```

</details>

### 고양이 실루엣

- Source: `res://assets/sprites/Cat/Cat_idle.png`
- Output: `res://assets/sprites/Cat/Cat_silhouette.png`
- Tool: built-in `image_gen`, transparent image edit.
- Size: 1254 × 1254 pixels, RGBA PNG.

#### Prompt

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: precise-object-edit
Asset type: black silhouette PNG sprite derived from an existing cat sprite.
Input image 1 is the EDIT TARGET: Cat_idle.png.
Perform only this exact change: replace every visible part of the existing cat, including its entire head, ears, whiskers, muzzle, eyes, body, paws, stripes and tail, with uniform pure solid black RGB(0,0,0). Remove all interior color and internal features so the result is one completely black silhouette.
Preserve the exact original outer contour, pose, scale, position, original square canvas dimensions, transparent padding, and original transparent gaps, particularly the gap inside the curled tail. Do not redraw, simplify, reshape, expand, crop, move or resize the silhouette. Keep smooth antialiased outer edges and preserve original transparency. All opaque interior pixels must be pure black, no gray or white pixels. Actual transparent alpha background; no checkerboard pattern, backdrop, shadows, glow, stroke outside the existing contour, labels or text. Output one single transparent black silhouette sprite.
```

</details>

### 짬통 고양이 호버 애니메이션

- Tool: built-in `image_gen` using the existing jjamtong and cat as image references.
- New images: `res://assets/sprites/Restaurant/JjamtongCat/peek_1.png`, `peek_2.png`, `peek_open.png` (1038 × 1515, transparent PNG).
- Frame resource: `res://data/animations/jjamtong_cat_frames.tres`.
- Applied to: `Restaurant/jjamtong/bin` in `scenes/world_layout.tscn`.
- Hover enter: closed → ears → eyes → face; 12 frames per second, three changes over 0.25 seconds, then hold.
- Hover exit: face → eyes → ears → closed. Reverses from the current state if interrupted.
- The original bin body is drawn unchanged from `jjamtong.png` below row 62. AtlasTexture regions select only the newly generated lid/cat/rim artwork and align it to that body. No new generated body replaces the original.
- Input uses the existing HoverArea, independently of whether purchased tooltips are enabled. Removing the purchase resets the animation.

#### Verification

```powershell
& 'C:\Users\user\Godot Engine\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file .godot/jjamtong_hover_test.log res://tests/jjamtong_hover.tscn
```

Add `-- --render-preview` when running with a graphics renderer to save a four-state engine-rendered preview to `.godot/jjamtong_hover_preview.png`. Tests use the real world layout, purchased sprite duplication and HoverArea signals without initializing player saves.

#### Fully open frame

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: precise-object-edit
Asset type: a single transparent PNG animation end-frame for an existing 2D Godot game.
Input image 1 is the EDIT TARGET: the existing tall blue jjamtong bin with green lid. Input image 2 is a CHARACTER REFERENCE: the existing cute orange cat.
Primary request: Show this same cat INSIDE this same bin, with ONLY ITS HEAD peeking out of the top opening, and the green lid lifted open above the cat. The whole cat body, paws, legs and tail are hidden inside the opaque bin. The head is about 60 percent of the bin rim width, looking straight toward the player, with the same face and orange stripes as the reference.
Preserve the ORIGINAL BIN extremely closely: same tall tapered front-view blue body, exactly the same proportions, four vertical blue ribs, same two large white/gray curved arrows making the recycling circle, same gray wheels, original simple black outlines, original flat blue and green colors. Keep the entire original body below the top rim unchanged in shape and appearance. Do not redesign, shorten, widen, round, simplify or add a new recycling logo to the bin.
Lid: the same green trapezoid lid and short green handle, lifted above the head, hinged at the BACK of the bin. The cat's ears gently lift it; it is tipped slightly upward at one side, supported visibly above/behind the cat. Show a narrow dark interior at the bin mouth, and let the lower edge of the head be occluded by the FRONT rim.
Framing: one complete isolated bin with its whole head, lid and wheels visible. Tall portrait transparent canvas, generous room above the original bin. Keep the bin body centered, upright, with wheels on a horizontal baseline close to the lower canvas edge. No camera rotation. The body must have the same horizontal center, width and height used in future intermediate frames.
Style: clean very simple 2D game sprite, simple geometric shapes, simple flat colors, bold solid black contour outlines, crisp smooth edges. Match the source bin art, no fur texture, no rendering.
Actual transparent alpha background, including any gaps between lid, ears and bin. No scene, no floor, no shadows, no white sticker border, no grid, no text, no labels, no motion marks. ONLY ONE sprite, no sheet.
```

</details>

#### Intermediate 1: ears

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: precise-object-edit
Asset type: first intermediate frame of an opening animation, one transparent game sprite.
Input image 1 is the EDIT TARGET: the fully-open cat-in-bin animation end frame. Input image 2 is the original closed bin REFERENCE for the green lid shape.
Change ONLY the pose of the lid and how far the cat head is visible. Keep the exact same canvas size, framing, pixel alignment, bin width, bin height, side faces, rim position, wheels and body. The entire blue bin body and recycling arrows below the mouth must remain IDENTICAL. Do not move or resize the image or bin.
This intermediate frame is just ONE THIRD of the way from fully closed to fully open: lower the green lid so it sits just 20 percent of the final distance above the front rim, almost closed. Keep it very slightly tilted, with a narrow dark opening below it. Hide almost all of the cat inside the opaque bin: ONLY the two orange triangular ear tips and a tiny bit of the top of the orange forehead can be seen in the small gap between front rim and lid. No eyes, no nose, no mouth, no paws, no body, no tail visible.
Leave the large upper area above the lowered lid completely TRANSPARENT. Keep the original canvas with the bin's mouth at exactly the same height and wheels in exactly the same pixels as the edit target; do not recenter or crop.
Match the simple flat black-outlined geometric style of the original bin, with orange/cream cat markings. Actual transparent alpha background. No labels, text, grid, white sticker outline or background. ONE complete sprite only.
```

</details>

#### Intermediate 2: eyes

<details>
<summary>생성 프롬프트 원문</summary>

```text
Use case: precise-object-edit
Asset type: second intermediate frame of a 2D game bin-opening animation, one transparent sprite.
Input image 1 is the EDIT TARGET: the fully open orange cat in the blue bin. Input image 2 is the first intermediate animation frame for identity and positioning consistency.
Change ONLY the green lid height/tilt and how far the cat head protrudes. Keep the EXACT same canvas dimensions and bin placement as both references. The blue body, rim, ribs, recycling arrows and wheels must remain at the same pixel positions and have the same proportions. Do not recenter, zoom, crop, resize, change perspective or redraw the body.
This frame is TWO THIRDS of the way to the fully open frame: the cat is halfway up with both round black eyes visible just above the front rim, but its nose, mouth and cream muzzle are mostly hidden BEHIND the opaque front rim. Its ears and forehead are fully visible. Keep the orange cat head the same size and same horizontal position as the open reference: simply lower the entire head about 90 pixels inside the bin.
Lower the lid so it rests gently above the partially emerged ears, about halfway between the first intermediate frame's lid and the fully open frame's lid. Preserve the original green handle and trapezoid green lid, with a dark green underside. Leave the space above the lowered lid fully transparent. No cat body, legs, paws or tail.
Clean simple flat-color geometric cartoon sprite with bold black outlines, matching the original bin and existing cat. Preserve real transparent alpha background and gaps. ONE full sprite only, no sheet, labels, text, grid, floor, shadow or white sticker border.
```

</details>

## 앱 아이콘

2026-10-17 수정. `res://assets/sprites/Friendship_Mark.png` 원본을 사용한다. 원본의 연한 금색, 배지와 날개의 모양, 부드러운 가장자리와 투명도는 유지하고, 중앙 **우정** 글자의 회색만 검은색으로 바꾼다. 글꼴과 획 모양도 원본을 유지한다.

#### 아이콘 파일

| 파일 | 포맷 / 크기 | 용도 |
| --- | --- | --- |
| `res://icon.png` | 512 × 512, 32비트 RGBA PNG, sRGB, 투명 배경 | Godot 기본 앱 아이콘 |
| `res://icon.ico` | 16, 24, 32, 48, 64, 128, 256 px를 담은 ICO | Windows 네이티브 아이콘 |
| `res://assets/icons/Friendship_icon_master.png` | 원본과 같은 528 × 328 RGBA PNG, sRGB | 글자색만 검은색으로 바꾼 원본 크기 마스터 |

`icon.png`는 원본의 가로세로 비율을 유지한 464 × 288 이미지를 512 × 512 투명 캔버스의 `(24, 112)` 위치에 배치한다. 기존 `icon.png.import`의 UID를 유지하므로 `application/config/icon`이 같은 파일을 가리킨다. Windows는 `application/config/windows_native_icon = "res://icon.ico"`를 사용한다.

#### 원본 보존과 검증

- 원본 글자의 회색 채움과 가장자리 색을 픽셀 단위로 검은색에 맞춰 변환한다. 글자 가장자리의 안티앨리어싱은 유지한다.
- 크기 조정 전 마스터와 원본을 비교해 알파 채널이 완전히 같은지 확인했다.
- 변경된 픽셀은 글자 영역 `(158, 121)–(363, 220)` 안의 5,493개뿐이다. 원래 회색 단색 글자 4,514픽셀이 모두 순수 검은색 `#000000`으로 바뀌었고, 나머지 영역은 원본 픽셀과 같다.
- PNG는 512 × 512, RGBA, sRGB 프로필과 투명 여백을 확인한다. ICO는 일곱 해상도를 포함하며, 같은 원본 기반 아이콘에서 크기별로 내보낸다.

#### 플랫폼 규격과 출처 · 2026-10-16 확인

- [Google Play icon specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications): 512 × 512 px, 32-bit PNG, sRGB, at most 1024 KB. Submit a full square without baked outer corner rounding or drop shadow; the store applies those effects.
- [Windows app icon construction](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction): minimum common sizes are 16, 24, 32, 48 and 256 px. [Win32 ICO reference](https://learn.microsoft.com/en-us/windows/win32/menurc/about-icons) explains the multiple images stored in one ICO.
- [Godot Windows application icon guide](https://docs.godotengine.org/en/stable/tutorials/export/changing_application_icon_for_windows.html): ICO should include 16, 32, 48, 64, 128 and 256 px to cover all default Godot icon sizes. The project native-icon setting controls the Windows runtime icon. Windows exports can generate the executable icon automatically from the project PNG when no export-preset icon override is supplied.
- [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive): launcher adaptive icons are separate from the Google Play listing image. They use foreground/background layers at 108 × 108 dp, with important content in the inner 66 × 66 dp safe zone. This task replaces the project's main icon; no adaptive foreground/background layer files were created.
- [Godot Android export options](https://docs.godotengine.org/en/4.5/classes/class_editorexportplatformandroid.html): an empty `launcher_icons/main_192x192` falls back to the project's configured icon. No export presets existed in the workspace at the time of this change.

## 실행과 검증

Godot 4.7에서 `project.godot`를 열고 메인 장면을 실행한다. PC에서는 마우스 드래그·휠로 카메라를 이동·확대하고, 모바일 입력에는 두 손가락 핀치 줌 처리가 있다. 개발자 도구는 `OS.is_debug_build()`가 참일 때 O 키로 열고 닫는다. 자금 추가, 생산 시간·수입 배율 변경, 이벤트 상태 조회와 즉시 발동을 제공한다.

### 테스트 장면

다음은 현재 `tests/`에 존재하는 장면이다. `godot`는 설치한 Godot 실행 파일의 경로로 대체할 수 있다. 목록은 검증 목적을 설명하며 현재 작업 트리에서 전부 통과했다는 뜻은 아니다.

```powershell
godot --headless --path . res://tests/big_numbers.tscn --fixed-fps 60
godot --headless --path . res://tests/big_number_payments.tscn --fixed-fps 60
godot --headless --path . res://tests/income_growth.tscn
godot --headless --path . res://tests/income_upgrade_panel.tscn
godot --headless --path . res://tests/income_upgrade_pointer.tscn
godot --headless --path . res://tests/income_upgrade_reentrancy.tscn
godot --headless --path . res://tests/save_system.tscn
godot --headless --path . res://tests/events.tscn
godot --headless --path . res://tests/jjamtong_hover.tscn
godot --headless --path . res://tests/income_effect_pop.tscn --fixed-fps 60
godot --headless --path . res://tests/balance_playthrough.tscn --fixed-fps 60
```

| 장면 | 확인 대상 / 주의점 |
| --- | --- |
| `big_numbers` | 단위 경계·큰 수 연산·표시·개발자 입력·저장·환생·지수 성장. 일부 환생 검사는 이전 환생 규칙을 기대함 |
| `income_growth` | `balance_playthrough.gd`의 `curve_checks_only = true` 장면. 설정된 성장 간격(현재 60레벨)의 배율·일정한 레벨당 증가율·고레벨·캐시 변경을 검사하며 진행 시뮬레이션 로그는 덮어쓰지 않음 |
| `big_number_payments` | 작은 입출금 잔여값, 여러 FPS의 생산 지급, 콜백 중 초기화, 저장 복원 |
| `income_upgrade_panel` | 실제 패널의 가격·구매 가능 여부·음영·구매 후 갱신. 현재 일부 기대값은 옛 자판기 첫 가격 30원과 이전 곡선의 고레벨 가격을 고정 사용하므로 현행 데이터와 대조 필요 |
| `income_upgrade_pointer` | 실제 포인터 입력으로 이미지 아래 빈 공간·투명 모서리 클릭 차단, 정상 클릭, 버튼 밖 홀드 유지와 해제 검사 |
| `income_upgrade_reentrancy` | 결제·레벨·수입 신호의 재진입, 일관된 저장, 초기화·환생·불러오기, 실패 후 재시도와 큰 수 가격. `.godot` 아래 별도 저장소 사용 |
| `save_system` | `.godot` 아래에서 슬롯·이전·손상·UI·자동 저장. 일부 옛 짬 기대값과 런타임 재배치 전 UI 경로는 수정 필요. 종료 요청은 `-- --close-request`로 추가 실행 |
| `events` | 추첨·쿨타임·폰 UI·보상·저장. `spa` 구매·60초 쿨타임 등 옛 기대값이 현재 `bumin` 영구 해금·150초 쿨타임·최소 제시액과 다름 |
| `jjamtong_hover` | 실제 월드 복제·HoverArea 신호·열기/닫기. 그래픽 실행에서 `-- --render-preview`로 `.godot/jjamtong_hover_preview.png` 생성 |
| `income_effect_pop` | 실제 구매와 월드 이미지 복제, 개별·전역 수입/속도 효과, 0.3초 재생, 연속 40회 적용, 최초 등장 중 적용, 실제 프레임 진행, 초기화·재구매 시 기본 크기 복원 |
| `balance_playthrough` | 최저가 우선 자동 구매. 현재 데이터에서 완료 시간 재측정 필요 |

저장 기능을 검사하는 장면은 `.godot` 아래 별도 저장소를 사용하며 플레이어의 `saves/`는 사용하지 않는다. 기존 `runtime_regression`, `error_handling_smoke`, `render_order_smoke` 장면은 현재 트리에 없다.

### 밸런스 테스트 해석

`balance_playthrough`는 자금·짬 0에서 시작한다. 해금된 미구매 버튼과 활성 수입원의 다음 레벨업 중 가장 싼 항목을 선택하며, 자금이 부족하면 실제 생산 로직을 60FPS 가상 시간으로 진행한다. 같은 가격이면 버튼 우선, 이후 등록 순서다. 모든 등록 버튼을 구매하면 종료하며 환생·외부 자금·클릭 지연은 없다. 이벤트를 포함한 수동 플레이 전체를 재현하는 테스트는 아니다.

실행 결과는 `logs/balance_playthrough.txt`에 덮어쓴다. 버튼별 가격·해금 시점·구매 시간과 전체 구매 기록을 남기며, 지수 성장·캐시·미리보기도 검사한다. 과거 시간 목표는 기본적으로 참고값이다. `enforce_legacy_pacing_targets`를 켜면 식당 구매 120~180초, 유리문 해금 600초 이상, 완료 시간 `1779.6667초 ±5%`를 실패 조건으로 검사한다. 이 기준은 현재 수입원·구매 가격·해금 조건의 완료 시간을 보장하지 않으며 현행 데이터로 재측정해야 한다.

기존 문서의 **18개 버튼 / 약 29분 48초 완료 / 변경 전 대비 +0.45%**는 이전 데이터의 측정 기록이다. 현재 등록된 32개 버튼과 변경된 수입원 곡선의 결과로 사용할 수 없으므로 현행 밸런스 수치에서 제외했다. 과거 기준 로그는 `logs/balance_playthrough_before_curve.txt`에 있다.

### 별도 점검 문서

[프로젝트 구조 및 버그 점검](docs/PROJECT_REVIEW.md)은 요청에 따라 통합 대상에서 제외했다. 과거 점검 기록과 당시의 위험 분석은 이 문서와 구분해서 읽는다.

[짬 환생 제작 기록](docs/JJAM_PRESTIGE.md)도 별도로 남아 있다. 그 문서의 환산 비율 등은 이전 설정일 수 있으므로, 현재 동작은 이 문서의 [짬 환생 항목](#짬-환생과-우측-패널)과 `PrestigeManager.gd`·이벤트 리소스를 기준으로 확인한다.

이 문서는 루트 `README.md`, `docs/BIG_NUMBERS.md`, `data/events/README.md`, `docs/art/Cat_idle_prompt.md`, `docs/art/Cat_silhouette_prompt.md`, `docs/art/Jjamtong_cat_hover.md`, `docs/art/App_icon.md`를 통합한 것이다. 앞으로 게임 구조·편집 안내·제작 기록은 루트의 `GameOverview.md`에서 관리한다.
