package game

import rl "../../raylib"

import "core:container/intrusive/list"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import "particles"

vec2 :: rl.Vector2
Rect :: rl.Rectangle

Rocks :: [][]vec2 {
	{
		{565.02, 208.144},
		{566.355, 284.913},
		{506.943, 369.693},
		{486.248, 474.499},
		{427.504, 380.374},
		{482.911, 313.619},
		{492.256, 157.41},
	},
	{{148.198, 121.495}, {96.796, 198.264}, {62.083, 151.535}, {81.442, 42.056}},
	{{854.491, 282.402}, {1089.964, 340.687}, {889.463, 345.35}, {824.183, 389.647}},
}

//GooPools :: [][]vec2 {
//	{{1081.238, 477.464}, {1118.541, 547.406}, {1256.095, 505.441}, {1214.129, 409.853}, {1111.547, 398.196}},
//}

GooPool :: struct {
	pos:  vec2,
	size: f32,
}

goo_pools: small_array.Small_Array(5, GooPool)
next_spawn: f32 = 0
GOO_POOL_SCALE_RATE :: 5

Transition :: enum {
	Enter,
	Update,
	Exit,
}

Event :: struct {
	transition: Transition,
	state:      State,
}

State :: enum {
	Undefined = 0,
	Idle,
	PlaceBuilding,
	PlacePiping,
	DeletePiping,
}

set_state_inner :: proc(state: ^State, new_state: State) {
	exit_result := handle_event(Event{.Exit, state^}, 0)
	assert(exit_result == .Undefined)

	state^ = new_state

	enter_result := handle_event(Event{.Enter, state^}, 0)
	if enter_result != .Undefined {
		set_state_inner(state, enter_result)
	}
}

update_state :: proc(state: ^State, dt: f32) {
	max_transitions :: 8

	i := 0
	for new_state := handle_event(Event{.Update, state^}, dt);
	    new_state != .Undefined && new_state != state^ && i < max_transitions; {
		set_state_inner(state, new_state)
		i += 1
		new_state = handle_event(Event{.Update, state^}, 0)
	}
	assert(i != max_transitions)
}

create_unit :: proc(type: UnitType) -> Unit {
	u := Unit {
		type = type,
		rect = Rect{0, 0, GRID_SIZE * 2, GRID_SIZE * 2},
	}

	small_array.append_elems(
		&u.snap_points,
		vec2{0, GRID_SIZE},
		vec2{u.rect.width, GRID_SIZE},
		vec2{GRID_SIZE, 0},
		vec2{GRID_SIZE, u.rect.height},
	)

	switch type {
	case .GooExtractor:
		u.max_goo_gen = 10
	case .GooTank:
		u.goo_max = 100
	case .Shipping:
		u.goo_max = 10
		u.startup_time = 10
		u.goo_use = 3
	}
	return u
}

new_unit: Unit
valid_placement := true
invalid_point := vec2{}
start_unit: Maybe(int) = nil
end_unit: Maybe(int) = nil

rect_edges :: proc(r: Rect) -> [8]vec2 {
	return [8]vec2 {
		// top
		vec2{r.x, r.y},
		vec2{r.x + r.width, r.y},
		// bottom
		vec2{r.x, r.y + r.height},
		vec2{r.x + r.width, r.y + r.height},
		// left
		vec2{r.x, r.y},
		vec2{r.x, r.y + r.height},
		// right
		vec2{r.x + r.width, r.y},
		vec2{r.x + r.width, r.y + r.height},
	}
}


PipeConnection :: struct {
	from: int,
	to:   int,
	pipe: ^Pipe,
}
pipe_graph := make(map[int][dynamic]PipeConnection)
new_pipe: ^Pipe

connect_units :: proc(from, to: int, pipe: ^Pipe) {
	if !(from in pipe_graph) {
		pipe_graph[from] = make([dynamic]PipeConnection)
	}
	if !(to in pipe_graph) {
		pipe_graph[to] = make([dynamic]PipeConnection)
	}
	append(&pipe_graph[from], PipeConnection{from = from, to = to, pipe = pipe})
	append(&pipe_graph[to], PipeConnection{from = to, to = from, pipe = pipe})
}

