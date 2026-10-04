class_name Slug
extends Node3D
## Slock's emergency slug: a small glowing projectile fired along one of the four grid directions. It flies
## straight at Slock's height, killing the first swurm it reaches or blasting the first inner wall block into
## floor; an outer wall or a locked gate stops it, and it fizzles after RANGE tiles. main.gd fires it and
## handles what it hits.

const RANGE := 4                  # tiles
const SPEED := 24.0               # tiles/s

enum Hit { FLYING, SWURM, WALL, MISS }

var section: Section
var dir := Vector3.ZERO           # horizontal, along the grid
var swurm_hit: Swurm              # what it hit, when it hits a swurm
var _travelled := 0.0


static func fire(from: Vector3, direction: Vector3, in_section: Section) -> Slug:
	var slug := Slug.new()
	slug.section = in_section
	slug.dir = direction
	slug.position = from + direction * 0.6 * in_section.tile
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.mesh.size = Vector3.ONE * 0.15 * in_section.tile
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.6, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(2.0, 0.9, 0.1)
	cube.mesh.material = glow
	Section._outline(cube)
	slug.add_child(cube)
	return slug


## Move on by `delta` seconds; what it ran into (if anything) this step.
func step(delta: float) -> Hit:
	var d := SPEED * section.tile * delta
	position += dir * d
	_travelled += d
	for swurm in section.swurms:
		if not swurm.eaten and (swurm.head_position() - position).length() < 0.57 * section.tile:
			swurm_hit = swurm
			return Hit.SWURM
	var t := section.tile_under(position)
	if section.tile_at(t.x, t.y) == Section.WALL:
		if section.blast_wall(t):
			return Hit.WALL
		return Hit.MISS # an outer wall stops it
	if t == section.exit_tile() and not section.gate_open():
		return Hit.MISS # so does a locked gate
	if _travelled >= RANGE * section.tile:
		return Hit.MISS
	return Hit.FLYING
