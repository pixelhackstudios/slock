extends SceneTree
## Exports the game's world for the website (website/public/world/), built by the game's own code so the site shows
## exactly what the game draws:
##   section-<i>.glb   each section's visible mesh, its materials swapped for plain ones named after their texture set
##                     (the site puts the textures back on)
##   world.json        what the site needs to dress and play each section: the layout, the tiles and their floor
##                     heights, where the pellets, pickups, swurms, gate and booster chevrons are
##   jelly.glb         the rounded block Slock and the swurms are made of
##   textures/         the maze's textures as WebP, at web sizes
##   models/           copies of the pickups, gate and chevron (models/*.glb)
##
## From the repository root, with Godot 4.7:
##   godot --path . --script website/tools/export_world.gd -- [seed] [sections]
## then run `npm run world` in website/ to compress the meshes.

const OUT := "res://website/public/world"
const TEXTURE_SIZES := {"floor": 1024, "cap": 1024, "wall": 512, "cliff": 512, "ramp": 512, "pen": 512}
const MODELS := ["clock", "key", "steel", "clear_dots", "close_traps", "slug_pack", "extra_slug", "slug", "gate", "chevron"]

var run_seed := 20261005
var count := 6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		run_seed = int(args[0])
	if args.size() > 1:
		count = int(args[1])
	seed(run_seed) # the powerups' kinds are picked at random as they're placed
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/textures"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/models"))
	var sections: Array[Section] = []
	for i in count:
		var s := Section.new(i, run_seed)
		root.add_child(s)
		sections.append(s)
	_export.call_deferred(sections)


func _export(sections: Array[Section]) -> void:
	while not sections.all(func(s: Section) -> bool: return s.built):
		await process_frame
	var world := {"seed": run_seed, "sections": []}
	for s in sections:
		_write_mesh(s)
		world.sections.append(_describe(s))
	var f := FileAccess.open(OUT + "/world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	f.close()
	_write_jelly()
	_write_textures()
	for name in MODELS:
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://models/%s.glb" % name),
			ProjectSettings.globalize_path(OUT + "/models/%s.glb" % name))
	print("exported %d sections (seed %d) to %s" % [sections.size(), run_seed, ProjectSettings.globalize_path(OUT)])
	quit()


## The section's visible mesh (its strips) as section-<i>.glb.
func _write_mesh(s: Section) -> void:
	var names := {} # material -> texture set
	for set_name in Section._looks:
		names[Section._looks[set_name]] = set_name
	var plain := {} # texture set -> a plain material with its name
	var holder := Node3D.new()
	holder.name = "section_%d" % s.index
	for strip: MeshInstance3D in s._strips:
		var mesh: ArrayMesh = strip.mesh.duplicate()
		for k in mesh.get_surface_count():
			var set_name: String = names[mesh.surface_get_material(k)]
			if not plain.has(set_name):
				var m := StandardMaterial3D.new()
				m.resource_name = set_name
				plain[set_name] = m
			mesh.surface_set_material(k, plain[set_name])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		holder.add_child(mi)
	_write_glb(holder, OUT + "/section-%d.glb" % s.index)


func _write_glb(node: Node, path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(node, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("couldn't write %s (%d)" % [path, err])
	node.free()


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _describe(s: Section) -> Dictionary:
	var floors := [] # [col][row]: floor height at the near-left, near-right, far-right and far-left corners
	for col in s.width:
		var column := []
		for row in s.length:
			var f := s._floor_corners(col, row)
			column.append([snappedf(f[0], 0.0001), snappedf(f[1], 0.0001), snappedf(f[2], 0.0001), snappedf(f[3], 0.0001)])
		floors.append(column)
	var items := [] # pellets, power pellets, clocks, keys and powerups
	for key: Vector2i in s.pellets:
		var kind: String = Section.Eaten.keys()[s.pellets[key]].to_lower()
		var c := s.tile_centre(key)
		items.append({"tile": [key.x, key.y], "kind": kind, "at": _v3(Vector3(c.x, s._heights[key], c.z))})
	var chevrons := []
	for child in s.get_children():
		if child is Node3D and child.scene_file_path == "res://models/chevron.glb":
			var b: Basis = child.basis
			chevrons.append({"at": _v3(child.position), "basis": _v3(b.x) + _v3(b.y) + _v3(b.z)})
	var homes := []
	for h in s.swurm_homes:
		homes.append([h.x, h.y])
	return {
		"index": s.index, "tile": s.tile, "floor": s.floor_y, "prevFloor": s._prev_floor, "nearEdge": s.near_edge,
		"width": s.width, "length": s.length, "centre": s.centre, "mazeLeft": s.maze_left, "mazeRight": s.maze_right,
		"mazeStart": s.maze_start, "side": [s._side.x, s._side.y, s._side.z], "layout": s.layout,
		"tiles": s.tiles, "levels": s.levels, "floors": floors,
		"start": _v3(s.start_position(Slock.HEIGHT_RATIO * s.tile)), "exit": _v3(s.tile_centre(s.exit_tile())),
		"landing": [s.landing_tile().x, s.landing_tile().y],
		"items": items, "chevrons": chevrons, "swurmHomes": homes,
		"swurms": MazeGen.swurm_count(s.index), "swurmSpeed": MazeGen.swurm_speed(s.index),
	}


## The rounded block (models/SlockJelly.fbx) as jelly.glb.
func _write_jelly() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "jelly"
	var mesh: Mesh = Jelly.mesh().duplicate()
	for k in mesh.get_surface_count():
		mesh.surface_set_material(k, StandardMaterial3D.new())
	mi.mesh = mesh
	var holder := Node3D.new()
	holder.add_child(mi)
	_write_glb(holder, OUT + "/jelly.glb")


## The maze's textures (textures/maze/<set>_<map>.png) as WebP: albedo, normal and ORM (and the pen's glow).
func _write_textures() -> void:
	for set_name in TEXTURE_SIZES:
		var size: int = TEXTURE_SIZES[set_name]
		for map in ["albedo", "normal", "orm", "emission"]:
			var src := ProjectSettings.globalize_path("res://textures/maze/%s_%s.png" % [set_name, map])
			if not FileAccess.file_exists(src):
				continue
			var img := Image.load_from_file(src)
			img.convert(Image.FORMAT_RGB8)
			if img.get_width() != size:
				img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			img.save_webp(ProjectSettings.globalize_path(OUT + "/textures/%s_%s.webp" % [set_name, map]), true, 0.9)