disconnect_units :: proc(pipe: ^Pipe) {
	remove1, remove2 := false, false
	for _, connections in pipe_graph {
		for connection, i in connections {
			if connection.pipe == pipe {
				for connection2, j in pipe_graph[connection.to] {
					if connection2.pipe == pipe {
						unordered_remove(&pipe_graph[connection.to], j)
						remove2 = true
						break
					}
				}
				unordered_remove(&pipe_graph[connection.from], i)
				remove1 = true
				break
			}
		}
	}
	assert(remove1 && remove2)
}

find_unit :: proc(pos: vec2) -> Maybe(int) {
	for unit, i in ctx.units {
		if rl.CheckCollisionPointRec(pos, unit.rect) {
			return i
		}
	}
	return nil
}

ignore_mouse := false
enter_delete_pipe := false
enter_switch_view := false

mouse_pressed :: proc(button: rl.MouseButton, dt: f32) -> bool {
	// hack to prevent double processing by checking that we're not in the same frame
	return rl.IsMouseButtonPressed(button) && dt > 0 && !ignore_mouse
}

key_pressed :: proc(button: rl.KeyboardKey, dt: f32) -> bool {
	return rl.IsKeyPressed(button) && dt > 0
}

pad :: proc(rect: Rect, pad: f32) -> Rect {
	return {rect.x - pad, rect.y - pad, rect.width + pad * 2, rect.height + pad * 2}
}

