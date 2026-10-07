class_name FX
extends RefCounted
## Помощник: быстро создаёт простые системы частиц из кода
## (осколки, брызги, снег, искры), чтобы не описывать их вручную в сценах.


## one_shot = true — разовый всплеск (вызывай restart()), false — постоянный поток.
static func particles(color: Color, amount: int, lifetime: float, size: float,
		speed_min: float, speed_max: float, gravity: Vector3,
		spread: float = 180.0, one_shot: bool = true, emissive: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = speed_max
	pm.gravity = gravity
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	p.process_material = pm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 3.0
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p


## Задать частицам область появления в виде коробки.
static func set_box(p: GPUParticles3D, extents: Vector3) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
