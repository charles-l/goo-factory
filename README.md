# The Goo Factory

An attempt at making a city-builder in 48hrs for the [2024 Odin Holiday Jam](https://itch.io/jam/odin-holiday-jam/rate/3210986). 

Theme: Overground and Underground

**Rough Timeline**

- *Prejam* 
- Wrote a particle system renderer and implemented an FSM based off [this article](https://blog.littlepolygon.com/posts/fsm/)

- *Jam start*
- Implement above ground/below ground rendering of units
- Add UI to place buildings/pipes
- Add particle effect on building placement
- Add "spotlight" grid rendering
- Add logic to ensure pipes don't intersect below-ground buildings/other pipes
- *End of first half day*
- *Start of day 2* (full day)
- Started working on figuring out pipe/unit connectedness graph
- Add some popups to show unit stats
- Add basic UI layout code for buttons
- Add underground rocks
- Add ability to delete pipes
- Work on water-flow simulation (got nerd-sniped here for a bit)
- Add goo pools
- More UI buttons
- Fix some nasty memory free bugs
- *End of day 2*
- *Start of final half day*
- Add sound effects/ambience
- Add art
- Push builds to itch.io with ~20 min to spare.

## Lessons learned

I bit off *wayy* more than I could chew. 
This nearly always happens with game jams, but man it's been a while since I did a 48 hr jam and dealt with this much of a compressed schedule.

The original idea was something with pipes underground and buildings above ground, and I thought the interaction pipe and building placement could be interesting.

Really the problem being solved is figuring out if there's a way of constructing a planar graph that meets the requirements. 
Unfortunately, I threw a bunch of additional problems on top.
I thought simulating water and using the pipe length as part of the simulation could be interesting. 
This took a bunch of time and didn't end up contributing much to gameplay (in fact I ditched the pipe length logic because it just confused things).
I also was taking inspiration from Frostpunk and started adding in a store/economy system, but didn't have any time to flesh it out so it just ate up time without contributing.

The reason I added all the extra stuff is because the pipe placing mechanic was a toy on its own.
I fell back to adding mechanics that I knew would probably work, but should have just utilized the mechanics I already built.
A smarter pivot might have been dropping the "city-building" aspect and turning it into more of a puzzle game.

On a more positive note, the FSM implementation I used worked very well. 
I regularly use FSMs but the ability to trigger events on state changes (enter/exit transitions) was extremely useful.
In the past I've used coroutines to do this, but Odin doesn't have them so I'm glad I discovered this approach because it's very simple to implement procedurally.

A minor tweak I want to make is using a tagged union instead of a enum so I can keep come state variables local to the state they affect.

Surprisingly I didn't run into many issues with memory management. 
I used fixed allocations when possible and that made things fairly safe and easy to work with.
The one bug I did run into was because I was misusing the `core:container/intrusive/list` node type and freeing the wrong thing.
Gotta remember that foot gun for next time.

I crammed in some sound effects at the last minute and I'm glad I did.
It really contributes to game juice and makes the game feel more alive.
Even dropping in a simple BFXR blip can help make a simple button press feel better.

As always, I ran into build issues right before submission. The Mac build was fine (I did all development on macOS this time), the web build was busted.
I think it's because dynamic allocation in odin WASM builds break... Still need to debug this. For the jam submission I hacked out a build on my windows laptop.

## Tools/utilities I want for next time

**Input management**. 
I kept having to throw in hacks to ignore certain keyboard/mouse events so they wouldn't be double-processed on one frame..
It would be nice to have a utility method to flag an event as already processed, or that pumps the event queue with `glfwPollEvents()`.

**UI Layout**.  
I keep reinventing the same `rect := next_row(&row, row_size)`, `rect := next_col(&row, col_width)`, `DrawTextCentered()` logic. 
Also had to do the boilerplate to `CheckCollisionRectanglePoint(dialog_rect, mouse)` logic to ignore all further mouse processing later in the frame when a dialog was visible.
Having some UI stuff handy for creating popup boxes/button rows/button grids would be quite useful.

Ideas: 
* https://pangui.io
* https://www.rfleury.com/p/ui-part-3-the-widget-building-language

**Asset management code**.

Boilerplate to load images/audio files from a directory. Atlas generation + asset enum generation would be even better.

**Audio firing utils for lots of instances**.

It would be nice to have a way of firing a sound and knowing how many instances of it are playing (e.g. cull sounds if >3 instances fire).

**2D Polygon rendering**.
`rlgl` isn't available in the Odin raylib bindings, so [this example](https://www.raylib.com/examples/textures/loader.html?name=textures_polygon) didn't work.
Either write the code in C and link it into the odin binary or expose `rlgl` bindings.

**Polygon generator tool**. 
For drawing the rock shapes, I want a visual editor that can generate a list of `{x, y}` points. 
From there I could either copy/paste the list, or read/write it to an odin source file and have a really ghetto level format that doesn't require runtime serialization.
For this jam, I spit out SVG paths, then copy pasted and did some text manipulation in vim to get it loaded. 
This was fine, but it would be better to have a dedicated tool.

**2D sort/depth rendering**.
I didn't actually end up needing 2D depth sorting code for the submission, but with the isometric look I definitely could have needed it. 
Maybe support some kind of depth map too for VFX.

**Static allocator so the dang web build works**.
This is the second time I've been burned by WASM memory allocation breaking my web build. 
I should really have learned my lesson :|