handle_event :: proc(event: Event, dt: f32) -> State {
	if event.transition == .Update && enter_switch_view {
		enter_switch_view = false
		ctx.view_mode = ViewMode((int(ctx.view_mode) + 1) % len(ViewMode))
		return .Idle
	}

	pos := rl.GetMousePosition()
	snap_pos := snap(pos)

	switch event {
	case Event{.Enter, .Idle}:
		// hide invalid marking placements
		valid_placement = true

	case Event{.Update, .Idle}:
		if mouse_pressed(.LEFT, dt) {
			switch ctx.view_mode {
			case .Above:
				return .PlaceBuilding
			case .Below:
				return .PlacePiping
			}
		}

		if (enter_delete_pipe) {
			enter_delete_pipe = false
			return .DeletePiping
		}
	case Event{.Update, .PlaceBuilding}:
		assert(ctx.view_mode == .Above)
		new_unit.rect.x = snap_pos.x
		new_unit.rect.y = snap_pos.y
		valid_placement = true
		for unit in ctx.units {
			valid_placement &= !rl.CheckCollisionRecs(new_unit.rect, pad(unit.rect, GRID_SIZE))
		}

		if valid_placement && mouse_pressed(.LEFT, dt) {
			append(&ctx.units, new_unit)
			particles.create_system(
				&new_unit.rect,
				origin_distribution = particles.rect,
				color = rl.Color{163, 106, 31, 100},
				particle_lifetime = 0.6,
			)

			if new_unit.type in visible_underground {
				// delete any underlying pipes
				iter := list.iterator_head(ctx.pipes, Pipe, "node")
				for pipe in list.iterate_next(&iter) {
					delete := false
					for i in 1 ..< len(pipe.parts) {
						edges := rect_edges(new_unit.rect)
						for j := 0; j < len(edges); j += 2 {
							if rl.CheckCollisionLines(edges[j], edges[j + 1], pipe.parts[i], pipe.parts[i - 1], nil) {
								delete = true
								break
							}
						}
					}

					if (delete) {
						particles.create_system(
							&pipe.parts[0],
							origin_distribution = particles.identity,
							color = rl.GREEN,
							particle_lifetime = 0.6,
						)
						list.remove(&ctx.pipes, pipe)
						disconnect_units(pipe)
						free(pipe)
					}
				}
			}

		}
		if mouse_pressed(.RIGHT, dt) {
			return .Idle
		}
	case Event{.Enter, .PlacePiping}:
		snap_result, ok := find_closest_snap_point(pos).?
		if !ok {
			new_pipe = nil // ARAKLHRA
			// cancel
			return .Idle
		}
		start_unit = snap_result.unit_id
		new_pipe = new(Pipe)
		fmt.printf("new pipe %p\n", new_pipe)
		list.push_back(&ctx.pipes, new_pipe)

		append(&new_pipe.parts, snap_result.snap_point)
		append(&new_pipe.parts, pos)
	case Event{.Update, .PlacePiping}:
		valid_placement = true
		new_pipe.parts[len(new_pipe.parts) - 1] = snap(pos)

		new_point_ptr := &new_pipe.parts[len(new_pipe.parts) - 1]
		new_point := new_point_ptr^
		prev_point := new_pipe.parts[len(new_pipe.parts) - 2]

		iter := list.iterator_head(ctx.pipes, Pipe, "node")
		for pipe in list.iterate_next(&iter) {
			for i in 1 ..< len(pipe.parts) {
				if pipe == new_pipe && i > len(pipe.parts) - 3 {
					continue
				}

				pipe_collision := rl.CheckCollisionLines(
					pipe.parts[i],
					pipe.parts[i - 1],
					new_point,
					prev_point,
					&invalid_point,
				)
				if pipe_collision && invalid_point != snap_pos {
					valid_placement = false
					break
				}
			}
		}

		for unit, i in ctx.units {
			if i == start_unit.? && len(new_pipe.parts) <= 2 {
				continue
			}
			edges := rect_edges(unit.rect)
			for j := 0; j < len(edges); j += 2 {
				if unit.type in visible_underground {
					edge_collision := rl.CheckCollisionLines(
						edges[j],
						edges[j + 1],
						new_point,
						prev_point,
						&invalid_point,
					)

					if edge_collision && invalid_point != snap_pos {
						valid_placement = false
						break
					}
				}
			}
		}

		for rock in Rocks {
			for i in 1 ..< len(rock) {
				valid_placement &= !rl.CheckCollisionLines(rock[i], rock[i - 1], new_point, prev_point, &invalid_point)
			}
		}

		end_unit = nil
		if s, ok := find_closest_snap_point(new_point).?; ok {
			if s.unit_id != start_unit {
				// snap to end point
				valid_placement &= true
				new_point_ptr^ = s.snap_point
				end_unit = s.unit_id
			} else {
				valid_placement = false
				invalid_point = s.snap_point
			}
		}


		if mouse_pressed(.LEFT, dt) && valid_placement && new_point != prev_point {
			new_pipe.length += rl.Vector2Length(new_point - prev_point) / GRID_SIZE
			if _, ok := end_unit.?; ok {
				return .Idle
			} else {
				append(&new_pipe.parts, snap(pos))
			}
		}

		if mouse_pressed(.RIGHT, dt) || key_pressed(.ESCAPE, dt) {
			end_unit = nil
			return .Idle
		}
	case Event{.Exit, .PlacePiping}:
		if new_pipe != nil {
			if _, ok := end_unit.?; !ok {
				p := list.pop_back(&ctx.pipes)
				assert(p == &new_pipe.node)
				fmt.printf("free %p\n", new_pipe)
				free(new_pipe)

			} else {
				connect_units(
					start_unit.? or_else panic("unreachable"),
					end_unit.? or_else panic("unreachable"),
					new_pipe,
				)
			}
		}

	case Event{.Enter, .DeletePiping}:
		rl.SetMouseCursor(.CROSSHAIR)
	case Event{.Update, .DeletePiping}:
		if mouse_pressed(.LEFT, dt) {
			iter := list.iterator_head(ctx.pipes, Pipe, "node")
			for pipe in list.iterate_next(&iter) {
				for i in 1 ..< len(pipe.parts) {
					mouse_pos_world := rl.GetScreenToWorld2D(pos, camera)
					if rl.CheckCollisionPointLine(mouse_pos_world, pipe.parts[i], pipe.parts[i - 1], 20) {
						list.remove(&ctx.pipes, pipe)
						disconnect_units(pipe)
						free(pipe)
						break
					}
				}
			}
		}

		if mouse_pressed(.RIGHT, dt) || key_pressed(.ESCAPE, dt) {
			return .Idle
		}
	case Event{.Exit, .DeletePiping}:
		rl.SetMouseCursor(.DEFAULT)

	}

	return .Undefined
}

ctx: GameContext

