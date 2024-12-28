package game

import rl "../../raylib"

import "core:container/intrusive/list"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:strings"
import "particles"

vec2 :: rl.Vector2
Rect :: rl.Rectangle

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

new_unit := Unit {
	rect = {-100, -100, GRID_SIZE * 2, GRID_SIZE * 2},
}

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
	append(&pipe_graph[from], PipeConnection{from = from, to = to, pipe = pipe})
	append(&pipe_graph[to], PipeConnection{from = to, to = from, pipe = pipe})
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

mouse_pressed :: proc(button: rl.MouseButton, dt: f32) -> bool {
	// hack to prevent double processing by checking that we're not in the same frame
	return rl.IsMouseButtonPressed(button) && dt > 0 && !ignore_mouse
}

key_pressed :: proc(button: rl.KeyboardKey, dt: f32) -> bool {
	return rl.IsKeyPressed(button) && dt > 0
}

handle_event :: proc(event: Event, dt: f32) -> State {
	if event.transition == .Update && key_pressed(.TAB, dt) {
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
	case Event{.Update, .PlaceBuilding}:
		assert(ctx.view_mode == .Above)
		new_unit.rect.x = snap_pos.x
		new_unit.rect.y = snap_pos.y
		valid_placement = true
		for unit in ctx.units {
			valid_placement &= !rl.CheckCollisionRecs(new_unit.rect, unit.rect)
		}

		if valid_placement && mouse_pressed(.LEFT, dt) {
			append(&ctx.units, new_unit)
			particles.create_system(
				&new_unit.rect,
				origin_distribution = particles.rect,
				color = rl.Color{163, 106, 31, 100},
				particle_lifetime = 0.6,
			)
		}
		if mouse_pressed(.RIGHT, dt) {
			return .Idle
		}
	case Event{.Enter, .PlacePiping}:
		snap_result, ok := find_closest_snap_point(pos).?
		if !ok {
			// cancel
			return .Idle
		}
		start_unit = snap_result.unit_id
		new_pipe = new(Pipe)
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
			if pipe == new_pipe {
				continue
			}

			for i in 1 ..< len(pipe.parts) {
				valid_placement &= !rl.CheckCollisionLines(
					pipe.parts[i],
					pipe.parts[i - 1],
					new_point,
					prev_point,
					&invalid_point,
				)
			}
		}

		for unit, i in ctx.units {
			if i == start_unit.? && len(new_pipe.parts) <= 2 {
				continue
			}
			edges := rect_edges(unit.rect)
			for j := 0; j < len(edges); j += 2 {
				valid_placement &= !rl.CheckCollisionLines(
					edges[j],
					edges[j + 1],
					new_point,
					prev_point,
					&invalid_point,
				)
			}
		}

		if new_point == prev_point {
			valid_placement = false
			invalid_point = new_point
		}

		end_unit = nil
		if s, ok := find_closest_snap_point(new_point).?; ok {
			if s.unit_id != start_unit {
				// snap to end point
				valid_placement = true
				new_point_ptr^ = s.snap_point
				end_unit = s.unit_id
			} else {
				valid_placement = false
				invalid_point = s.snap_point
			}
		}

		if mouse_pressed(.LEFT, dt) && valid_placement {
			if _, ok := end_unit.?; ok {
				return .Idle
			} else {
				append(&new_pipe.parts, snap(pos))
			}
		}

		if mouse_pressed(.RIGHT, dt) || key_pressed(.ESCAPE, dt) {
			return .Idle
		}

	//if rl.IsMouseButtonPressed(.RIGHT) {
	//	// keep the pipe
	//	pipe_reset_len = nil
	//	ctx.pipes[len(ctx.pipes) - 1] = PIPE_END
	//	return .Idle
	//}
	case Event{.Exit, .PlacePiping}:
		if _, ok := end_unit.?; !ok {
			list.pop_back(&ctx.pipes)
		} else {
			connect_units(start_unit.? or_else panic("unreachable"), end_unit.? or_else panic("unreachable"), new_pipe)
		}
	}

	return .Undefined
}

ctx: GameContext

GRID_SIZE :: 64
BACKGROUND_COLOR :: rl.Color{196, 168, 110, 255}

UnitType :: enum {
	WaterExtractor,
	ElectrictyExtractor,
}

Unit :: struct {
	type:        UnitType,
	rect:        Rect,
	snap_points: small_array.Small_Array(8, vec2),
}

ViewMode :: enum {
	Above,
	Below,
}

Pipe :: struct {
	parts:      [dynamic]vec2,
	using node: list.Node,
}

PIPE_END :: vec2{}
GameContext :: struct {
	units:     [dynamic]Unit,
	// list of Pipe
	pipes:     list.List,
	view_mode: ViewMode,
	ui_state:  State,
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

	small_array.append_elems(
		&new_unit.snap_points,
		vec2{0, GRID_SIZE},
		vec2{new_unit.rect.width, GRID_SIZE},
		vec2{GRID_SIZE, 0},
		vec2{GRID_SIZE, new_unit.rect.height},
	)

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
					color := rl.GRAY
					switch unit.type {
					case .ElectrictyExtractor:
						color = rl.GOLD
					case .WaterExtractor:
						color = rl.DARKBLUE
					}
					rl.DrawRectangleRec(unit.rect, color)
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

				for unit in ctx.units {
					rl.DrawRectangleRec(unit.rect, rl.WHITE)
				}

				iter := list.iterator_head(ctx.pipes, Pipe, "node")
				for pipe in list.iterate_next(&iter) {
					for i in 1 ..< len(pipe.parts) {
						color := rl.RED if !valid_placement && pipe == new_pipe else rl.WHITE
						if i == 1 {
							rl.DrawCircleV(pipe.parts[0], 5, color)
						}
						if pipe.parts[i] == PIPE_END || pipe.parts[i - 1] == PIPE_END {
							continue
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
	rl.DrawText(fmt.ctprint(ctx.view_mode), 10, 10, 20, rl.WHITE)

	if ctx.view_mode == .Above {
		mouse_pos := rl.GetMousePosition()
		if id, ok := find_unit(rl.GetScreenToWorld2D(mouse_pos, camera)).?; ok {
			unit := ctx.units[id]
			// print stats
			rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprint(unit.type), mouse_pos + vec2{40, 0}, 10, 1.0, rl.WHITE)
		}

		layout := Rect{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

		row := new_row(&layout, -40)
		ignore_mouse = rl.CheckCollisionPointRec(mouse_pos, row)
		rl.DrawRectangleRec(row, rl.DARKGRAY)
		if rl.GuiButton(new_col(&row, 120), "WaterExtractor") {
			new_unit.type = .WaterExtractor
		}
		if rl.GuiButton(new_col(&row, 120), "ElectrictyExtractor") {
			new_unit.type = .ElectrictyExtractor
		}
	}

	dt := rl.GetFrameTime()


	update_state(&ctx.ui_state, dt)
	particles.update_systems(dt)

}

fini :: proc() {

}
