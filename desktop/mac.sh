#!/usr/bin/env bash
#
# mac.sh — one-shot setup for the Wallify desktop wallpaper changer on macOS.
#
# Asks for the change interval, your API keys and your tags, then installs
# the script, writes the config and schedules it with launchd.
#
# Usage, from a clone of the repo:
#   ./mac.sh              set up (safe to re-run; answers default to what is
#                         already configured)
#   ./mac.sh --uninstall  remove the schedule, keep the wallpapers
#
# Or without cloning anything:
#   bash <(curl -sSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/mac.sh)

set -u -o pipefail

REPO_RAW="https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/wallify-desktop.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallify"
CONFIG="$CONFIG_DIR/config"
LABEL="com.wallify.desktop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/wallify.log"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# How to run this installer again. When it is run straight from the web there
# is no file on disk to point people back at, so repeat the one-liner instead.
case "${BASH_SOURCE[0]}" in
  /dev/fd/*|/proc/*|"") SELF_CMD="bash <(curl -sSL $REPO_RAW/mac.sh)" ;;
  *)                    SELF_CMD="$HERE/mac.sh" ;;
esac

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "$(uname -s)" == Darwin ]] || die "This is the macOS installer. On Linux run linux.sh instead."

unload_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null ||
    launchctl unload "$PLIST" 2>/dev/null
  return 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
  unload_agent
  rm -f "$PLIST"
  say "Schedule removed. The script, your config and your wallpapers are untouched."
  say "To remove those too:  rm -rf $BIN $CONFIG_DIR"
  exit 0
fi

# curl | bash leaves stdin pointing at the script, so the answers are read from
# the terminal. Set WALLIFY_PIPED_ANSWERS=1 to feed them on stdin instead.
if [[ ! -t 0 && "${WALLIFY_PIPED_ANSWERS:-0}" != 1 ]]; then
  [[ -r /dev/tty ]] || die "Run this script from a terminal."
  exec </dev/tty
fi

# --- questions --------------------------------------------------------------

# Accepts "30", "30m", "4h" or "1d" and prints the value in minutes.
parse_interval() {
  local raw num unit
  raw=$(printf '%s' "${1// /}" | tr '[:upper:]' '[:lower:]')
  [[ "$raw" =~ ^([0-9]+)(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)?$ ]] || return 1
  num=${BASH_REMATCH[1]}
  unit=${BASH_REMATCH[2]:-m}
  (( num > 0 )) || return 1
  case "$unit" in
    h*) num=$(( num * 60 )) ;;
    d*) num=$(( num * 1440 )) ;;
  esac
  printf '%s' "$num"
}

# ask <variable> <prompt> <default>
ask() {
  local __var="$1" prompt="$2" default="${3:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply
  else
    read -r -p "$prompt (Enter to skip): " reply
  fi
  printf -v "$__var" '%s' "${reply:-$default}"
}

# Re-running should not mean typing everything again.
if [[ -f "$CONFIG" ]]; then
  say "Found an existing config at $CONFIG — its values are offered as defaults."
  # shellcheck source=/dev/null
  . "$CONFIG"
fi
OLD_INTERVAL=""
if [[ -f "$PLIST" ]]; then
  OLD_SECONDS=$(/usr/libexec/PlistBuddy -c "Print :StartInterval" "$PLIST" 2>/dev/null) || OLD_SECONDS=""
  [[ "$OLD_SECONDS" =~ ^[0-9]+$ ]] && OLD_INTERVAL="$(( OLD_SECONDS / 60 ))m"
fi

step "How often should the wallpaper change?"
say "Examples: 45m, 4h, 1d"
while :; do
  ask INTERVAL_RAW "Interval" "${OLD_INTERVAL:-4h}"
  INTERVAL_MINUTES=$(parse_interval "$INTERVAL_RAW") && break
  say "  Didn't understand '$INTERVAL_RAW'. Try a number of minutes, or 4h."
done
INTERVAL_SECONDS=$(( INTERVAL_MINUTES * 60 ))

step "API keys — press Enter to skip any you don't have."
say "Wallhaven, Openverse, Bing and Picsum work with no key at all."
ask UNSPLASH_ACCESS_KEY "Unsplash access key  (unsplash.com/oauth/applications)" "${UNSPLASH_ACCESS_KEY:-}"
ask PEXELS_API_KEY      "Pexels API key       (pexels.com/api)"                  "${PEXELS_API_KEY:-}"
ask PIXABAY_API_KEY     "Pixabay API key      (pixabay.com/api/docs)"            "${PIXABAY_API_KEY:-}"
ask WALLHAVEN_API_KEY   "Wallhaven API key    (optional)"                        "${WALLHAVEN_API_KEY:-}"
ask NASA_API_KEY        "NASA API key         (api.nasa.gov)"                    "${NASA_API_KEY:-DEMO_KEY}"

step "Tags — the search terms wallpapers are picked from."
DEFAULT_TAGS="nature, space, minimal, cyberpunk, mountains, ocean, night, city, abstract, forest"
if [[ -n "${TAGS+set}" ]] && (( ${#TAGS[@]} )); then
  DEFAULT_TAGS=$(printf '%s, ' "${TAGS[@]}" | sed 's/, $//')
fi
say "Separate them with commas."
ask TAGS_RAW "Tags" "$DEFAULT_TAGS"

# Split on commas, drop blanks and surrounding spaces.
NEW_TAGS=()
while IFS= read -r tag; do
  [[ -n "$tag" ]] && NEW_TAGS+=("$tag")
done < <(printf '%s\n' "$TAGS_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
(( ${#NEW_TAGS[@]} )) || NEW_TAGS=("nature" "space" "minimal")

# --- dependencies -----------------------------------------------------------

step "Checking dependencies"
missing=()
have curl || missing+=(curl)
have jq   || missing+=(jq)
if (( ${#missing[@]} )); then
  if have brew; then
    say "Installing: ${missing[*]}"
    brew install "${missing[@]}" || die "Could not install ${missing[*]}"
  else
    die "Missing ${missing[*]}. Install Homebrew (brew.sh) then: brew install ${missing[*]}"
  fi
fi
have magick || have convert || say "ImageMagick not found — images are used at their original size."
have wallpaper || say "Optional: 'brew install wallpaper' sets every screen more reliably than AppleScript."
say "OK"

# --- install ----------------------------------------------------------------

step "Installing the wallpaper script"
mkdir -p "$BIN_DIR" "$CONFIG_DIR" || die "Cannot create $BIN_DIR"
if [[ -f "$HERE/wallify-desktop.sh" ]]; then
  cp "$HERE/wallify-desktop.sh" "$BIN"
else
  curl -fsSL "$REPO_RAW/wallify-desktop.sh" -o "$BIN" || die "Could not download wallify-desktop.sh"
fi
chmod +x "$BIN"
say "$BIN"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Note: $BIN_DIR isn't on your PATH. The schedule doesn't care, but to"
     say "run it by name add this to your shell profile:"
     say "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

step "Writing the config"
[[ -f "$CONFIG" ]] && cp "$CONFIG" "$CONFIG.bak" && say "Previous config saved as $CONFIG.bak"
{
  printf '# Wallify desktop config — written by mac.sh on %s\n' "$(date)"
  printf '# Re-run mac.sh to change these, or edit them here.\n\n'
  printf 'UNSPLASH_ACCESS_KEY="%s"\n' "$UNSPLASH_ACCESS_KEY"
  printf 'PEXELS_API_KEY="%s"\n'      "$PEXELS_API_KEY"
  printf 'PIXABAY_API_KEY="%s"\n'     "$PIXABAY_API_KEY"
  printf 'WALLHAVEN_API_KEY="%s"\n'   "$WALLHAVEN_API_KEY"
  printf 'NASA_API_KEY="%s"\n\n'      "$NASA_API_KEY"
  printf 'SOURCES="%s"\n'             "${SOURCES:-wallhaven unsplash pexels pixabay openverse bing nasa picsum}"
  printf 'BING_MARKET="%s"\n\n'       "${BING_MARKET:-en-US}"
  printf 'TAGS=('
  printf '"%s" ' "${NEW_TAGS[@]}"
  printf ')\n\n'
  printf 'WALLPAPER_DIR="%s"\n'       "${WALLPAPER_DIR:-\$HOME/Pictures/Wallpapers}"
  printf 'KEEP_WALLPAPERS=%s\n'       "${KEEP_WALLPAPERS:-30}"
  printf 'RESOLUTION="%s"\n'          "${RESOLUTION:-auto}"
  printf 'ONLY_WHEN_CHARGING=%s\n'    "${ONLY_WHEN_CHARGING:-false}"
  printf 'MIN_INTERVAL_MINUTES=%s\n'  "${MIN_INTERVAL_MINUTES:-0}"
  printf 'SET_LOCK_SCREEN=%s\n'       "${SET_LOCK_SCREEN:-true}"
  printf 'POST_SET_HOOK="%s"\n'       "${POST_SET_HOOK:-}"
} > "$CONFIG"
chmod 600 "$CONFIG"
say "$CONFIG"

step "Scheduling it every $INTERVAL_RAW ($INTERVAL_MINUTES min)"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
  </array>
  <key>StartInterval</key>
  <integer>$INTERVAL_SECONDS</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
PLISTEOF

unload_agent
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null ||
  launchctl load "$PLIST" 2>/dev/null ||
  die "Could not load the launch agent. Try: launchctl bootstrap gui/\$(id -u) $PLIST"
say "Scheduled."

step "Setting a wallpaper now"
if "$BIN" -f; then
  say ""
  say "Done. The wallpaper changes every $INTERVAL_RAW from now on."
else
  say ""
  say "Setup is complete, but that first run failed — see the output above."
  say "If macOS asked about controlling System Events, allow it under"
  say "System Settings > Privacy & Security > Automation, then run: $BIN -f"
fi

cat <<EOF

Handy commands
  $BIN -f          change the wallpaper now
  $BIN -l          which sources are ready
  tail -f $LOG     the log
  $SELF_CMD
      change the interval, keys or tags
  $SELF_CMD --uninstall
      stop the automatic changes
EOF