GRID_SIZE :: 64
BACKGROUND_COLOR :: rl.Color{196, 168, 110, 255}

UnitType :: enum {
	GooExtractor,
	GooTank,
	Shipping,
}

visible_underground: bit_set[UnitType] = {.GooTank, .GooExtractor}

Unit :: struct {
	type:         UnitType,
	rect:         Rect,
	snap_points:  small_array.Small_Array(8, vec2),
	goo_cur:      f32,
	goo_gen:      f32,
	goo_use:      f32,
	max_goo_gen:  f32,
	goo_max:      f32,
	startup_time: f32,
	rampup:       f32,
}

ViewMode :: enum {
	Above,
	Below,
}

Pipe :: struct {
	parts:      [dynamic]vec2,
	length:     f32,
	using node: list.Node,
}

GameContext :: struct {
	units:           [dynamic]Unit,
	// list of Pipe
	pipes:           list.List,
	view_mode:       ViewMode,
	ui_state:        State,
	barrels_shipped: f32,
}

rect_pos :: proc(r: Rect) -> vec2 {
	return {r.x, r.y}
}

SnapResult :: struct {
	snap_point: vec2,
	unit_id:    int,
}

find_closest_snap_point :: proc(pos: vec2, max_dist: f32 = SNAP_RANGE) -> Maybe(SnapResult) {
	closest_dist := math.INF_F32
	closest_i := 0
	closest_point := vec2{}

	for &unit, i in ctx.units {
		for snap_point in small_array.slice(&unit.snap_points) {
			p := rect_pos(unit.rect) + snap_point
			dist := rl.Vector2Length(pos - p)
			if dist < closest_dist && dist < max_dist {
				closest_dist = dist
				closest_i = i
				closest_point = p
			}
		}
	}

	if math.is_inf(closest_dist) {
		return nil
	} else {
		return SnapResult{closest_point, closest_i}
	}
}

SNAP_RANGE :: GRID_SIZE

grid_target: rl.RenderTexture2D
grid_shader: rl.Shader

shipping_unit: ^Unit

init :: proc() {
	rl.SetTargetFPS(144)

	// FIXME: for final release, set this
	//rl.SetExitKey(.F4)

	grid_target = rl.LoadRenderTexture(rl.GetRenderWidth(), rl.GetRenderHeight())

	shader_code := `#version 330

	// Input vertex attributes (from vertex shader)
	in vec2 fragTexCoord;
	in vec4 fragColor;

	// Input uniform values
	uniform sampler2D texture0;
	uniform vec4 colDiffuse;

	// Output fragment color
	out vec4 finalColor;

	// NOTE: Render size values should be passed from code
	const float renderWidth = %%WIDTH%%;
	const float renderHeight = %%HEIGHT%%;

	float radius = renderHeight / 5;

	uniform vec2 pos = vec2(200.0, 200.0);

	void main()
	{
		vec2 texSize = vec2(renderWidth, renderHeight);

		float dist = length(fragTexCoord*texSize - pos);

		if (dist < radius)
		{
			vec4 color = texture(texture0, fragTexCoord)*colDiffuse*fragColor;
			finalColor = vec4(color.rgb, 1 - dist/radius);
		} else {
			finalColor = vec4(0, 0, 0, 0);
		}
	}
	`

	shipping := create_unit(.Shipping)
	shipping.rect = Rect{GRID_SIZE, GRID_SIZE * 5, 2 * GRID_SIZE, GRID_SIZE}
	small_array.resize(&shipping.snap_points, 0)
	small_array.append_elems(&shipping.snap_points, vec2{GRID_SIZE, 0})
	append(&ctx.units, shipping)
	shipping_unit = &ctx.units[0]


	shader_code, _ = strings.replace(
		shader_code,
		"%%WIDTH%%",
		fmt.tprint(rl.GetRenderWidth()),
		1,
		allocator = context.temp_allocator,
	)
	shader_code, _ = strings.replace(
		shader_code,
		"%%HEIGHT%%",
		fmt.tprint(rl.GetRenderHeight()),
		1,
		allocator = context.temp_allocator,
	)

	grid_shader = rl.LoadShaderFromMemory(nil, fmt.ctprint(shader_code))

	new_unit = create_unit(.GooExtractor)

	ctx.ui_state = .Idle
}

