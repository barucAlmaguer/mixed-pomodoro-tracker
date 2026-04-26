-- pomo/init.lua — menubar + floating panel for pomodoro-tracker.

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

local BASE_URL       = "http://localhost:4123"
local STATE_URL      = BASE_URL .. "/api/state"
local FLOATING_URL   = BASE_URL .. "/floating"
local FULL_APP_URL   = BASE_URL .. "/"

local POLL_INTERVAL_S      = 1
local AUTO_SHOW_SUPPRESS_S = 30   -- after manual hide, suppress auto-show this long
local PANEL_W              = 320
local PANEL_H              = 480
local PANEL_MARGIN_RIGHT   = 40
local PANEL_MARGIN_TOP     = 80

local SETTINGS_FRAME_KEY = "pomo.floatingFrame"

-- ---------------------------------------------------------------------------
-- Module-private state
-- ---------------------------------------------------------------------------

local state = {
  online      = false,
  last_state  = nil, -- last decoded JSON snapshot
  last_phase  = nil, -- last seen timer.phase, for transition detection
  last_running = nil,
}

local poll_timer    = nil
local menubar       = nil
local floating      = nil
local hidden_until  = 0           -- timestamp; auto-show suppressed before this
local hotkey_toggle = nil
local hotkey_open   = nil
local started       = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Safely get the hs.window from a webview without crashing.
local function pcall_win(wv)
  if not wv then return nil end
  local ok, win = pcall(function() return wv:hswindow() end)
  return (ok and win) or nil
end

local function safe_get(t, key, default)
  if type(t) ~= "table" then return default end
  local v = t[key]
  if v == nil then return default end
  return v
end

local function format_mmss(ms)
  ms = tonumber(ms) or 0
  if ms < 0 then ms = 0 end
  local total = math.floor(ms / 1000)
  local m = math.floor(total / 60)
  local s = total % 60
  return string.format("%d:%02d", m, s)
end

local function now_seconds()
  return hs.timer.secondsSinceEpoch()
end

local function floating_visible()
  if not floating then return false end
  local ok, win = pcall(function() return floating:hswindow() end)
  if not ok or not win then return false end
  local ok2, vis = pcall(function() return win:isVisible() end)
  return ok2 and vis or false
end

-- Find an existing Chrome/Safari/Arc tab pointing at the full app and focus
-- it instead of opening a new tab. Falls back to openURL if nothing found.
-- Improved AppleScript that finds existing tab and brings browser to front
-- Matches any host ending with :4123 (localhost, 127.0.0.1, Tailscale IPs, etc.)
-- Returns: "ok:Chrome" | "ok:Arc" | etc, or "miss"
local FOCUS_TAB_SCRIPT = [[
on hostMatches(theURL)
  -- Match :4123/ or :4123 (with or without trailing slash)
  if theURL contains ":4123" and (theURL does not contain "/floating") and (theURL does not contain "/api/") then
    return true
  end if
  return false
end hostMatches

-- Chromium-based browsers (Chrome, Arc, Brave, Edge)
set browsers to {{"Google Chrome", "Chrome"}, {"Arc", "Arc"}, {"Brave Browser", "Brave"}, {"Microsoft Edge", "Edge"}}
repeat with browserInfo in browsers
  set bname to item 1 of browserInfo
  set bshort to item 2 of browserInfo
  try
    tell application "System Events"
      if exists (process bname) then
        tell application bname
          set foundTab to false
          set foundWindow to missing value
          set foundIndex to 0

          -- Find the tab
          repeat with w in windows
            set tabIndex to 0
            repeat with t in tabs of w
              set tabIndex to tabIndex + 1
              if my hostMatches(URL of t) then
                set foundTab to true
                set foundWindow to w
                set foundIndex to tabIndex
                exit repeat
              end if
            end repeat
            if foundTab then exit repeat
          end repeat

          -- If found, activate it
          if foundTab then
            set active tab index of foundWindow to foundIndex
            set index of foundWindow to 1
            activate
            return "ok:" & bshort
          end if
        end tell
      end if
    end tell
  on error errMsg
    -- Continue to next browser
  end try
end repeat

-- Safari (different tab model)
try
  tell application "System Events"
    if exists (process "Safari") then
      tell application "Safari"
        set foundTab to false
        set foundWindow to missing value
        set foundTabObj to missing value

        repeat with w in windows
          repeat with t in tabs of w
            if my hostMatches(URL of t) then
              set foundTab to true
              set foundWindow to w
              set foundTabObj to t
              exit repeat
            end if
          end repeat
          if foundTab then exit repeat
        end repeat

        if foundTab then
          set current tab of foundWindow to foundTabObj
          set index of foundWindow to 1
          activate
          return "ok:Safari"
        end if
      end tell
    end if
  end tell
on error errMsg
  -- Safari check failed
end try

return "miss"
]]

