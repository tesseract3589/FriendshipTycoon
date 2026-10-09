@tool
extends RefCounted

const SCIENTIFIC_NOTATION_THRESHOLD: float = 100000000000.0
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
	var value_text := format_number(value) if absf(seconds) < TIME_UNIT_MIN_SECONDS[unit_index] else "%.2f" % value
	return value_text + TIME_UNITS[unit_index]


static func format_income_per_second(value: float) -> String:
	return format_number(roundf(value))


static func format_number(value: float) -> String:
	if not is_finite(value):
		return str(value)
	var absolute_value := absf(value)
	if absolute_value >= SCIENTIFIC_NOTATION_THRESHOLD or (absolute_value > 0.0 and absolute_value < 0.01):
		return _format_scientific(value)

	var is_negative := value < 0.0
	# Round once before separating the digits, so 999.999 carries into 1,000.
	var decimal_text := "%.2f" % absolute_value
	var whole_text := _group_digits(decimal_text.get_slice(".", 0))
	var decimal_part := decimal_text.get_slice(".", 1)
	if is_negative:
		whole_text = "-" + whole_text
	if decimal_part == "00":
		return whole_text
	return "%s.%s" % [whole_text, decimal_part]


static func _format_scientific(value: float) -> String:
	var is_negative := value < 0.0
	var mantissa := absf(value)
	var exponent := 0
	while mantissa >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while mantissa < 1.0:
		mantissa *= 10.0
		exponent -= 1

	var mantissa_milli := roundi(mantissa * 1000.0)
	if mantissa_milli >= 10000:
		mantissa_milli = 1000
		exponent += 1
	var mantissa_whole := floori(float(mantissa_milli) / 1000.0)
	var mantissa_decimal := str(mantissa_milli % 1000).pad_zeros(3)
	var sign_text := "-" if is_negative else ""
	var exponent_sign := "+" if exponent >= 0 else "-"
	return "%s%d.%se%s%d" % [sign_text, mantissa_whole, mantissa_decimal, exponent_sign, absi(exponent)]


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