snap :: proc(pos: vec2) -> vec2 {
	return vec2{math.floor(pos.x / GRID_SIZE) * GRID_SIZE, math.floor(pos.y / GRID_SIZE) * GRID_SIZE}
}

camera := rl.Camera2D {
	offset = {0, 0},
	target = {0, 0},
	zoom   = 1,
}

new_row :: proc(r: ^Rect, row_height: f32) -> Rect {
	assert(row_height != 0)

	height := row_height

	if height > 0 {
		defer r.y += height
		return Rect{r.x, r.y, r.width, height}
	} else {
		height = -height
		r.height -= height
		return Rect{r.x, r.height, r.width, height}
	}
}

new_col :: proc(r: ^Rect, col_width: f32) -> Rect {
	assert(col_width != 0)

	width := col_width

	if width > 0 {
		defer r.x += width
		return Rect{r.x, r.y, width, r.height}
	} else {
		width = -width
		defer r.width -= width
		return Rect{r.width - width, r.y, width, r.height}
	}
}


render_grid :: proc(mouse_pos: vec2, color: rl.Color) {
	height := rl.GetRenderHeight()
	width := rl.GetRenderWidth()

	loc := rl.GetShaderLocation(grid_shader, "pos")
	pos := vec2{mouse_pos.x, f32(height) - mouse_pos.y}
	rl.SetShaderValue(grid_shader, loc, &pos, rl.ShaderUniformDataType.VEC2)

	rl.BeginTextureMode(grid_target)
	rl.ClearBackground(rl.BLANK)
	{
		for x: i32 = 0; x < width; x += GRID_SIZE {
			rl.DrawLine(x, 0, x, height, rl.Fade(color, 0.5))
		}

		for y: i32 = 0; y < height; y += GRID_SIZE {
			rl.DrawLine(0, y, width, y, rl.Fade(color, 0.5))
		}
	}
	rl.EndTextureMode()

	rl.BeginShaderMode(grid_shader)
	rl.BeginBlendMode(rl.BlendMode.ADDITIVE)
	rl.DrawTextureRec(
		grid_target.texture,
		{0, 0, f32(grid_target.texture.width), -f32(grid_target.texture.height)},
		{0, 0},
		rl.WHITE,
	)
	rl.EndShaderMode()
	rl.EndBlendMode()
}

unit_color :: proc(type: UnitType) -> rl.Color {
	color := rl.GRAY
	switch type {
	case .GooTank:
		color = rl.GRAY
	case .GooExtractor:
		color = rl.DARKGREEN
	case .Shipping:
		color = rl.BROWN
	}
	return color
}

