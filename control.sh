#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WINDOW_CLASS="wolften.youtube-music"
SPECIAL_NAME="wolften-youtube-music"
SPECIAL_WORKSPACE="special:$SPECIAL_NAME"
MUSIC_URL="https://music.youtube.com"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-youtube-music"
PROFILE_DIR="$DATA_DIR/chromium"

hypr_json() {
  local command=$1 output signature
  if output=$(hyprctl -j "$command" 2>/dev/null); then
    printf '%s' "$output"
    return
  fi

  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl -j "$command"
}

hypr_call() {
  if hyprctl "$@" >/dev/null 2>&1; then
    return
  fi

  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl "$@" >/dev/null
}

state() {
  local clients monitors
  clients=$(hypr_json clients)
  monitors=$(hypr_json monitors)

  jq -cn \
    --arg class "$WINDOW_CLASS" \
    --arg workspace "$SPECIAL_WORKSPACE" \
    --argjson clients "$clients" \
    --argjson monitors "$monitors" \
    '(first($clients[] | select(
        ((.class // "") == $class)
        or ((.initialClass // "") == $class)
        or ((.class // "") | contains("music.youtube.com__"))
        or ((.initialClass // "") | contains("music.youtube.com__"))
      )) // null) as $client |
    {
      client: $client,
      monitors: $monitors,
      open: ($client != null and ($client.workspace.name // "") != $workspace),
      openScreen: (if $client != null and ($client.workspace.name // "") != $workspace
        then (first($monitors[] | select(.id == $client.monitor) | .name) // "")
        else ""
      end)
    }'
}

browser_executable() {
  command -v chromium || command -v google-chrome-stable || command -v google-chrome
}

configure_profile() {
  local preferences="$PROFILE_DIR/Default/Preferences" tmp
  umask 077
  mkdir -p "$PROFILE_DIR/Default"

  tmp=$(mktemp "$PROFILE_DIR/Default/.Preferences.XXXXXX")
  if [[ -f $preferences ]]; then
    if ! jq '
      .browser.app_window_placement.music.youtube["com_/"] = (
        (.browser.app_window_placement.music.youtube["com_/"] // {}) + {
          maximized: false,
          left: 480,
          top: 80,
          right: 1440,
          bottom: 760
        }
      )
    ' "$preferences" >"$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  else
    if ! jq -n '{
      browser: {
        app_window_placement: {
          music: {
            youtube: {
              "com_/": {
                maximized: false,
                left: 480,
                top: 80,
                right: 1440,
                bottom: 760
              }
            }
          }
        }
      }
    }' >"$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  fi

  chmod 0600 "$tmp"
  mv -f -- "$tmp" "$preferences"
}

launch() {
  local executable unit
  executable=$(browser_executable)
  [[ -n $executable ]] || return 1
  unit="omarchy-youtube-music-$(date +%s%N)"

  umask 077
  mkdir -p "$PROFILE_DIR/Default"
  configure_profile || true
  install_rules "$ROOT/hypr/youtube-music.lua" true || true

  systemd-run --user --quiet --collect --unit="$unit" \
    --property=StandardOutput=null --property=StandardError=null \
    uwsm-app -- "$executable" \
      --user-data-dir="$PROFILE_DIR" \
      --class="$WINDOW_CLASS" \
      --app="$MUSIC_URL" \
      --window-size=960,680 \
      --no-first-run \
      --disable-features=Translate,MediaRouter \
      --disable-session-crashed-bubble
}

hypr_batch() {
  local batch=$1 op
  shift
  for op in "$@"; do
    batch+="dispatch $op ; "
  done
  batch=${batch% ; }
  if hyprctl --batch "$batch" >/dev/null 2>&1; then
    return 0
  fi

  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl --batch "$batch" >/dev/null
}

show_window() {
  local address=$1 screen=$2 x=$3 y=$4 width=$5 height=$6

  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return 2
  [[ $screen =~ ^[[:alnum:]_.:-]+$ ]] || return 2
  [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || return 2
  [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 2

  local workspace cursor
  cursor=$(cursor_xy)
  workspace=$(hypr_json monitors | jq -r --arg screen "$screen" \
    'first(.[] | select(.name == $screen) | .activeWorkspace.name) // empty')
  [[ -n $workspace && $workspace != *$'\n'* && $workspace != *'"'* && $workspace != *'\\'* ]] || return 2

  # Park overlay away first so it never overlaps the reveal.
  dismiss_special

  # One atomic batch: the window used to be moved in several roundtrips,
  # painting an intermediate frame (often centered) before landing on the
  # final rect. Applied together, it appears directly where it should.
  # A tiled window on an empty workspace would stretch to fill the monitor,
  # so keep it floating and compact throughout the move.
  local -a ops=(
    "hl.dsp.window.float({ window = \"address:$address\", action = \"set\" })"
    "hl.dsp.window.fullscreen({ window = \"address:$address\", action = \"unset\" })"
    "hl.dsp.window.fullscreen({ window = \"address:$address\", mode = \"maximized\", action = \"unset\" })"
    "hl.dsp.window.resize({ window = \"address:$address\", x = $width, y = $height, relative = false })"
    "hl.dsp.window.move({ window = \"address:$address\", workspace = \"$workspace\", follow = false })"
    "hl.dsp.focus({ monitor = \"$screen\" })"
    "hl.dsp.window.resize({ window = \"address:$address\", x = $width, y = $height, relative = false })"
    "hl.dsp.window.move({ window = \"address:$address\", x = $x, y = $y, relative = false })"
    "hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:$address\" })"
    "hl.dsp.focus({ window = \"address:$address\" })"
  )
  if ! hypr_batch "" "${ops[@]}"; then
    local op
    for op in "${ops[@]}"; do
      hypr_call dispatch "$op" || true
    done
  fi
  restore_cursor $cursor
}

cursor_xy() {
  local cursor_json cursor_x cursor_y
  cursor_json=$(hypr_json cursorpos 2>/dev/null || true)
  cursor_x=$(jq -r '(.x // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  cursor_y=$(jq -r '(.y // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  if [[ $cursor_x =~ ^-?[0-9]+$ && $cursor_y =~ ^-?[0-9]+$ ]]; then
    printf '%s %s' "$cursor_x" "$cursor_y"
  fi
}

restore_cursor() {
  local cursor_x=${1:-} cursor_y=${2:-}
  if [[ $cursor_x =~ ^-?[0-9]+$ && $cursor_y =~ ^-?[0-9]+$ ]]; then
    hypr_call dispatch "hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y })"
  fi
}

# Hide the dropdown when a left click lands outside of it. Invoked by the
# non-consuming mouse bind armed while the dropdown is open. Quiet and
# fast: a no-op unless the window is currently open and the cursor is out.
clickaway() {
  local snapshot address open at_x at_y width height cursor cursor_x cursor_y
  snapshot=$(state) || return 0
  open=$(jq -r '.open // false' <<<"$snapshot")
  [[ $open == "true" ]] || return 0
  address=$(jq -r '.client.address // empty' <<<"$snapshot")
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return 0
  at_x=$(jq -r '.client.at[0] // empty' <<<"$snapshot")
  at_y=$(jq -r '.client.at[1] // empty' <<<"$snapshot")
  width=$(jq -r '.client.size[0] // empty' <<<"$snapshot")
  height=$(jq -r '.client.size[1] // empty' <<<"$snapshot")
  [[ $at_x =~ ^-?[0-9]+$ && $at_y =~ ^-?[0-9]+$ ]] || return 0
  [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 0
  cursor=$(cursor_xy)
  cursor_x=${cursor%% *}
  cursor_y=${cursor##* }
  [[ $cursor_x =~ ^-?[0-9]+$ && $cursor_y =~ ^-?[0-9]+$ ]] || return 0
  if (( cursor_x < at_x || cursor_y < at_y
    || cursor_x >= at_x + width || cursor_y >= at_y + height )); then
    hide_window "$address"
  fi
  return 0
}

eval_lua() {
  local snippet=$1 result
  if result=$(hyprctl eval "$snippet" 2>&1); then
    printf '%s\n' "$result"
    return 0
  fi
  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl eval "$snippet"
}

clickaway_arm() {
  local script_escaped
  script_escaped=$(printf '%s/control.sh' "$ROOT" | sed "s/'/\\\\'/g")
  eval_lua "omarchy_youtube_music.arm_clickaway('$script_escaped')" >/dev/null || true
}

clickaway_disarm() {
  eval_lua "omarchy_youtube_music.disarm_clickaway()" >/dev/null || true
}

# The special workspace is a parking lot, never a visible overlay. Focusing
# the parked window (or moving onto it) can reveal it and dim the desktop.
dismiss_special() {
  local current cursor
  current=$(hypr_json monitors | jq -r --arg workspace "$SPECIAL_WORKSPACE" \
    'first(.[] | select((.specialWorkspace.name // "") == $workspace) | .name) // empty')
  [[ -n $current ]] || return 0
  cursor=$(cursor_xy)
  hypr_call dispatch "hl.dsp.focus({ monitor = \"$current\" })"
  hypr_call dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL_NAME\")"
  restore_cursor $cursor
}

hide_window() {
  local address=${1:-} focused fallback cursor
  if [[ -z $address ]]; then
    address=$(state | jq -r '.client.address // empty')
  fi
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return

  cursor=$(cursor_xy)
  hypr_call dispatch "hl.dsp.window.move({ window = \"address:$address\", workspace = \"$SPECIAL_WORKSPACE\", follow = false })"
  dismiss_special

  focused=$(hypr_json activewindow | jq -r '.address // empty')
  if [[ $focused == "$address" ]]; then
    fallback=$(hypr_json clients | jq -r --arg addr "$address" \
      'first(.[] | select(.address != $addr and ((.workspace.id // 0) > 0) and .mapped == true) | .address) // empty')
    if [[ $fallback =~ ^0x[0-9a-fA-F]+$ ]]; then
      hypr_call dispatch "hl.dsp.focus({ window = \"address:$fallback\" })" || true
    fi
    dismiss_special
  fi
  restore_cursor $cursor
}

focus_window() {
  local address=$1 cursor
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return 2

  cursor=$(cursor_xy)
  hypr_call dispatch "hl.dsp.focus({ window = \"address:$address\" })"
  restore_cursor $cursor
}

install_rules() {
  local lua_path=$1 force=${2:-false} code result
  [[ -f $lua_path ]] || return 1
  code="dofile('$(printf '%s' "$lua_path" | sed "s/'/\\\\'/g")'); omarchy_youtube_music.install($force)"
  if result=$(hyprctl eval "$code" 2>&1); then
    printf '%s\n' "$result"
    return 0
  fi
  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl eval "$code"
}

case ${1:-} in
state) state ;;
launch) launch ;;
show)
  (( $# == 7 )) || { echo "usage: $0 show <address> <screen> <x> <y> <width> <height>" >&2; exit 2; }
  show_window "$2" "$3" "$4" "$5" "$6" "$7"
  ;;
hide) hide_window "${2:-}" ;;
clickaway) clickaway ;;
clickaway-arm) clickaway_arm ;;
clickaway-disarm) clickaway_disarm ;;
dismiss-special) dismiss_special ;;
focus)
  (( $# == 2 )) || { echo "usage: $0 focus <address>" >&2; exit 2; }
  focus_window "$2"
  ;;
rules)
  (( $# >= 2 )) || { echo "usage: $0 rules <lua-path> [true|false]" >&2; exit 2; }
  install_rules "$2" "${3:-false}"
  ;;
*)
  echo "usage: $0 <state|launch|show|hide|clickaway|clickaway-arm|clickaway-disarm|dismiss-special|focus|rules>" >&2
  exit 2
  ;;
esac
