extends RefCounted

const INITIAL_DELAY: float = 0.4
const ACCELERATION: float = 0.82
const MIN_INTERVAL: float = 0.06

var active: bool = false
var _remaining: float = 0.0
var _interval: float = INITIAL_DELAY
var _has_purchased: bool = false


func start(purchase: Callable) -> void:
	active = true
	_remaining = 0.0
	_interval = INITIAL_DELAY
	_has_purchased = false
	advance(0.0, purchase)


func stop() -> void:
	active = false
	_remaining = 0.0


func advance(delta: float, purchase: Callable) -> void:
	if not active:
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining > 0.0:
		return
	# An unaffordable purchase waits here without resetting the speed or building
	# up missed purchases. Retry next frame so new income is used promptly.
	if not purchase.call() or not active:
		return
	if _has_purchased:
		_interval = maxf(MIN_INTERVAL, _interval * ACCELERATION)
	_has_purchased = true
	_remaining = _interval
