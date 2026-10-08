extends RefCounted

const SCIENTIFIC_NOTATION_THRESHOLD: float = 100000000000.0


static func format_number(value: float) -> String:
	if not is_finite(value):
		return str(value)
	if absf(value) >= SCIENTIFIC_NOTATION_THRESHOLD:
		return _format_scientific(value)

	var is_negative := value < 0.0
	var absolute_value := absf(value)
	var whole_part := floori(absolute_value)
	var whole_text := _group_digits(str(whole_part))
	if is_negative:
		whole_text = "-" + whole_text
	if is_equal_approx(absolute_value, float(whole_part)):
		return whole_text

	var decimal_text := "%.2f" % absolute_value
	var decimal_part := decimal_text.get_slice(".", 1)
	return "%s.%s" % [whole_text, decimal_part]


static func _format_scientific(value: float) -> String:
	var is_negative := value < 0.0
	var mantissa := absf(value)
	var exponent := 0
	while mantissa >= 10.0:
		mantissa /= 10.0
		exponent += 1

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
