function love.conf(t)
  t.identity = "survivor_rts"
  t.version = "11.5"
  t.console = false

  t.window.title = "Survivor RTS"
  t.window.width = 1600
  t.window.height = 900
  t.window.minwidth = 1100
  t.window.minheight = 680
  t.window.resizable = true
  t.window.msaa = 4
  t.window.vsync = 1
end
