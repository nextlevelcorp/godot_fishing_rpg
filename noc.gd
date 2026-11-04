## A small "Nature of Code" toolkit (https://natureofcode.com), shared by every moving thing in the
## shore scene so they all follow the same rules:
##   forces -> acceleration (a = F / m) -> velocity -> position   (Euler integration, ch. 2)
##   springs (Hooke's law, ch. 3), particles with gravity and drag (ch. 4),
##   autonomous agents: seek, flee, arrive, wander, containment and flocking (ch. 5),
##   a Verlet rope for the fishing line (ch. 6 style physics).
class_name Noc
extends RefCounted


## Reynolds-style autonomous agent ("vehicle"). Steering = desired velocity - current velocity,
## capped at max_force. Call the behaviours, apply_force() what they return, then update().
class Vehicle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var acc := Vector2.ZERO
	var max_speed := 60.0
	var max_force := 80.0
	var mass := 1.0
	var wander_theta := 0.0
	var data: Dictionary = {}

	func _init(p: Vector2 = Vector2.ZERO, speed: float = 60.0, force: float = 80.0) -> void:
		pos = p
		max_speed = speed
		max_force = force
		wander_theta = randf() * TAU
		vel = Vector2.from_angle(randf() * TAU) * speed * 0.3

	func apply_force(f: Vector2) -> void:
		acc += f / mass

	func update(dt: float) -> void:
		vel = (vel + acc * dt).limit_length(max_speed)
		pos += vel * dt
		acc = Vector2.ZERO

	func heading() -> Vector2:
		return vel.normalized() if vel.length() > 0.01 else Vector2.RIGHT

	func seek(target: Vector2) -> Vector2:
		var desired := (target - pos).normalized() * max_speed
		return (desired - vel).limit_length(max_force)

	func flee(threat: Vector2, radius: float) -> Vector2:
		var away := pos - threat
		if away.length() > radius or away.length() < 0.001:
			return Vector2.ZERO
		var desired := away.normalized() * max_speed
		return (desired - vel).limit_length(max_force)

	## Seek that slows down inside slow_radius and stops on the target.
	func arrive(target: Vector2, slow_radius: float) -> Vector2:
		var to := target - pos
		var d := to.length()
		if d < 0.001:
			return -vel.limit_length(max_force)
		var speed := max_speed
		if d < slow_radius:
			speed = max_speed * d / slow_radius
		return (to / d * speed - vel).limit_length(max_force)

	## Seek a point on a circle projected ahead; the point's angle drifts randomly.
	func wander(dt: float, distance: float = 40.0, radius: float = 20.0, jitter: float = 3.0) -> Vector2:
		wander_theta += randf_range(-jitter, jitter) * dt
		var center := pos + heading() * distance
		return seek(center + Vector2(cos(wander_theta), sin(wander_theta)) * radius)

	## Steers back inside bounds when closer than margin to an edge.
	func contain(bounds: Rect2, margin: float) -> Vector2:
		var desired := vel
		var outside := false
		if pos.x < bounds.position.x + margin:
			desired.x = max_speed
			outside = true
		elif pos.x > bounds.end.x - margin:
			desired.x = -max_speed
			outside = true
		if pos.y < bounds.position.y + margin:
			desired.y = max_speed
			outside = true
		elif pos.y > bounds.end.y - margin:
			desired.y = -max_speed
			outside = true
		if not outside:
			return Vector2.ZERO
		return (desired.normalized() * max_speed - vel).limit_length(max_force * 1.5)


## A particle with height z, so splashes and spray rise and fall in the top-down view.
class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var z := 0.0
	var vz := 0.0
	var age := 0.0
	var life := 1.0
	var size := 3.0
	var color := Color.WHITE

	func _init(p: Vector2, v: Vector2, z0: float, vz0: float, lifetime: float, sz: float, c: Color) -> void:
		pos = p
		vel = v
		z = z0
		vz = vz0
		life = lifetime
		size = sz
		color = c

	func update(dt: float, gravity: float, drag: float) -> void:
		vz -= gravity * dt
		vel *= maxf(0.0, 1.0 - drag * dt)
		pos += vel * dt
		z = maxf(0.0, z + vz * dt)
		age += dt

	func dead() -> bool:
		return age >= life


## Verlet rope between two pinned ends. Free points keep their momentum, get pushed by a force,
## and segment constraints pull them back to the rope length (a slack line sags, a tight one is straight).
class Rope:
	var pts := PackedVector2Array()
	var prev := PackedVector2Array()

	func _init(n: int, a: Vector2, b: Vector2) -> void:
		reset(n, a, b)

	func reset(n: int, a: Vector2, b: Vector2) -> void:
		pts.resize(n)
		prev.resize(n)
		for i in n:
			var p := a.lerp(b, float(i) / float(n - 1))
			pts[i] = p
			prev[i] = p

	func step(a: Vector2, b: Vector2, length: float, force: Vector2, dt: float, iterations: int = 6) -> void:
		var n := pts.size()
		var seg := length / float(n - 1)
		for i in range(1, n - 1):
			var cur := pts[i]
			pts[i] = cur + (cur - prev[i]) * 0.96 + force * dt * dt
			prev[i] = cur
		pts[0] = a
		pts[n - 1] = b
		for _k in iterations:
			for i in n - 1:
				var delta := pts[i + 1] - pts[i]
				var d := delta.length()
				if d <= seg or d < 0.0001:
					continue
				var corr := delta * (0.5 * (d - seg) / d)
				if i > 0:
					pts[i] += corr
				if i + 1 < n - 1:
					pts[i + 1] -= corr
			pts[0] = a
			pts[n - 1] = b


## Damped spring (Hooke's law): a = -k (x - rest) - c v. Returns Vector2(new x, new v).
static func spring_step(x: float, v: float, rest: float, k: float, damping: float, dt: float) -> Vector2:
	var a := -k * (x - rest) - damping * v
	v += a * dt
	return Vector2(x + v * dt, v)


## Boids: separation, alignment and cohesion forces for every Vehicle in the group.
static func flock(group: Array, sep_radius: float, view_radius: float, w_sep: float = 1.6, w_ali: float = 1.0, w_coh: float = 0.8) -> void:
	for v in group:
		var sep := Vector2.ZERO
		var ali := Vector2.ZERO
		var coh := Vector2.ZERO
		var n_sep := 0
		var n := 0
		for o in group:
			if o == v:
				continue
			var d: float = v.pos.distance_to(o.pos)
			if d < sep_radius and d > 0.001:
				sep += (v.pos - o.pos).normalized() / d
				n_sep += 1
			if d < view_radius:
				ali += o.vel
				coh += o.pos
				n += 1
		if n_sep > 0:
			v.apply_force(steer_toward(v, sep) * w_sep)
		if n > 0:
			v.apply_force(steer_toward(v, ali / float(n)) * w_ali)
			v.apply_force(v.seek(coh / float(n)) * w_coh)


## Steering force that turns a vehicle toward a direction at full speed.
static func steer_toward(v: Vehicle, direction: Vector2) -> Vector2:
	if direction.length() < 0.0001:
		return Vector2.ZERO
	return (direction.normalized() * v.max_speed - v.vel).limit_length(v.max_force)
