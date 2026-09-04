-- Runtime-only window rules for the YouTube Music shell plugin.
-- The service evaluates this file after startup and after every Hyprland
-- config reload. Nothing is written into the user's Hyprland configuration.

_G.omarchy_youtube_music = _G.omarchy_youtube_music or {}
local M = _G.omarchy_youtube_music

local DROPDOWN_WIDTH = 960
local DROPDOWN_HEIGHT = 680
local MAX_WIDTH = 1080
local MAX_HEIGHT = 760

local function is_music(w)
  if w == nil then return false end
  local class = tostring(w.class or w.initial_class or "")
  if class == "wolften.youtube-music" then return true end
  return class:find("music.youtube.com", 1, true) ~= nil
end

local function too_large(w)
  local size = w.size or {}
  local width = tonumber(size.x or size.width) or 0
  local height = tonumber(size.y or size.height) or 0
  if width > MAX_WIDTH or height > MAX_HEIGHT then return true end

  local monitor = w.monitor
  if monitor == nil then return false end
  local monitor_size = monitor.size or {}
  local monitor_width = tonumber(monitor_size.width or monitor.width) or 0
  local monitor_height = tonumber(monitor_size.height or monitor.height) or 0
  return (monitor_width > 0 and width >= monitor_width * 0.85)
    or (monitor_height > 0 and height >= monitor_height * 0.85)
end

function M.enforce(w)
  if not is_music(w) then return end

  hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = "0", window = w }))

  if not w.floating then
    hl.dispatch(hl.dsp.window.float({ window = w, action = "set" }))
  end
  if tonumber(w.fullscreen) and tonumber(w.fullscreen) ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ window = w, action = "unset" }))
    hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = "maximized", action = "unset" }))
  end

  if too_large(w) then
    hl.dispatch(hl.dsp.window.resize({
      window = w,
      x = DROPDOWN_WIDTH,
      y = DROPDOWN_HEIGHT,
      relative = false
    }))
  end
end

function M.enforce_later(w)
  M.enforce(w)
  hl.timer(function()
    M.enforce(w)
  end, { timeout = 80, type = "oneshot" })
end

function M.dismiss_parking(ws)
  ws = ws or (hl.get_active_special_workspace and hl.get_active_special_workspace() or nil)
  if ws == nil then return end
  local name = tostring(ws.name or "")
  if name ~= "special:wolften-youtube-music" and not name:find("wolften-youtube-music", 1, true) then
    return
  end
  hl.dispatch(hl.dsp.workspace.toggle_special("wolften-youtube-music"))
end

local function disable_rule(rule)
  if rule then pcall(function() rule:set_enabled(false) end) end
end

-- Click-away dismissal: a global, non-consuming left-click bind that asks
-- control.sh whether the cursor is outside the dropdown and hides it.
-- Installed only while the dropdown is open, so normal clicks are
-- untouched the rest of the time. Clicks pass through (non_consuming),
-- the checker just observes cursor position vs window rect.
function M.arm_clickaway(script)
  M.disarm_clickaway()
  script = tostring(script or "")
  if script == "" then return end
  local quoted = "'" .. script:gsub("'", "'\\''") .. "' clickaway"
  local ok, bind = pcall(function()
    return hl.bind("mouse:272", hl.dsp.exec_cmd(quoted), {
      mouse = true,
      non_consuming = true,
      description = "wolften.youtube-music-clickaway",
    })
  end)
  if ok then M.clickawayBind = bind end
end

function M.disarm_clickaway()
  local bind = M.clickawayBind
  M.clickawayBind = nil
  if bind ~= nil then pcall(function() bind:remove() end) end
end

function M.install(force)
  if force then
    M.installed = false
    disable_rule(M.rule)
    disable_rule(M.parkedRule)
    M.rule = nil
    M.parkedRule = nil
  end

  if not M.rule then
    local ok, rule = pcall(function()
      return hl.window_rule({
        name = "wolften-youtube-music-dropdown",
        match = {
          class = "^(wolften\\.youtube-music|.*music\\.youtube\\.com.*)$",
        },
        tag = "+youtube-music-dropdown",
        float = true,
        -- No open/close/move animations: the dropdown must appear and
        -- vanish instantly like a menu, not slide in like a window.
        -- (Lua API uses snake_case: no_anim, like no_blur.)
        no_anim = true,
        workspace = "special:wolften-youtube-music silent",
        opacity = "1.0 1.0",
        rounding = 0,
        border_size = 1,
        size = { DROPDOWN_WIDTH, DROPDOWN_HEIGHT },
        min_size = { 640, 420 },
        max_size = { MAX_WIDTH, MAX_HEIGHT },
        center = false,
        focus_on_activate = false,
        suppress_event = "maximize fullscreen activate activatefocus",
      })
    end)
    if ok then M.rule = rule end
  else
    pcall(function() M.rule:set_enabled(true) end)
  end

  -- The special workspace is only a parking lot. If Hyprland focuses the
  -- parked Chromium window (layer-shell Exclusive restore, activate
  -- requests), it would reveal that workspace and dim the desktop.
  if not M.parkedRule then
    local ok, rule = pcall(function()
      return hl.window_rule({
        name = "wolften-youtube-music-parked",
        match = {
          class = "^(wolften\\.youtube-music|.*music\\.youtube\\.com.*)$",
          workspace = "special:wolften-youtube-music",
        },
        no_focus = true,
        focus_on_activate = false,
      })
    end)
    if ok then M.parkedRule = rule end
  else
    pcall(function() M.parkedRule:set_enabled(true) end)
  end
  M.installed = true

  if not M.watching then
    M.watching = true
    hl.on("window.open", function(w) M.enforce_later(w) end)
    hl.on("window.move_to_workspace", function(w) M.enforce_later(w) end)
    hl.on("window.fullscreen", function(w) M.enforce(w) end)
  end

  if not M.specialWatching then
    M.specialWatching = true
    pcall(function()
      hl.on("workspace.special_active", function(ws)
        M.dismiss_parking(ws)
      end)
    end)
  end

  return "installed"
end
