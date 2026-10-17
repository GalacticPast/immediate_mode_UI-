package main
import pl "platform"
import gl "vendor:OpenGL"
// this feels so weird
// comming from 'C' land where I literally had to write everything by hand
main :: proc() {
    if !pl.startup(600, 400) {
        return
    }

    run: bool = true

    for run {
        list: pl.event_list = pl.get_events()
        e: ^pl.event = list.head
        for ; e != nil; e = e.next {
            #partial switch e.type {
                case .WINDOW_CLOSE:
                    run = false
                case:
            }
        }
        // draw
        gl.ClearColor(0.4, 0.5, 0.0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
