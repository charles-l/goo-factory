package particles

import rl "../../../raylib"

import "core:container/intrusive/list"
import "core:container/small_array"
import "core:math"
import "core:math/rand"

Particle :: struct {
	position:   rl.Vector2,
	velocity:   rl.Vector2,
	size:       f32,
	rotation:   f32,
	alive_time: f32,
}

max_particles :: 1000

ParticleSystem :: struct {
	particles:           small_array.Small_Array(max_particles, Particle),
	origin:              rawptr,
	origin_distribution: proc(_: rawptr) -> (rl.Vector2, rl.Vector2),
	gravity:             rl.Vector2,
	wind:                rl.Vector2,
	spawn_per_second:    f32,
	spawn_accumulator:   f32,
	initial_speed:       f32,
	size:                f32,
	size_variation:      f32,
	system_lifetime:     f32,
	particle_lifetime:   f32,
	color:               rl.Color,

	// intrusive list for other particle systems
	node:                list.Node,
}

all_systems: list.List

spawn_particle :: #force_inline proc(system: ^ParticleSystem) {
	position, velocity := system.origin_distribution(system.origin)
	small_array.append(
		&system.particles,
		Particle {
			position = position,
			velocity = system.initial_speed * velocity,
			size = system.size + rand.float32() * system.size_variation,
			rotation = rand.float32() * 360,
		},
	)
}

identity :: proc(p: ^rl.Vector2) -> (rl.Vector2, rl.Vector2) {
	theta := rand.float32() * 2 * math.PI
	r := math.sqrt(rand.float32())
	v := rl.Vector2{r * math.cos(theta), r * math.sin(theta)}
	return p^, v
}

rect :: proc(r: ^rl.Rectangle) -> (rl.Vector2, rl.Vector2) {
	switch rand.uint32() % 4 {
	case 0:
		// top
		p := rl.Vector2{r.x, r.y} + rl.Vector2{r.width, 0} * rand.float32()
		v := rl.Vector2{rand.float32_range(-1, 1), -rand.float32()}
		return p, v
	case 1:
		// bottom
		p := rl.Vector2{r.x, r.y + r.height} + rl.Vector2{r.width, 0} * rand.float32()
		v := rl.Vector2{rand.float32_range(-1, 1), rand.float32()}
		return p, v
	case 2:
		// left
		p := rl.Vector2{r.x, r.y} + rl.Vector2{0, r.height} * rand.float32()
		v := rl.Vector2{-rand.float32(), rand.float32_range(-1, 1)}
		return p, v
	case 3:
		// right
		p := rl.Vector2{r.x + r.width, r.y} + rl.Vector2{0, r.height} * rand.float32()
		v := rl.Vector2{rand.float32(), rand.float32_range(-1, 1)}
		return p, v
	}
	// unreachable
	assert(false)
	return rl.Vector2{}, rl.Vector2{}
}

create_system :: proc(
	origin: ^$T,
	origin_distribution: proc(_: ^T) -> (rl.Vector2, rl.Vector2),
	size: f32 = 4.0,
	size_variation: f32 = 1.0,
	initial_speed: f32 = 100,
	gravity := rl.Vector2{},
	wind := rl.Vector2{0, 0},
	color := rl.WHITE,
	num_particles := max_particles,
	spawn_per_second: f32 = 0.0,
	system_lifetime: f32 = 4.0,
	particle_lifetime: f32 = 1.0,
) {
	system := new(ParticleSystem)
	list.push_back(&all_systems, &system.node)

	system.spawn_per_second = spawn_per_second
	system.spawn_accumulator = 0

	system.origin = rawptr(new_clone(origin^))
	dist_func :: proc(_: rawptr) -> (rl.Vector2, rl.Vector2)
	system.origin_distribution = dist_func(origin_distribution)

	system.size = size
	system.size_variation = size_variation
	system.initial_speed = initial_speed
	system.gravity = gravity
	system.wind = wind
	system.color = color

	system.system_lifetime = system_lifetime
	system.particle_lifetime = particle_lifetime

	if spawn_per_second == 0 {
		for i := 0; i < num_particles; i += 1 {
			_ = i
			spawn_particle(system)
		}
	}
}

update_systems :: proc(dt: f32) {
	iter := list.iterator_head(all_systems, ParticleSystem, "node")
	for system in list.iterate_next(&iter) {
		system.spawn_accumulator += system.spawn_per_second * dt

		{
			i := 0
			for ; i < int(system.spawn_accumulator); i += 1 {
				spawn_particle(system)
			}
			if i > 0 {
				system.spawn_accumulator = max(0, system.spawn_accumulator - f32(i))
			}
		}

		for i := 0; i < small_array.len(system.particles); i += 1 {
			p := small_array.get_ptr(&system.particles, i)
			p.position += (system.wind + p.velocity) * dt
			p.velocity += system.gravity
			p.alive_time += dt
			if p.alive_time > system.particle_lifetime {
				small_array.unordered_remove(&system.particles, i)
			}
		}

		system.system_lifetime -= dt
		if system.system_lifetime < 0 {
			list.remove(&all_systems, &system.node)
			free(system.origin)
			free(system)
		}
	}
}

render_particles :: proc() {
	iter := list.iterator_head(all_systems, ParticleSystem, "node")
	for system in list.iterate_next(&iter) {
		for p in small_array.slice(&system.particles) {
			f := 1 - math.clamp(p.alive_time / system.particle_lifetime, 0, 1)

			rl.DrawRectanglePro(
				rl.Rectangle{p.position.x, p.position.y, p.size * f, p.size * f},
				rl.Vector2{p.size * f / 2, p.size * f / 2},
				p.rotation,
				rl.ColorAlpha(system.color, min(f32(system.color.a) / 255.0, f)),
			)
		}
	}
}