frame :: proc() {
	// clear temp allocator each frame
	defer free_all(context.temp_allocator)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	{
		rl.BeginMode2D(camera)
		defer rl.EndMode2D()

		switch ctx.view_mode {
		case .Above:
			rl.ClearBackground(BACKGROUND_COLOR)
			{
				for unit in ctx.units {
					rl.DrawRectangleRec(unit.rect, unit_color(unit.type))
				}

				if ctx.ui_state == .PlaceBuilding {
					render_grid(rl.GetMousePosition(), rl.RED)

					rl.DrawRectangleRec(new_unit.rect, rl.Fade(rl.GRAY if valid_placement else rl.RED, 0.5))
				}

				particles.render_particles()
			}
		case .Below:
			rl.ClearBackground(rl.BLACK)
			{
				if ctx.ui_state == .PlacePiping {
					render_grid(rl.GetMousePosition(), rl.GRAY)
				}

				{
					for rock in Rocks {
						for i in 1 ..< len(rock) {
							rl.DrawLineEx(rock[i - 1], rock[i], 3, rl.GRAY)
						}
						rl.DrawLineEx(rock[0], rock[len(rock) - 1], 3, rl.GRAY)
					}
				}

				{
					for pool in small_array.slice(&goo_pools) {
						rl.DrawCircleLinesV(pool.pos, pool.size, rl.GREEN)
					}
				}

				for unit in ctx.units {
					if unit.type in visible_underground {
						rl.DrawRectangleLinesEx(unit.rect, 2, unit_color(unit.type))
					}
				}


				iter := list.iterator_head(ctx.pipes, Pipe, "node")
				for pipe in list.iterate_next(&iter) {
					for i in 1 ..< len(pipe.parts) {
						color := rl.RED if !valid_placement && pipe == new_pipe else rl.WHITE
						if i == 1 {
							rl.DrawCircleV(pipe.parts[0], 5, color)
						}
						rl.DrawLineEx(pipe.parts[i - 1], pipe.parts[i], 10, color)
						rl.DrawCircleV(pipe.parts[i], 5, color)
					}
				}

				// draw x indicator for intersection
				if !valid_placement {
					rl.DrawLineEx(invalid_point + vec2{-10, -10}, invalid_point + vec2{10, 10}, 2, rl.RED)
					rl.DrawLineEx(invalid_point + vec2{-10, 10}, invalid_point + vec2{10, -10}, 2, rl.RED)
				}


				for &unit in ctx.units {
					for snap_point in small_array.slice(&unit.snap_points) {
						p := snap_point + vec2{unit.rect.x, unit.rect.y}
						rl.DrawCircleLinesV(p, 5, rl.GREEN)
					}
				}

				if result, ok := find_closest_snap_point(rl.GetMousePosition()).?; ok {
					rl.DrawCircleV(result.snap_point, 5, rl.LIME)
				}

				particles.render_particles()
			}
		}
	}
	rl.DrawFPS(500, 10)
	rl.DrawText(fmt.ctprint("Barrels of Goo Shipped:", int(ctx.barrels_shipped)), 10, 10, 20, rl.GREEN)
	rl.DrawText(fmt.ctprint(ctx.view_mode), 10, 30, 20, rl.WHITE)

	mouse_pos := rl.GetMousePosition()

	// draw button panel
	layout := Rect{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	panel_row := new_row(&layout, -40)
	ignore_mouse = rl.CheckCollisionPointRec(mouse_pos, panel_row)
	rl.DrawRectangleRec(panel_row, rl.DARKGRAY)

	enter_switch_view = rl.GuiButton(new_col(&panel_row, 180), "Switch View (tab)") || rl.IsKeyPressed(.TAB)
	switch ctx.view_mode 
	{
	case .Above:
		if id, ok := find_unit(rl.GetScreenToWorld2D(mouse_pos, camera)).?; ok {
			rl.DrawRectangleRec(Rect{mouse_pos.x + 35, mouse_pos.y - 5, 140, 100}, rl.BLACK)
			unit := ctx.units[id]
			y: f32 = 0
			// print stats
			rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprint(unit.type), mouse_pos + vec2{40, y}, 10, 1.0, rl.WHITE)
			y += 20
			desc := cstring("")
			if unit.goo_max > 0 {
				desc = fmt.ctprintf("Goo Store: %0.1f/%0.1f", unit.goo_cur, unit.goo_max)
				rl.DrawTextEx(rl.GetFontDefault(), desc, mouse_pos + vec2{40, y}, 10, 1.0, rl.WHITE)
				y += 20
			}
			if unit.rampup < unit.startup_time {
				if unit.rampup == 0 {
					rl.DrawTextEx(rl.GetFontDefault(), "INACTIVE", mouse_pos + vec2{40, y}, 10, 1.0, rl.LIGHTGRAY)
				} else {
					rl.DrawTextEx(
						rl.GetFontDefault(),
						fmt.ctprintf("STARTING: %0.1f%%", unit.rampup * 100 / unit.startup_time),
						mouse_pos + vec2{40, y},
						10,
						1.0,
						rl.YELLOW,
					)
				}
				y += 20
			} else {
				if unit.goo_gen > 0 {
					desc = fmt.ctprintf("Goo Outflow: %0.1f/s", unit.goo_gen)
					rl.DrawTextEx(rl.GetFontDefault(), desc, mouse_pos + vec2{40, y}, 10, 1.0, rl.WHITE)
					y += 20
				}
				if unit.goo_use > 0 {
					desc = fmt.ctprintf("Goo Usage: %0.1f/s", unit.goo_use)
					rl.DrawTextEx(rl.GetFontDefault(), desc, mouse_pos + vec2{40, y}, 10, 1.0, rl.WHITE)
					y += 20
				}
				rl.DrawTextEx(rl.GetFontDefault(), "ACTIVE", mouse_pos + vec2{40, y}, 10, 1.0, rl.GREEN)
				y += 20
			}
		}

		if rl.GuiButton(new_col(&panel_row, 120), "GooExtractor (1)") || rl.IsKeyPressed(.ONE) {
			new_unit = create_unit(.GooExtractor)
		}
		if rl.GuiButton(new_col(&panel_row, 120), "GooTank (2)") || rl.IsKeyPressed(.TWO) {
			new_unit = create_unit(.GooTank)
		}
	case .Below:
		enter_delete_pipe = rl.GuiButton(new_col(&panel_row, 120), "Delete Pipe (d)") || rl.IsKeyPressed(.D)
	}

	dt := rl.GetFrameTime()

	update_state(&ctx.ui_state, dt)

	for &unit in ctx.units {
		if unit.rampup < unit.startup_time && unit.goo_cur > 0 {
			unit.rampup += dt
		}
		if unit.goo_cur == 0 {
			unit.rampup = 0
		}
		if unit.type == .GooExtractor {
			unit.goo_gen = 0
			active := false
			for i := 0; i < small_array.len(goo_pools); {
				pool := small_array.get_ptr(&goo_pools, i)
				dist := rl.Vector2Length(
					pool.pos - vec2{unit.rect.x, unit.rect.y} + vec2{unit.rect.width, unit.rect.height} / 2,
				)
				if dist < 300 && unit.goo_gen < unit.max_goo_gen {
					unit.goo_gen += min(1, pool.size / GOO_POOL_SCALE_RATE)
					pool.size = clamp(pool.size - GOO_POOL_SCALE_RATE * dt, 0, pool.size)
					active = true
				}

				if pool.size > 0 {
					i += 1
				} else {
					small_array.unordered_remove(&goo_pools, i)
				}
			}
			unit.startup_time = 0 if active else 1
		} else {
			unit.goo_gen = unit.max_goo_gen
		}
		unit.goo_cur = clamp(unit.goo_cur - unit.goo_use * dt, 0, unit.goo_max)
	}

	if shipping_unit.rampup >= shipping_unit.startup_time {
		ctx.barrels_shipped += dt / 10
	}

	{
		processed := make(map[^Pipe]bool, allocator = context.temp_allocator)

		// process pipes
		for _, connections in pipe_graph {
			for connection in connections {
				if connection.pipe in processed {
					continue
				}
				processed[connection.pipe] = true

				{
					from_ptr := &ctx.units[connection.from]
					to_ptr := &ctx.units[connection.to]

					// flow of goo storage
					dP: f32 = 0
					if from_ptr.goo_gen == 0 && to_ptr.goo_gen == 0 {
						dP = (1 * (from_ptr.goo_cur - to_ptr.goo_cur))
					}

					from_dP := (-dP + max(0, to_ptr.goo_gen - from_ptr.goo_gen)) / connection.pipe.length * dt
					to_dP := (dP + max(0, from_ptr.goo_gen - to_ptr.goo_gen)) / connection.pipe.length * dt

					from_ptr.goo_cur = clamp(from_ptr.goo_cur + from_dP, 0, from_ptr.goo_max)
					to_ptr.goo_cur = clamp(to_ptr.goo_cur + to_dP, 0, to_ptr.goo_max)
				}
			}
		}
	}


	spawn_pools: {
		screen_width := f32(rl.GetScreenWidth())
		screen_height := f32(rl.GetScreenHeight())
		t := f32(rl.GetTime())
		if t > next_spawn {
			small_array.append(
				&goo_pools,
				GooPool {
					pos = {rand.float32() * screen_width / 2 + screen_width / 2, rand.float32() * screen_height},
					size = 100,
				},
			)
			next_spawn =
				t + rand.float32_range(f32(small_array.len(goo_pools) * 2), f32(small_array.len(goo_pools) * 4))
		}
	}

	particles.update_systems(dt)
}

fini :: proc() {

}
