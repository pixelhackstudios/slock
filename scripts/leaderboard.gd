class_name Leaderboard
## The local top 10, saved on this computer (Godot's user data folder), with the last name entered. Kept behind
## this small API so an online board could slot in later.

const MAX := 10
const PATH := "user://leaderboard.json"


## The entries, best first: each {name, score, height, seconds, date}.
static func entries() -> Array:
	return _load().get("entries", [])


## The name last entered, to offer again.
static func last_name() -> String:
	return _load().get("last_name", "")


## Whether `score` makes the board.
static func qualifies(score: int) -> bool:
	if score <= 0:
		return false
	var list := entries()
	return list.size() < MAX or score > int(list[-1].score)


## Adds a run and returns its rank (1 = best), or 0 if it didn't make the board.
static func submit(name: String, score: int, height: int, seconds: float) -> int:
	var data := _load()
	var list: Array = data.get("entries", [])
	var entry := {"name": name, "score": score, "height": height, "seconds": roundi(seconds),
		"date": Time.get_date_string_from_system()}
	list.append(entry)
	list.sort_custom(func(a, b): return int(a.score) > int(b.score))
	list.resize(mini(list.size(), MAX))
	data["entries"] = list
	data["last_name"] = name
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
	return list.find(entry) + 1


static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}
