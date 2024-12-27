package game

import rl "../../raylib"

import "core:fmt"
import "core:math"
import "core:strings"
import "particles"

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
	PipeLaying,
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

pipe_reset_len: Maybe(int) = nil
new_unit := Unit {
	pos  = {-100, -100},
	size = {GRID_SIZE * 2, GRID_SIZE * 2},
}
handle_event :: proc(event: Event, dt: f32) -> State {
	if event.transition == .Update && dt > 0 && rl.IsKeyPressed(.TAB) {
		ctx.view_mode = ViewMode((int(ctx.view_mode) + 1) % len(ViewMode))
		return .Idle
	}

	pos := rl.GetMousePosition()

	switch event {
	case Event{.Update, .Idle}:
		if rl.IsMouseButtonPressed(.LEFT) {
			switch ctx.view_mode {
			case .Above:
				return .PlaceBuilding
			case .Below:
				return .PipeLaying
			}
		}
	case Event{.Update, .PlaceBuilding}:
		assert(ctx.view_mode == .Above)
		new_unit.pos = snap(rl.GetMousePosition())
		if rl.IsMouseButtonPressed(.LEFT) && dt > 0 {
			append(&ctx.units, new_unit)
		}
		if rl.IsMouseButtonPressed(.RIGHT) {
			return .Idle
		}
	case Event{.Enter, .PipeLaying}:
		pipe_reset_len = len(ctx.pipes)
		append(&ctx.pipes, snap(pos))
		append(&ctx.pipes, pos)
	case Event{.Update, .PipeLaying}:
		assert(ctx.view_mode == .Below)
		ctx.pipes[len(ctx.pipes) - 1] = snap(pos)
		if rl.IsMouseButtonPressed(.LEFT) {
			append(&ctx.pipes, snap(pos))
		}

		if rl.IsMouseButtonPressed(.RIGHT) {
			// keep the pipe
			pipe_reset_len = nil
			ctx.pipes[len(ctx.pipes) - 1] = PIPE_END
			return .Idle
		}
	case Event{.Exit, .PipeLaying}:
		if pipe_reset_len, ok := pipe_reset_len.?; ok {
			resize(&ctx.pipes, pipe_reset_len)
		}
	}

	return .Undefined
}

ctx: GameContext

GRID_SIZE :: 64
BACKGROUND_COLOR :: rl.Color{196, 168, 110, 255}

Unit :: struct {
	pos:  rl.Vector2,
	size: rl.Vector2,
}

ViewMode :: enum {
	Above,
	Below,
}

PIPE_END :: rl.Vector2{}
GameContext :: struct {
	units:     [dynamic]Unit,
	pipes:     [dynamic]rl.Vector2,
	view_mode: ViewMode,
	ui_state:  State,
}


grid_target: rl.RenderTexture2D
grid_shader: rl.Shader

init :: proc() {
	rl.SetTargetFPS(144)

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

	ctx.ui_state = .Idle
}

snap :: proc(pos: rl.Vector2) -> rl.Vector2 {
	return rl.Vector2{math.floor(pos.x / GRID_SIZE) * GRID_SIZE, math.floor(pos.y / GRID_SIZE) * GRID_SIZE}
}

camera := rl.Camera2D {
	offset = {0, 0},
	target = {0, 0},
	zoom   = 1,
}

render_grid :: proc(mouse_pos: rl.Vector2, color: rl.Color) {
	height := rl.GetRenderHeight()
	width := rl.GetRenderWidth()

	loc := rl.GetShaderLocation(grid_shader, "pos")
	pos := rl.Vector2{mouse_pos.x, f32(height) - mouse_pos.y}
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

	dt := rl.GetFrameTime()

	update_state(&ctx.ui_state, dt)
	particles.update_systems(dt)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	{
		rl.BeginMode2D(camera)
		defer rl.EndMode2D()

		switch ctx.view_mode {
		case .Above:
			rl.ClearBackground(BACKGROUND_COLOR)
			{
				if ctx.ui_state == .PlaceBuilding {
					render_grid(rl.GetMousePosition(), rl.RED)

					rl.DrawRectangleRec(
						{new_unit.pos.x, new_unit.pos.y, new_unit.size.x, new_unit.size.y},
						rl.Fade(rl.GRAY, 0.5),
					)
				}

				for unit in ctx.units {
					rl.DrawRectangleRec({unit.pos.x, unit.pos.y, unit.size.x, unit.size.y}, rl.GRAY)
				}

				particles.render_particles()
			}
		case .Below:
			rl.ClearBackground(rl.BLACK)
			{
				if ctx.ui_state == .PipeLaying {
					render_grid(rl.GetMousePosition(), rl.GRAY)
				}

				for unit in ctx.units {
					rl.DrawRectangleRec({unit.pos.x, unit.pos.y, unit.size.x, unit.size.y}, rl.WHITE)
				}

				if len(ctx.pipes) > 1 {
					for i in 1 ..< len(ctx.pipes) {
						if ctx.pipes[i] == PIPE_END || ctx.pipes[i - 1] == PIPE_END {
							continue
						}
						rl.DrawLineEx(ctx.pipes[i - 1], ctx.pipes[i], 2, rl.WHITE)
					}
				}

				particles.render_particles()
			}
		}
	}
	rl.DrawText(fmt.ctprint(ctx.view_mode), 10, 10, 20, rl.WHITE)
}

fini :: proc() {

}
