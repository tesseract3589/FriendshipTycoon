@tool
class_name BigNumber
extends RefCounted

## Immutable approximate decimal. Ordinary values keep the native float fast path.
## At large magnitudes retain ~15 significant digits and discard insignificant tails.
const MAX_EXPONENT: int = 1000000000
const ALIGNMENT_DIGITS: int = 16
const SIGNIFICAND_SCALE: int = 100000000000000
var mantissa: float
var exponent: int

func _init(coefficient: float = 0.0, power: int = 0) -> void:
	# Normalize public construction too, so the same value behaves alike in both types.
	if coefficient == 0.0:
		power = 0
	elif is_finite(coefficient) and (absf(coefficient) < 1.0 or absf(coefficient) >= 10.0):
		if power < -MAX_EXPONENT - 400 or power > MAX_EXPONENT + 400:
			coefficient = NAN
			power = 0
		else:
			var shift := clampi(floori(log(absf(coefficient)) / log(10.0)), -300, 300)
			coefficient /= pow(10.0, shift)
			power += shift
			if absf(coefficient) < 1.0 or absf(coefficient) >= 10.0:
				shift = floori(log(absf(coefficient)) / log(10.0))
				coefficient /= pow(10.0, shift)
				power += shift
			if absf(coefficient) >= 10.0:
				coefficient /= 10.0
				power += 1
			elif absf(coefficient) < 1.0:
				coefficient *= 10.0
				power -= 1
	if is_finite(coefficient) and coefficient != 0.0:
		# One canonical 15-digit decimal grid across native/scientific conversions.
		coefficient = roundf(coefficient * SIGNIFICAND_SCALE) / SIGNIFICAND_SCALE
		if absf(coefficient) >= 10.0:
			coefficient /= 10.0
			power += 1
	mantissa = coefficient
	exponent = power

static func parts(value: Variant) -> BigNumber:
	if value is BigNumber:
		return value
	var number := float(value)
	if number == 0.0 or not is_finite(number):
		return BigNumber.new(number, 0)
	var power := floori(log(absf(number)) / log(10.0))
	# Avoid pow(10, -324) underflow for the smallest native doubles.
	power = clampi(power, -300, 300)
	var coefficient := number / pow(10.0, power)
	# log can round to the adjacent decade; recompute directly to avoid two divisions.
	if absf(coefficient) < 1.0 and power > -300:
		power -= 1
		coefficient = number / pow(10.0, power)
	elif absf(coefficient) >= 10.0 and power < 300:
		power += 1
		coefficient = number / pow(10.0, power)
	return _normalized(coefficient, power)

static func _normalized(coefficient: float, power: int) -> BigNumber:
	return BigNumber.new(coefficient, power)

static func _pack(coefficient: float, power: int) -> Variant:
	var number := _normalized(coefficient, power)
	if not is_finite(number.mantissa) or number.exponent < -MAX_EXPONENT or number.exponent > MAX_EXPONENT:
		return NAN
	if number.mantissa == 0.0:
		return 0.0
	if number.exponent >= -300 and number.exponent <= 300:
		return number.mantissa * pow(10.0, number.exponent)
	return number

static func valid(value: Variant, allow_zero: bool = true) -> bool:
	return valid_signed(value) and (compare(value, 0.0) >= 0 if allow_zero else compare(value, 0.0) > 0)

static func valid_signed(value: Variant) -> bool:
	if value is BigNumber:
		return is_finite(value.mantissa) and ((absf(value.mantissa) >= 1.0 and absf(value.mantissa) < 10.0) or (value.mantissa == 0.0 and value.exponent == 0)) and value.exponent >= -MAX_EXPONENT and value.exponent <= MAX_EXPONENT
	return (value is float or value is int) and is_finite(float(value))

static func compact(value: Variant) -> Variant:
	return _pack(value.mantissa, value.exponent) if value is BigNumber else value

static func absolute(value: Variant) -> Variant:
	return BigNumber.new(absf(value.mantissa), value.exponent) if value is BigNumber else absf(float(value))

