-- pomo/init.lua — integration temporarily disabled while the app is
-- simplified back to a single supported Phoenix LiveView surface.

local M = {}

local function notify()
  hs.notify
    .new({
      title = "PomodoroTracker",
      informativeText = "Hammerspoon integration is temporarily disabled. Use the full web app instead.",
    })
    :send()
end

function M.start()
  notify()
  return M
end

function M.stop()
  return M
end

function M.reload()
  hs.reload()
  return M
end

return M
