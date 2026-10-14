@tool
extends RefCounted

const BIG = preload("res://scripts/BigNumber.gd")
const LARGE_UNITS: Array[String] = ["", "만", "억", "조", "경", "해", "자", "양", "구", "간", "정", "재", "극", "항하사", "아승기", "나유타", "불가사의", "무량대수"]
const TIME_UNITS: Array[String] = ["s", "ms", "μs", "ns", "ps", "fs", "as", "zs", "ys", "rs", "qs"]
# Compare explicit second thresholds to keep boundary rounding consistent.
const TIME_UNIT_MIN_SECONDS: Array[float] = [1.0e-2, 1.0e-5, 1.0e-8, 1.0e-11, 1.0e-14, 1.0e-17, 1.0e-20, 1.0e-23, 1.0e-26, 1.0e-29, 1.0e-32]


static func format_time(seconds: float) -> String:
	if not is_finite(seconds):
		return "%ss" % str(seconds)
	if seconds == 0.0:
		return "0.00s"
	var unit_index := 0
	while unit_index < TIME_UNITS.size() - 1 and absf(seconds) < TIME_UNIT_MIN_SECONDS[unit_index]:
		unit_index += 1
	var value := seconds / (TIME_UNIT_MIN_SECONDS[unit_index] * 100.0)
	# Keep smaller values in qs without rounding a positive interval to zero.
	var value_text := _format_scientific(value) if absf(seconds) < TIME_UNIT_MIN_SECONDS[unit_index] else "%.2f" % value
	return value_text + TIME_UNITS[unit_index]


static func format_income_per_second(value: Variant) -> String:
	value = BIG.compact(value)
	if value is BIG and value.exponent < 0:
		return "0"
	if value is BIG or (value is float or value is int) and absf(float(value)) >= 10000.0:
		return _format_large(value)
	if is_finite(float(value)) and roundf(absf(float(value)) * 100.0) >= 1000000.0:
		return _format_large(signf(float(value)) * 10000.0)
	return _format_small_income(float(value))


static func _format_small_income(value: float) -> String:
	if not is_finite(value):
		return str(value)
	var decimal_text := "%.2f" % absf(value)
	var sign_text := "-" if value < 0.0 else ""
	return _trim_decimal(sign_text + _group_digits(decimal_text.get_slice(".", 0)) + "." + decimal_text.get_slice(".", 1))


static func format_number(value: Variant) -> String:
	return _format_money(value, 2, true)


static func format_current_money(value: Variant) -> String:
	return _format_money(value, 4, false)


static func _format_money(value: Variant, decimal_places: int, trim_zeros: bool) -> String:
	value = BIG.compact(value)
	if value is BIG or (value is float or value is int) and absf(float(value)) >= 10000.0:
		return _format_large(value, trim_zeros)
	var scale := pow(10.0, decimal_places)
	if is_finite(float(value)) and roundf(absf(float(value)) * scale) >= 10000.0 * scale:
		return _format_large(signf(float(value)) * 10000.0, trim_zeros)
	return _format_small_number(float(value), decimal_places, trim_zeros)


static func _format_large(value: Variant, trim_zeros: bool = true) -> String:
	var number := BIG.parts(value)
	if not is_finite(number.mantissa):
		return str(number.mantissa)
	if number.exponent < 4:
		var mantissa_text := "%.4f" % number.mantissa
		return "%se%d" % [_trim_decimal(mantissa_text) if trim_zeros else mantissa_text, number.exponent]
	var group := floori(float(number.exponent) / 4.0)
	var coefficient := absf(number.mantissa) * pow(10.0, number.exponent - group * 4)
	var scaled := roundi(coefficient * 10000.0 + 1.0e-7)
	if scaled >= 100000000:
		scaled = 10000
		group += 1
	var digits := "%d.%s" % [scaled / 10000, str(scaled % 10000).pad_zeros(4)]
	if trim_zeros:
		digits = _trim_decimal(digits)
	var sign_text := "-" if number.mantissa < 0.0 else ""
	if group < LARGE_UNITS.size():
		return sign_text + digits + LARGE_UNITS[maxi(group, 0)]
	var scientific_scaled := roundi(absf(number.mantissa) * 10000.0 + 1.0e-8)
	var scientific_exponent := number.exponent
	if scientific_scaled >= 100000:
		scientific_scaled = 10000
		scientific_exponent += 1
	var scientific_digits := "%d.%s" % [scientific_scaled / 10000, str(scientific_scaled % 10000).pad_zeros(4)]
	if trim_zeros:
		scientific_digits = _trim_decimal(scientific_digits)
	return "%s%s만 x 10^%d" % [sign_text, scientific_digits, scientific_exponent - 4]


static func _format_small_number(value: float, decimal_places: int = 2, trim_zeros: bool = true) -> String:
	if not is_finite(value):
		return str(value)
	var absolute_value := absf(value)
	if absolute_value > 0.0 and absolute_value < pow(10.0, -decimal_places):
		return _format_scientific(value, maxi(3, decimal_places), trim_zeros)

	var is_negative := value < 0.0
	# Round once before separating the digits, so 999.999 carries into 1,000.
	var decimal_text := "%.*f" % [decimal_places, absolute_value]
	var whole_text := _group_digits(decimal_text.get_slice(".", 0))
	var decimal_part := decimal_text.get_slice(".", 1)
	if is_negative:
		whole_text = "-" + whole_text
	var digits := "%s.%s" % [whole_text, decimal_part]
	return _trim_decimal(digits) if trim_zeros else digits


static func _format_scientific(value: float, decimal_places: int = 3, trim_zeros: bool = false) -> String:
	var is_negative := value < 0.0
	var mantissa := absf(value)
	var exponent := 0
	while mantissa >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while mantissa < 1.0:
		mantissa *= 10.0
		exponent -= 1

	var decimal_scale := int(pow(10.0, decimal_places))
	var scaled_mantissa := roundi(mantissa * decimal_scale)
	if scaled_mantissa >= 10 * decimal_scale:
		scaled_mantissa = decimal_scale
		exponent += 1
	var mantissa_whole := floori(float(scaled_mantissa) / float(decimal_scale))
	var mantissa_decimal := str(scaled_mantissa % decimal_scale).pad_zeros(decimal_places)
	var sign_text := "-" if is_negative else ""
	var exponent_sign := "+" if exponent >= 0 else "-"
	var digits := "%s%d.%s" % [sign_text, mantissa_whole, mantissa_decimal]
	return "%se%s%d" % [_trim_decimal(digits) if trim_zeros else digits, exponent_sign, absi(exponent)]


static func _trim_decimal(digits: String) -> String:
	if not digits.contains("."):
		return digits
	while digits.ends_with("0"):
		digits = digits.trim_suffix("0")
	return digits.trim_suffix(".")


static func _group_digits(digits: String) -> String:
	var grouped := ""
	var digits_in_group := 0
	for index in range(digits.length() - 1, -1, -1):
		if digits_in_group == 3:
			grouped = "," + grouped
			digits_in_group = 0
		grouped = digits.substr(index, 1) + grouped
		digits_in_group += 1
	return grouped
