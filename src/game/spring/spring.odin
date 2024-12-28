package spring

Spring :: struct($T: typeid) {
	k1, k2, k3: f32,
	xp, y, yd:  T,
}

make_spring :: proc(f, z, r: f32, x0: $T) -> Spring(T) {
	return Spring(T) {
		k1 = z / (math.π * f),
		k2 = 1 / math.pow(2 * math.π * f, 2),
		k3 = r * z / (2 * math.π * f),
		xp = x0,
		y = x0,
		yd = 0,
	}
}

update_spring_v :: proc(spring: ^Spring($T), x: T, xd: T, dt: f32) -> T {
	if (dt == 0) {
		return x
	}

	spring.y += dt * spring.yd
	spring.yd += dt * (x + spring.k3 * xd - spring.y - spring.k1 * spring.yd) / spring.k2
	return spring.y
}

update_spring :: proc(spring: ^Spring($T), x: T, dt: f32) -> T {
	if (dt == 0) {
		return x
	}

	xd := (x - spring.xp) / dt
	spring.xp = x
	return update_spring_v(spring, x, xd)
}
