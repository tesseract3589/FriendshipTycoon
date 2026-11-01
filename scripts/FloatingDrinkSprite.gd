extends AnimatedSprite2D

@export_range(0.0, 5.0, 0.01, "or_greater") var phase_delay: float = 0.0
@export_range(0.0, 20.0, 0.5, "or_greater") var float_amplitude: float = 4.0
@export_range(0.1, 10.0, 0.1, "or_greater") var float_period: float = 2.4

var _base_y: float
var _float_time: float


func _ready() -> void:
	# Runtime purchase visuals duplicate already-floating layout sprites.
	_base_y = get_meta(&"_drink_float_base_y", position.y)
	set_meta(&"_drink_float_base_y", _base_y)
	_float_time = -phase_delay
	if sprite_frames == null or not sprite_frames.has_animation(animation):
		set_process(false)
		return
	var speed := sprite_frames.get_animation_speed(animation)
	var count := sprite_frames.get_frame_count(animation)
	if speed <= 0.0 or count == 0:
		set_process(false)
		return
	var cycle_seconds := 0.0
	for index in range(count):
		cycle_seconds += sprite_frames.get_frame_duration(animation, index) / speed
	# Start behind the left sprite on the same loop, rather than starting late once.
	var phase := fposmod(-phase_delay, cycle_seconds)
	play(animation)
	for index in range(count):
		var seconds := sprite_frames.get_frame_duration(animation, index) / speed
		if phase < seconds:
			set_frame_and_progress(index, phase / seconds)
			break
		phase -= seconds
	_update_float()


func _process(delta: float) -> void:
	_float_time = fposmod(_float_time + delta, float_period)
	_update_float()


func _update_float() -> void:
	position.y = _base_y + sin(TAU * _float_time / float_period) * float_amplitude
