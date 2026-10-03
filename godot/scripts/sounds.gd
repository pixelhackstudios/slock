class_name Sounds
extends Node
## Sound effects (not positional). The pellet pops, ouches and steel woo were made in Audacity; the big pop and
## slug clicks by art-work/sounds.py. How loud each plays is set here. Where there are several of a kind, it
## picks one at random, never the same one twice in a row.

const PELLET_VOLUME := 0.2        # kept quiet: pellets go off constantly and mustn't become a distraction
const PELLET_TUNE := -8.0         # semitones: the pops play this far below how they were recorded
const PELLET_DETUNE := 0.55       # semitones of random pitch wobble, so repeats never sound copy-pasted
const VOICES := 6                 # pops can overlap; each gets its own player so detuning doesn't bleed
const OUCH_VOLUME := 0.5          # Slock hit by a swurm (the clips are recorded near full volume)
const PICKUP_VOLUME := 0.5        # power pellets and powerups: steel woo, slug clicks, big pop
const BIG_POP_DETUNE := 1.0       # semitones of random pitch wobble on the big pop

var _pellets: Array[AudioStream] = []
var _ouches: Array[AudioStream] = []
var _steel: AudioStream
var _slug_click: AudioStream
var _slug_reload: AudioStream
var _big_pop: AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _ouch_player: AudioStreamPlayer # its own player, so a burst of pops can't cut it off
var _pickup_player: AudioStreamPlayer # likewise
var _next_voice := 0
var _last_pellet := -1
var _last_ouch := -1


func _ready() -> void:
	for i in 6:
		_pellets.append(load("res://sounds/Pellet%d.wav" % (i + 1)))
	for i in 5:
		_ouches.append(load("res://sounds/Ouch%d.wav" % (i + 1)))
	_ouch_player = AudioStreamPlayer.new()
	add_child(_ouch_player)
	_steel = load("res://sounds/Steel.wav")
	_slug_click = load("res://sounds/SlugClick.wav")
	_slug_reload = load("res://sounds/SlugReload.wav")
	_big_pop = load("res://sounds/BigPop.wav")
	_pickup_player = AudioStreamPlayer.new()
	add_child(_pickup_player)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)


## A pellet eaten: one of the six pops, slightly detuned.
func pellet() -> void:
	_last_pellet = _pick(_pellets.size(), _last_pellet)
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	_play(p, _pellets[_last_pellet], PELLET_VOLUME * randf_range(0.8, 1.0),
		pow(2.0, (PELLET_TUNE + randf_range(-PELLET_DETUNE, PELLET_DETUNE)) / 12.0))


## Slock hit by a swurm: one of the five ouches.
func ouch() -> void:
	_last_ouch = _pick(_ouches.size(), _last_ouch)
	_play(_ouch_player, _ouches[_last_ouch], OUCH_VOLUME, 1.0)


## Slock of Steel picked up.
func steel() -> void:
	_play(_pickup_player, _steel, PICKUP_VOLUME, 1.0)


## One slug picked up: a clip snapping in.
func slug_click() -> void:
	_play(_pickup_player, _slug_click, PICKUP_VOLUME, 1.0)


## Slugs refilled: a quick reload.
func slug_reload() -> void:
	_play(_pickup_player, _slug_reload, PICKUP_VOLUME, 1.0)


## A power pellet or pellet powerup: a big bubble pop.
func big_pop() -> void:
	_play(_pickup_player, _big_pop, PICKUP_VOLUME, pow(2.0, randf_range(-BIG_POP_DETUNE, BIG_POP_DETUNE) / 12.0))


## A random index below `count` that isn't `last`.
static func _pick(count: int, last: int) -> int:
	var i := randi_range(0, count - 2)
	if last >= 0 and i >= last:
		i += 1
	return i


func _play(p: AudioStreamPlayer, stream: AudioStream, volume: float, pitch: float) -> void:
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	p.pitch_scale = pitch
	p.play()
