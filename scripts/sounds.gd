class_name Sounds
extends Node
## Sound effects (not positional) and the music. The pellet pops, ouches and steel woo were made in Audacity; the
## big pop and slug clicks by art-work/sounds.py. The songs are in sounds/theme-music/. How loud
## each plays is set here. Where there are several of a kind, it picks one at random, never the same one twice in
## a row.

const PELLET_VOLUME := 0.5       # kept quiet: pellets go off constantly and mustn't become a distraction
const PELLET_TUNE := -8.0         # semitones: the pops play this far below how they were recorded
const PELLET_DETUNE := 0.55       # semitones of random pitch wobble, so repeats never sound copy-pasted
const VOICES := 6                 # pops can overlap; each gets its own player so detuning doesn't bleed
const OUCH_VOLUME := 0.4          # Slock hit by a swurm (the clips are recorded near full volume)
const PICKUP_VOLUME := 0.5        # power pellets and powerups: steel woo, big pop
const SLUG_VOLUME := 0.2          # slug pickups: the single slug and the three-slug pack
const BIG_POP_DETUNE := 1.0       # semitones of random pitch wobble on the big pop
const MUSIC_VOLUME := 0.7        # the music, under everything
const MUSIC_DELAY := 3.0          # seconds after the first run starts before the music comes in ...
const MUSIC_FADE := 4.0           # ... fading up over this long
const MUSIC_DIR := "res://sounds/theme-music/"

var _pellets: Array[AudioStream] = []
var _ouches: Array[AudioStream] = []
var _steel: AudioStream
var _slug_click: AudioStream
var _slug_reload: AudioStream
var _big_pop: AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _ouch_player: AudioStreamPlayer # its own player, so a burst of pops can't cut it off
var _pickup_player: AudioStreamPlayer # likewise
var _music: AudioStreamPlayer
var _themes: Array[String] = []   # the theme-0xx songs
var _queue: Array[String] = []    # ... still to play this time round
var _last_song := ""
var _music_started := false
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
	for file in ResourceLoader.list_directory(MUSIC_DIR):
		if file.begins_with("theme-") and file.ends_with(".ogg"):
			_themes.append(MUSIC_DIR + file)
	_music = AudioStreamPlayer.new()
	_music.process_mode = Node.PROCESS_MODE_ALWAYS # it plays on through pauses and slug aiming
	_music.finished.connect(_next_song)
	add_child(_music)


## The music, once the first run starts (the title screen is quiet): after MUSIC_DELAY seconds main-theme.ogg fades
## in, then the theme-0xx songs follow (see _next_song). Later runs leave it playing.
func start_music() -> void:
	if _music_started:
		return
	_music_started = true
	await get_tree().create_timer(MUSIC_DELAY, true).timeout
	_play(_music, load(MUSIC_DIR + "main-theme.ogg"), MUSIC_VOLUME, 1.0)
	_music.volume_db = -60.0
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(_music, "volume_db",
		linear_to_db(MUSIC_VOLUME), MUSIC_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## After the main theme, the theme-0xx songs in a shuffled order, reshuffled each time round (never the same song
## twice in a row).
func _next_song() -> void:
	if _themes.is_empty():
		_play(_music, _music.stream, MUSIC_VOLUME, 1.0)
		return
	if _queue.is_empty():
		_queue = _themes.duplicate()
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _last_song:
			_queue.reverse()
	_last_song = _queue.pop_front()
	_play(_music, load(_last_song), MUSIC_VOLUME, 1.0)


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
	_play(_pickup_player, _slug_click, SLUG_VOLUME, 1.0)


## Three slugs picked up: a quick reload.
func slug_reload() -> void:
	_play(_pickup_player, _slug_reload, SLUG_VOLUME, 1.0)


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