## Add without losing the low part: sum plus signed rounding residual.
static func add_with_residual(a: Variant, b: Variant) -> Array:
	if not a is BigNumber and not b is BigNumber:
		var first := float(a)
		var second := float(b)
		var sum := first + second
		if is_finite(sum):
			return [sum, (first - sum) + second if absf(first) >= absf(second) else (second - sum) + first]
	return _decimal_sum(a, b, true)

static func compare(a: Variant, b: Variant) -> int:
	if not a is BigNumber and not b is BigNumber:
		return 0 if a == b else (1 if a > b else -1)
	var left := parts(a)
	var right := parts(b)
	if left.mantissa == 0.0 or right.mantissa == 0.0 or signf(left.mantissa) != signf(right.mantissa):
		return 0 if left.mantissa == right.mantissa else (1 if left.mantissa > right.mantissa else -1)
	var direction := 1 if left.mantissa > 0.0 else -1
	if left.exponent != right.exponent:
		return direction if left.exponent > right.exponent else -direction
	return 0 if left.mantissa == right.mantissa else (1 if left.mantissa > right.mantissa else -1)

static func add(a: Variant, b: Variant) -> Variant:
	if not a is BigNumber and not b is BigNumber:
		var result := float(a) + float(b)
		if is_finite(result):
			return result
	return _decimal_sum(a, b, false)[0]

static func _decimal_sum(a: Variant, b: Variant, keep_residual: bool) -> Array:
	if not valid_signed(a) or not valid_signed(b):
		return [NAN, NAN]
	var left := parts(a)
	var right := parts(b)
	var left_value: Variant = a
	var right_value: Variant = b
	if left.mantissa == 0.0:
		return [b, 0.0]
	if right.mantissa == 0.0:
		return [a, 0.0]
	if left.exponent < right.exponent:
		var swap := left
		left = right
		right = swap
		left_value = b
		right_value = a
	var difference := left.exponent - right.exponent
	if difference > ALIGNMENT_DIGITS:
		return [left_value, right_value if keep_residual else 0.0]
	# Integer significands make mixed arithmetic and cancellation deterministic.
	var divisor := int(pow(10.0, difference))
	var left_digits := roundi(left.mantissa * SIGNIFICAND_SCALE)
	var right_digits := roundi(right.mantissa * SIGNIFICAND_SCALE)
	var combined := left_digits + right_digits / divisor
	var common_exponent := left.exponent
	var alignment_remainder := right_digits % divisor
	if difference <= 3:
		# Align exactly before cancellation; the largest intermediate fits int64.
		combined = left_digits * divisor + right_digits
		common_exponent = right.exponent
		alignment_remainder = 0
	var sum: Variant = _pack(float(combined) / SIGNIFICAND_SCALE, common_exponent)
	if not keep_residual:
		return [sum, 0.0]
	if not valid_signed(sum):
		return [sum, NAN]
	var represented := 0
	if compare(sum, 0.0) != 0:
		var sum_parts := parts(sum)
		represented = roundi(sum_parts.mantissa * SIGNIFICAND_SCALE)
		var shift := sum_parts.exponent - common_exponent
		if shift >= 0:
			represented *= int(pow(10.0, shift))
		else:
			represented /= int(pow(10.0, -shift))
	var rounding_tail: Variant = _pack(float(combined - represented), common_exponent - 14)
	var alignment_tail: Variant = _pack(float(alignment_remainder), right.exponent - 14)
	return [sum, add(rounding_tail, alignment_tail)]

static func subtract(a: Variant, b: Variant) -> Variant:
	if not a is BigNumber and not b is BigNumber:
		var result := float(a) - float(b)
		if is_finite(result):
			return result
	var right := parts(b)
	return add(a, BigNumber.new(-right.mantissa, right.exponent))

static func multiply(a: Variant, b: Variant) -> Variant:
	if not a is BigNumber and not b is BigNumber:
		var result := float(a) * float(b)
		if is_finite(result) and (result != 0.0 or float(a) == 0.0 or float(b) == 0.0):
			return result
	var left := parts(a)
	var right := parts(b)
	return _pack(left.mantissa * right.mantissa, left.exponent + right.exponent)

