package main_desktop

import "core:log"

import rl "../../raylib"

import "../game"

INIT_WIDTH :: 1280
INIT_HEIGHT :: 720
TITLE :: "THE GOO FACTORY"

main :: proc() {
	rl.InitWindow(INIT_WIDTH, INIT_HEIGHT, TITLE)
	defer rl.CloseWindow()

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color, .Short_File_Path, .Line})
	defer log.destroy_console_logger(context.logger)

	game.init()
	defer game.fini()

	for !rl.WindowShouldClose() {
		game.frame()
	}
}

