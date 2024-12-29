package game

import rl "../../raylib"

import "core:log"

GameContext :: struct {
    pos: rl.Vector2,
}

ctx: GameContext 

init :: proc() {
    rl.SetTargetFPS(144)
    ctx.pos = {100, 100}

    log.info("Yoo We can do this as well")
    log.warnf("PI: {}", 3.141)

    b, ok := rl.LoadFileDataString("assets/test_file_loading.txt")
    assert(ok, "Failed to load file")
    defer delete(b)

    log.infof("Content: %s", b)
}

frame :: proc() {
    dt := rl.GetFrameTime()
    SPEED :: 300.0
    if rl.IsKeyDown(.W) do ctx.pos.y -= SPEED * dt
    if rl.IsKeyDown(.S) do ctx.pos.y += SPEED * dt
    if rl.IsKeyDown(.A) do ctx.pos.x -= SPEED * dt
    if rl.IsKeyDown(.D) do ctx.pos.x += SPEED * dt

    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)

    rl.DrawText("Hello From Raylib", 100, 100, 60, rl.WHITE)

    rl.DrawRectangleV(ctx.pos, {100, 100}, rl.PURPLE)
    rl.EndDrawing()
}

fini :: proc() {

}