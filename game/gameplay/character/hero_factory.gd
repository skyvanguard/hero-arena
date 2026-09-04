class_name HeroFactory
extends RefCounted
## Builds a Hero node tree in code (no external assets — placeholder visuals).
## Phase 2 replaces placeholder meshes with original art through the same
## factory (cosmetic slots only; the node contract stays stable).

const BODY_H := 1.8

static func create(team: int, is_player: bool, color: Color = Color.WHITE,
		hero_data: HeroData = null) -> Hero:
	if hero_data != null and color == Color.WHITE:
		color = hero_data.color
	var h := Hero.new()
	h.name = "Hero_%d_%d" % [team, randi() % 1000]
	h.team = team
	h.display_name = ("You" if is_player else "Bot") + " %d" % (team * 10 + randi() % 10)
	h.is_player = is_player
	if hero_data != null:
		h.hero_data = hero_data
		h.max_hp = hero_data.max_hp
		h.base_speed = hero_data.base_speed
		h.jump_velocity = hero_data.jump_velocity
	h.collision_layer = CharacterEntity.LAYER_BODY
	h.collision_mask = CharacterEntity.LAYER_WORLD | CharacterEntity.LAYER_BODY | CharacterEntity.LAYER_HEAD

	# Body collider (capsule).
	var body_shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CharacterEntity.BODY_RADIUS
	cap.height = BODY_H
	body_shape.shape = cap
	h.add_child(body_shape)

	# Body visual.
	var body_mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = CharacterEntity.BODY_RADIUS
	capsule.height = BODY_H
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	capsule.material = mat
	body_mesh.mesh = capsule
	body_mesh.position.y = BODY_H * 0.5
	h.add_child(body_mesh)

	# Team marker (readability: team color always visible).
	var team_marker := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.14
	cone.height = 0.25
	var tm := StandardMaterial3D.new()
	tm.albedo_color = (Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.35, 0.3))
	cone.material = tm
	team_marker.mesh = cone
	team_marker.position.y = BODY_H + 0.2
	h.add_child(team_marker)

	# Head (visual + separate sensor for headshots, own collision layer).
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = CharacterEntity.HEAD_OFFSET
	var head_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = color.lightened(0.25)
	sphere.material = hmat
	head_mesh.mesh = sphere
	head.add_child(head_mesh)
	# StaticBody (not Area3D): in Godot 4.7, intersect_ray does not report
	# Area3Ds here, so an Area sensor made the head completely unhittable
	# (Phase 4 duel probe: rays passed through heads and hit the wall).
	var head_sensor := StaticBody3D.new()
	head_sensor.name = "HeadSensor"
	head_sensor.collision_layer = CharacterEntity.LAYER_HEAD
	head_sensor.collision_mask = 0
	var head_shape := CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = CharacterEntity.HEAD_RADIUS
	head_shape.shape = hs
	head_sensor.add_child(head_shape)
	head.add_child(head_sensor)
	var head_marker := Marker3D.new()
	head_marker.name = "HeadMarker"
	head.add_child(head_marker)
	h.add_child(head)

	# Gun + muzzle.
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.32, 1.28, 0.4)
	var gun_mesh := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.12, 0.22, 0.62)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.16, 0.2)
	gbox.material = gmat
	gun_mesh.mesh = gbox
	gun.add_child(gun_mesh)
	var flash := OmniLight3D.new()
	flash.name = "MuzzleFlash"
	flash.position = Vector3(0, 0.02, 0.36)
	flash.light_energy = 2.0
	flash.light_color = Color(1.0, 0.85, 0.5)
	flash.omni_range = 6.0
	flash.visible = false
	gun.add_child(flash)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.02, 0.36)
	gun.add_child(muzzle)
	h.add_child(gun)

	# Weapon (sim component).
	var weapon := Weapon.new()
	h.add_child(weapon)
	h.weapon = weapon
	weapon.setup(h)
	weapon.ready()
	if hero_data != null:
		_apply_weapon_profile(weapon, hero_data.weapon)
		var ab := AbilityComponent.new()
		ab.name = "Ability"
		h.add_child(ab)
		h.ability = ab
		ab.setup(hero_data, h)
		# Balance layer (content/balance/): per-hero tuning multipliers.
		Balance.apply_to(h, hero_data)

	# Camera rig (players only): plain offset camera (over-the-shoulder).
	# Godot 4.7 reworked SpringArm3D (shape + spring_length); a fixed offset is
	# robust for Phase 1 and keeps the sim free of camera-collision coupling.
	if is_player:
		var rig := Node3D.new()
		rig.name = "CameraRig"
		rig.position.y = 1.65
		var cam := Camera3D.new()
		cam.name = "Camera3D"
		cam.position = Vector3(0.28, 0.02, -1.0)  # behind + right of head
		cam.rotation.y = PI                        # look along rig +Z (forward)
		cam.fov = 72.0
		cam.current = true
		rig.add_child(cam)
		h.add_child(rig)
		h.camera_rig = rig

	# Character origin: capsule center at 0.9 above floor.
	h.position.y = BODY_H * 0.5
	return h

static func _apply_weapon_profile(weapon: Weapon, profile: Dictionary) -> void:
	weapon.mode = str(profile.get("mode", "hitscan"))
	weapon.pellets = int(profile.get("pellets", weapon.pellets))
	weapon.damage = float(profile.get("damage", weapon.damage))
	weapon.headshot_mult = float(profile.get("headshot_mult", weapon.headshot_mult))
	weapon.fire_rate = float(profile.get("fire_rate", weapon.fire_rate))
	weapon.clip_size = int(profile.get("clip_size", weapon.clip_size))
	weapon.reload_time = float(profile.get("reload_time", weapon.reload_time))
	weapon.max_range = float(profile.get("max_range", weapon.max_range))
	weapon.spread_deg = float(profile.get("spread_deg", weapon.spread_deg))
	weapon.projectile_speed = float(profile.get("proj_speed", weapon.projectile_speed))
	weapon.projectile_range = float(profile.get("proj_range", weapon.projectile_range))
	weapon.projectile_slow_ratio = float(profile.get("proj_slow_ratio", 0.0))
	weapon.projectile_slow_duration = float(profile.get("proj_slow_duration", 0.0))
	weapon.ready()