local function open_full_app()
  local ok, result = hs.osascript.applescript(FOCUS_TAB_SCRIPT)

  -- Debug: descomenta la siguiente línea para ver qué retorna el AppleScript
  -- hs.notify.new({title="Pomo Debug", informativeText="Result: " .. tostring(ok) .. " / " .. tostring(result)}):send()

  if ok and type(result) == "string" and result:match("^ok:") then
    -- Successfully focused existing tab in browser X
    return
  end

  -- Fallback: open new tab
  hs.urlevent.openURL(FULL_APP_URL)
end

-- ---------------------------------------------------------------------------
-- Drag / event handling
-- ---------------------------------------------------------------------------
-- We do NOT use hs.eventtap. It interferes with macOS event system and causes
-- "ghost drags", laggy interactions, and broken close buttons.
--
-- Instead we rely on native window styles:
--   - "titled" gives us a draggable titlebar (macOS native)
--   - "closable" gives us a working close button
--   - "resizable" gives us native resize handles
--   - "utility" keeps it lightweight but functional
--
-- Native drag is smooth. Eventtap was causing the lag and ghost events.

-- ---------------------------------------------------------------------------
-- Menubar title rendering
-- ---------------------------------------------------------------------------

local function styled(text, color)
  -- color: nil for default, or {red=..., green=..., blue=..., alpha=...}
  local attrs = { font = { name = ".AppleSystemUIFont", size = 13 } }
  if color then attrs.color = color end
  return hs.styledtext.new(text, attrs)
end

local function format_menubar_title(snap)
  if not state.online or not snap then
    return styled("🔌")
  end

  local timer = safe_get(snap, "timer", {})
  local phase   = safe_get(timer, "phase", "idle")
  local running = safe_get(timer, "running", false)
  local rem     = safe_get(timer, "remaining_ms", 0)
  local next_due = safe_get(snap, "next_due", nil)

  if phase ~= "idle" then
    local clock = format_mmss(rem)
    local icon
    if running then
      if phase == "work" then
        icon = "🍅"
      else
        icon = "☕"
      end
    else
      icon = "⏸"
    end
    return styled(icon .. " " .. clock)
  end

  -- Idle states
  if next_due and type(next_due) == "table" then
    local minutes = tonumber(safe_get(next_due, "minutes", 0)) or 0
    local title   = safe_get(next_due, "title", "")
    local human   = safe_get(next_due, "humanized", "")

    if minutes <= 0 then
      -- due now or overdue: red warning
      local mins_late = math.abs(minutes)
      local label = string.format("⚠️ %s %dm tarde", title, mins_late)
      -- Truncate to keep it short
      if #label > 22 then
        label = string.sub(label, 1, 21) .. "…"
      end
      return styled(label, { red = 0.85, green = 0.15, blue = 0.15, alpha = 1 })
    elseif minutes < 120 then
      return styled("🟢 in " .. human)
    end
  end

  return styled("🍅")
end

-- ---------------------------------------------------------------------------
-- Menu (dropdown) construction
-- ---------------------------------------------------------------------------