static func divide(a: Variant, b: Variant) -> Variant:
	if compare(b, 0.0) == 0:
		return NAN
	if not a is BigNumber and not b is BigNumber:
		var result := float(a) / float(b)
		if is_finite(result) and (result != 0.0 or float(a) == 0.0):
			return result
	var left := parts(a)
	var right := parts(b)
	return _pack(left.mantissa / right.mantissa, left.exponent - right.exponent)

static func power_of_ten(power: float) -> Variant:
	if not is_finite(power) or absf(power) > MAX_EXPONENT:
		return NAN
	var whole := floori(power)
	return _pack(pow(10.0, power - whole), whole)

static func square_root(value: Variant) -> Variant:
	if not value is BigNumber:
		return sqrt(float(value))
	var odd := posmod(value.exponent, 2)
	return _pack(sqrt(value.mantissa * (10.0 if odd else 1.0)), (value.exponent - odd) / 2)

static func rounded(value: Variant) -> Variant:
	if not value is BigNumber:
		return roundf(float(value))
	if value.exponent < -1:
		return 0.0
	if value.exponent > 15:
		return value
	return roundf(value.mantissa * pow(10.0, value.exponent))

static func floored(value: Variant) -> Variant:
	if not value is BigNumber:
		return floorf(float(value))
	if value.exponent < 0:
		return -1.0 if value.mantissa < 0.0 else 0.0
	if value.exponent > 15:
		return value
	return floorf(value.mantissa * pow(10.0, value.exponent))

static func truncated(value: Variant) -> Variant:
	return floored(value) if compare(value, 0.0) >= 0 else subtract(0.0, floored(absolute(value)))

static func whole_count(value: Variant) -> Variant:
	if value is int:
		return value
	var whole: Variant = floored(value)
	if compare(whole, 9223372036854775808.0) < 0:
		return int(whole)
	return whole

static func parse(text: String) -> Variant:
	var cleaned := text.strip_edges().to_lower()
	var segments := cleaned.split("e")
	if segments.size() > 2 or not segments[0].is_valid_float():
		return NAN
	var coefficient := segments[0].to_float()
	var power := 0
	if segments.size() == 2:
		if not segments[1].is_valid_int() or segments[1].trim_prefix("+").trim_prefix("-").length() > 10:
			return NAN
		power = segments[1].to_int()
	if absi(power) > MAX_EXPONENT:
		return NAN
	if power >= -300 and power <= 300:
		var native := coefficient * pow(10.0, power)
		if is_finite(native) and (native != 0.0 or coefficient == 0.0):
			return native
	return _pack(coefficient, power)

static func serialize(value: Variant, force_decimal: bool = false) -> Variant:
	if value is BigNumber or force_decimal:
		var number := parts(value)
		if number.mantissa == 0.0:
			return 0.0
		return {"decimal_mantissa": number.mantissa, "decimal_exponent": number.exponent}
	return value

static func serialize_count(value: Variant) -> Variant:
	var count: Variant = whole_count(value)
	return count if count is int else serialize(count, true)

static func is_serialized(value: Variant, allow_signed: bool = false) -> bool:
	return value is Dictionary and value.size() == 2 and value.get("decimal_mantissa") is float \
		and value.get("decimal_exponent") is int and is_finite(value.decimal_mantissa) \
		and (absf(value.decimal_mantissa) >= 1.0 and absf(value.decimal_mantissa) < 10.0 if allow_signed else value.decimal_mantissa >= 1.0 and value.decimal_mantissa < 10.0) and value.decimal_exponent >= -MAX_EXPONENT and value.decimal_exponent <= MAX_EXPONENT

static func deserialize(value: Variant, allow_signed: bool = false) -> Variant:
	if is_serialized(value, allow_signed):
		return _pack(value.decimal_mantissa, value.decimal_exponent)
	return value

func _to_string() -> String:
	return "%se%d" % [String.num(mantissa, 16), exponent]
