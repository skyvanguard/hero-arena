class_name Map
extends Resource
## A map as DATA (Phase 6, D18): all layout values are @exports so new maps
## are .tres files under content/maps/ - no code change per map. The arena
## geometry is a set of axis-aligned boxes (cover/platforms), unit crates,
## ramps, health pickups, and the two team spawn rows. Original layouts only.
@export var map_id := ""
@export var display_name := ""
## Short name for compact UI buttons (hero-select map picker).
@export var short_name := ""
@export var size := 44.0
## Team spawn points (the CENTER spawn - index 1 - doubles as the CTF base
## and the escort lane endpoint, so it must sit on the central lane).
@export var spawn_team0: Array[Vector3] = []
@export var spawn_team1: Array[Vector3] = []
## Cover boxes: parallel arrays (pos[i], box_sizes[i]).
@export var boxes: Array[Vector3] = []
@export var box_sizes: Array[Vector3] = []
## Unit crates (1 m cubes) at these positions.
@export var crates: Array[Vector3] = []
## Ramps: parallel arrays (ramps[i], ramp_lengths[i]), rotated -12 deg about
## X, 3 m wide (see Arena._ramp).
@export var ramps: Array[Vector3] = []
@export var ramp_lengths: Array[float] = []
## Health pickup positions.
@export var potions: Array[Vector3] = []