local function build_menu(snap)
  local items = {}

  if not state.online or not snap then
    table.insert(items, { title = "Pomodoro server offline", disabled = true })
    table.insert(items, { title = "-" })
    table.insert(items, {
      title = "Open full app",
      fn = function() open_full_app() end,
    })
    table.insert(items, { title = "-" })
    table.insert(items, { title = "Reload", fn = function() M.reload() end })
    table.insert(items, { title = "Quit menubar", fn = function() M.stop() end })
    return items
  end

  local timer = safe_get(snap, "timer", {})
  local day   = safe_get(snap, "day", {})
  local active_ids = safe_get(timer, "task_ids", {})
  local pending = safe_get(day, "pending", {})
  local next_due = safe_get(snap, "next_due", nil)

  -- Active task header
  local active_title = nil
  if type(active_ids) == "table" and #active_ids > 0 then
    -- Try to find the first active task in pending list (by id) for a friendly title
    local first_id = active_ids[1]
    for _, t in ipairs(pending) do
      if safe_get(t, "id") == first_id then
        active_title = safe_get(t, "title")
        break
      end
    end
    if not active_title then active_title = first_id end
  end

  if active_title then
    table.insert(items, { title = "🍅 " .. active_title, disabled = true })
  else
    local phase = safe_get(timer, "phase", "idle")
    if phase == "idle" then
      table.insert(items, { title = "🍅 No active task", disabled = true })
    else
      table.insert(items, { title = "🍅 " .. phase, disabled = true })
    end
  end

  table.insert(items, { title = "-" })

  -- Pending section
  local pending_count = safe_get(day, "pending_count", #pending)
  table.insert(items, {
    title = string.format("PENDING (%d)", pending_count),
    disabled = true,
  })

  if type(pending) == "table" and #pending > 0 then
    local shown = 0
    for i, t in ipairs(pending) do
      if shown >= 5 then break end
      local title = safe_get(t, "title", "(untitled)")
      table.insert(items, { title = "  • " .. title, disabled = true })
      shown = shown + 1
    end
    if #pending > 5 then
      table.insert(items, {
        title = string.format("  …and %d more", #pending - 5),
        disabled = true,
      })
    end
  else
    table.insert(items, { title = "  (none)", disabled = true })
  end

  -- Next deadline section
  if next_due and type(next_due) == "table" then
    table.insert(items, { title = "-" })
    table.insert(items, { title = "NEXT DEADLINE", disabled = true })
    local title = safe_get(next_due, "title", "(untitled)")
    local human = safe_get(next_due, "humanized", "")
    table.insert(items, {
      title = string.format("  ⏰ %s · %s", title, human),
      disabled = true,
    })
  end

  table.insert(items, { title = "-" })
  table.insert(items, {
    title = (floating_visible() and "Hide floating panel" or "Show floating panel"),
    shortcut = "P",
    fn = function() M.toggle_floating() end,
  })
  table.insert(items, {
    title = "Open full app",
    fn = function() hs.urlevent.openURL(FULL_APP_URL) end,
  })
  table.insert(items, { title = "-" })
  table.insert(items, { title = "Reload", fn = function() M.reload() end })
  table.insert(items, { title = "Quit menubar", fn = function() M.stop() end })

  return items
end

-- ---------------------------------------------------------------------------
-- Floating panel (hs.webview)
-- ---------------------------------------------------------------------------

local function default_frame()
  local screen = hs.screen.mainScreen()
  local sf = screen and screen:frame() or { x = 0, y = 0, w = 1440, h = 900 }
  return {
    x = sf.x + sf.w - PANEL_W - PANEL_MARGIN_RIGHT,
    y = sf.y + PANEL_MARGIN_TOP,
    w = PANEL_W,
    h = PANEL_H,
  }
end

local function load_frame()
  local saved = hs.settings.get(SETTINGS_FRAME_KEY)
  if type(saved) == "table"
    and saved.x and saved.y and saved.w and saved.h then
    return saved
  end
  return default_frame()
end

local function save_frame()
  if not floating then return end
  local ok, frame = pcall(function() return floating:frame() end)
  if ok and frame then
    hs.settings.set(SETTINGS_FRAME_KEY, {
      x = frame.x, y = frame.y, w = frame.w, h = frame.h,
    })
  end
end

local function ensure_floating()
  if floating then return floating end

  local frame = load_frame()
  local prefs = {
    developerExtrasEnabled = false,
    suppressesIncrementalRendering = false,
  }

  local wv = hs.webview.new(frame, prefs)
  if not wv then return nil end

  wv:url(FLOATING_URL)
  -- "titled" + "utility" gives a small panel-style titlebar that's
  -- draggable. Without "titled" the borderless window can't be moved.
  wv:windowStyle({ "titled", "closable", "resizable", "utility" })
  wv:level(hs.drawing.windowLevels.floating)
  -- "stationary" can prevent manual dragging on some macOS versions — removed.
  wv:behaviorAsLabels({ "canJoinAllSpaces" })
  wv:allowGestures(true)
  wv:allowTextEntry(true)
  wv:bringToFront(true)
  wv:windowTitle("Pomo")

  -- Save frame when the window changes (we poll on hide too).
  floating = wv
  return floating
end

local function open_floating()
  local wv = ensure_floating()
  if not wv then return end
  wv:show()
  wv:bringToFront(true)
  -- Ensure the window is key so interactions work immediately
  pcall(function()
    local win = wv:hswindow()
    if win then win:focus() end
  end)
end

local function close_floating()
  if not floating then return end
  save_frame()
  floating:hide()
  hidden_until = now_seconds() + AUTO_SHOW_SUPPRESS_S
end

function M.toggle_floating()
  if floating and floating:hswindow() and floating:hswindow():isVisible() then
    close_floating()
  else
    open_floating()
  end
end

-- ---------------------------------------------------------------------------
-- Transition detection / auto-summon
-- ---------------------------------------------------------------------------

local function on_state_update(snap)
  if not snap then return end
  local timer = safe_get(snap, "timer", {})
  local phase = safe_get(timer, "phase", "idle")
  local running = safe_get(timer, "running", false)

  -- Detect transition: previously running (work/active_break/...) → now idle.
  if state.last_phase
    and state.last_phase ~= "idle"
    and state.last_running == true
    and phase == "idle" then
    -- A pomodoro / break just ended. Auto-summon the panel unless suppressed.
    if now_seconds() >= hidden_until then
      open_floating()
    end
  end

  state.last_phase = phase
  state.last_running = running
end

-- ---------------------------------------------------------------------------
-- HTTP polling
-- ---------------------------------------------------------------------------

local function apply_snapshot(snap)
  state.last_state = snap
  if menubar then
    menubar:setTitle(format_menubar_title(snap))
    menubar:setMenu(build_menu(snap))
  end
  on_state_update(snap)
end

local function fetch_state(callback)
  hs.http.asyncGet(STATE_URL, nil, function(status, body, _headers)
    if status ~= 200 or type(body) ~= "string" or body == "" then
      state.online = false
      if menubar then
        menubar:setTitle(format_menubar_title(nil))
        menubar:setMenu(build_menu(nil))
      end
      if callback then callback(nil) end
      return
    end

    local ok, decoded = pcall(hs.json.decode, body)
    if not ok or type(decoded) ~= "table" then
      state.online = false
      if menubar then
        menubar:setTitle(format_menubar_title(nil))
        menubar:setMenu(build_menu(nil))
      end
      if callback then callback(nil) end
      return
    end

    state.online = true
    apply_snapshot(decoded)
    if callback then callback(decoded) end
  end)
end

local function start_polling()
  if poll_timer then poll_timer:stop() end
  fetch_state(nil) -- prime immediately
  poll_timer = hs.timer.doEvery(POLL_INTERVAL_S, function()
    fetch_state(nil)
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.start()
  if started then return M end

  menubar = hs.menubar.new()
  if menubar then
    menubar:setTitle(styled("🍅"))
    menubar:setMenu(build_menu(nil))
    menubar:setTooltip("Pomodoro tracker")
  end

  hotkey_toggle = hs.hotkey.bind({ "cmd", "shift" }, "P", function()
    M.toggle_floating()
  end)
  hotkey_open = hs.hotkey.bind({ "cmd", "shift" }, "O", function()
    open_full_app()
  end)

  start_polling()
  started = true
  return M
end

function M.stop()
  if poll_timer then
    poll_timer:stop()
    poll_timer = nil
  end
  if hotkey_toggle then hotkey_toggle:delete(); hotkey_toggle = nil end
  if hotkey_open then hotkey_open:delete(); hotkey_open = nil end
  if floating then
    save_frame()
    pcall(function() floating:delete() end)
    floating = nil
  end
  if menubar then
    pcall(function() menubar:delete() end)
    menubar = nil
  end
  state.online = false
  state.last_state = nil
  state.last_phase = nil
  state.last_running = nil
  started = false
  return M
end

function M.reload()
  hs.timer.doAfter(0.1, function()
    hs.reload()
  end)
end

-- Test hooks (used by pomo.test)
M._internal = {
  format_menubar_title = format_menubar_title,
  build_menu           = build_menu,
  fetch_state          = fetch_state,
  state                = state,
  format_mmss          = format_mmss,
  default_frame        = default_frame,
}

return M
