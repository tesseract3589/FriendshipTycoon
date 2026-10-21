# 짬 환생

- `PrestigeManager.jjam_unlocked`: 슬롯별 영구 해금. 첫 짬통 구매 시 켜지며 짬 환생으로 꺼지지 않습니다.
- `banked_jjam`: 환생으로 확정한 짬. 수입 부스트의 기준입니다.
- `live_jjam` / `current_jjam`: 이번 환생에서 받을 짬. 부스트나 재화 소비에는 사용하지 않습니다.
- `total_jjam`: 확정 짬 + 실시간 짬.
- `prestige_count`: 새 짬 환생의 실행 횟수. `No Prestige Only` 이벤트는 이 값으로 판별합니다.

## 계산과 저장

`IncomeManager.total_earned_income`은 전체 누적 수익이고, `jjam_earned_income`은 첫 해금 이후 이번 환생까지의 수익입니다. 지출과 별도로 보관하며 큰 수의 잔여 정밀도도 저장합니다. 수입원 지급, 수락한 폰 DM 보상, 개발자 도구로 추가한 금액을 모두 수익으로 계산합니다. 짬통 해금 이후 개발자 도구로 추가하는 금액도 같은 환산 비율로 실시간 짬에 즉시 반영됩니다. 폰 DM 보상은 거래 확정 때 한 번만 기록하므로 입금 애니메이션 중 저장해도 중복 계산되지 않습니다.

실시간 짬은 `floor(jjam_earned_income / money_per_jjam)`이며, 첫 해금부터 첫 환생까지는 400짬을 추가합니다. 기본 `money_per_jjam`은 1.2조 원(1,200,000,000,000원), `boost_per_jjam`은 1%입니다. 두 값은 `autoload/PrestigeManager.gd`의 export 변수로 조정합니다.

수입 배율은 `1 + banked_jjam × boost_per_jjam / 100`입니다. 새 짬 환생을 한 번도 하지 않았다면 0% 보너스입니다. 옛 계산 방식의 짬은 로드 시 폐기하고 기존 전역 배율에 포함된 옛 짬 배율도 제거합니다. 새 저장에는 해금, 두 짬, 누적 수익, 첫 400짬 지급 여부, 환생 횟수를 따로 기록합니다.

## UI와 이벤트

`data/events/jjamtong_intro_event.tres`는 짬통 구매 조건의 Instant / One Off 이벤트입니다. `JjamPrestigePresentation`이 UI와 입력을 잠그고 카메라 이동, 기존 고양이 빼꼼 애니메이션, 1초 대기, 원래 줌 복귀를 처리합니다. 슬롯을 바꾸면 진행 중인 연출을 취소하고 입력과 UI를 복구합니다.

새 우측 패널은 `RightPanelManager.register_panel(content)`로 등록하고 `open_panel(content)` 또는 `toggle_panel(content)`로 엽니다. 다른 등록 패널은 자동으로 닫힙니다. 저장 화면은 `close_all()`을 호출하고 개발자 도구는 이 관리자에 등록하지 않습니다.

표시 순서: 기본 HUD → 우측 버튼 → 저장 화면 → 이벤트 → 환생 암전 → 개발자 도구 → 오류 화면.

짬 환생은 암전 중 확정 짬 추가, 실시간 수익 초기화, 돈·일반 구매·수입원 레벨과 배율 초기화, 카메라 복귀를 처리하고 패널을 닫습니다. 우측 짬 환생 버튼, 영구 해금, 일회성 이벤트 이력은 유지합니다. 재입대·초월 로직은 아직 구현하지 않습니다.

화면이 밝아지면 `data/effects/jjam_prestige_cats.tres`의 설정으로 고양이 30개가 0.3초에 걸쳐 화면 곳곳에서 나타납니다. 각 고양이는 짧게 튀어나온 뒤 1초 동안 우측 짬 환생 버튼으로 모이며 작아집니다. 재사용 장면은 `ui/effects/jjam_cat_effect.tscn`입니다. 화면 크기가 바뀌어도 도착점은 현재 버튼 중앙을 따라가며, 슬롯을 바꾸면 남은 이펙트를 정리합니다.
