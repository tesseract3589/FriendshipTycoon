class_name JjamGrowthData
extends Resource

const BIG = preload("res://scripts/BigNumber.gd")

## 실시간 짬이 기준 짬의 2배, 4배, 8배가 될 때마다 1짬의 필요 수익에 곱합니다.
## 1이면 기존 선형 환산입니다. 기준 짬 이하에서는 초기 환산 비율을 유지합니다.
@export_range(1.0, 100.0, 0.1, "or_greater") var difficulty_multiplier: float = 4.0


## Integrate the tier prices, including any boundaries crossed by one large reward.
## Returns fractional progress too; the manager floors only the displayed/usable jjam.
func get_earned_jjam(income: Variant, holdings: Variant, initial_jjam: int, base_price: float) -> Variant:
	if BIG.compare(income, 0.0) <= 0:
		return 0.0
	var factor := difficulty_multiplier if is_finite(difficulty_multiplier) else 4.0
	factor = maxf(factor, 1.0)
	if factor == 1.0:
		return BIG.divide(income, base_price)
	var tier := maxi(0, floori(_log_base(BIG.divide(holdings, initial_jjam), 2.0))) if BIG.compare(holdings, initial_jjam) > 0 else 0
	# Correct logarithm rounding at exact powers of two.
	var lower: Variant = BIG.multiply(initial_jjam, _power(2.0, tier))
	if tier > 0 and BIG.compare(holdings, lower) < 0:
		tier -= 1
	var boundary: Variant = BIG.multiply(initial_jjam, _power(2.0, tier + 1))
	if BIG.compare(holdings, boundary) >= 0:
		tier += 1
		boundary = BIG.multiply(boundary, 2.0)
	var price: Variant = BIG.multiply(base_price, _power(factor, tier))
	var to_boundary: Variant = BIG.subtract(boundary, holdings)
	var first_cost: Variant = BIG.multiply(to_boundary, price)
	if BIG.compare(income, first_cost) < 0:
		return BIG.divide(income, price)
	var remaining: Variant = BIG.subtract(income, first_cost)
	var earned: Variant = to_boundary
	tier += 1
	price = BIG.multiply(price, factor)
	# Full tiers form a geometric series with ratio 2 * factor. Skip them in
	# logarithmic time instead of looping once per jjam or per enormous exponent.
	var ratio := 2.0 * factor
	var tier_cost: Variant = BIG.multiply(boundary, price)
	var geometric: Variant = BIG.add(1.0, BIG.divide(BIG.multiply(remaining, ratio - 1.0), tier_cost))
	var full_tiers := maxi(0, floori(_log_base(geometric, ratio)))
	var full_cost: Variant = _full_tier_cost(tier_cost, ratio, full_tiers)
	if full_tiers > 0 and BIG.compare(full_cost, remaining) > 0:
		full_tiers -= 1
		full_cost = _full_tier_cost(tier_cost, ratio, full_tiers)
	var next_cost: Variant = _full_tier_cost(tier_cost, ratio, full_tiers + 1)
	if BIG.compare(next_cost, remaining) <= 0:
		full_tiers += 1
		full_cost = next_cost
	var width_growth: Variant = _power(2.0, full_tiers)
	earned = BIG.add(earned, BIG.multiply(boundary, BIG.subtract(width_growth, 1.0)))
	remaining = BIG.subtract(remaining, full_cost)
	price = BIG.multiply(price, _power(factor, full_tiers))
	return BIG.add(earned, BIG.divide(remaining, price))


func _full_tier_cost(first_cost: Variant, ratio: float, count: int) -> Variant:
	return BIG.multiply(first_cost, BIG.divide(BIG.subtract(_power(ratio, count), 1.0), ratio - 1.0))


func _log_base(value: Variant, base: float) -> float:
	var parts := BIG.parts(value)
	return (log(parts.mantissa) + parts.exponent * log(10.0)) / log(base)


func _power(base: float, exponent: int) -> Variant:
	# Integer exponentiation keeps exact small tier boundaries exact.
	var result: Variant = 1.0
	var factor: Variant = base
	var remaining := exponent
	while remaining > 0:
		if remaining % 2 == 1:
			result = BIG.multiply(result, factor)
		remaining >>= 1
		if remaining > 0:
			factor = BIG.multiply(factor, factor)
	return result
