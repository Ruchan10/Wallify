#!/usr/bin/env bash
#
# linux.sh — one-shot setup for the Wallify desktop wallpaper changer on Linux.
#
# Asks for the change interval, your API keys and your tags, then installs
# the script, writes the config and schedules it with a systemd user timer
# (falling back to cron where systemd isn't available).
#
# Usage, from a clone of the repo:
#   ./linux.sh              set up (safe to re-run; answers default to what is
#                           already configured)
#   ./linux.sh --uninstall  remove the schedule, keep the wallpapers
#
# Or without cloning anything:
#   bash <(curl -sSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/linux.sh)

set -u -o pipefail

REPO_RAW="https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/wallify-desktop.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallify"
CONFIG="$CONFIG_DIR/config"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE="$UNIT_DIR/wallify.service"
TIMER="$UNIT_DIR/wallify.timer"
CRON_TAG="# wallify-desktop"
LOG="$HOME/.cache/wallify.log"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# How to run this installer again. When it is run straight from the web there
# is no file on disk to point people back at, so repeat the one-liner instead.
case "${BASH_SOURCE[0]}" in
  /dev/fd/*|/proc/*|"") SELF_CMD="bash <(curl -sSL $REPO_RAW/linux.sh)" ;;
  *)                    SELF_CMD="$HERE/linux.sh" ;;
esac

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "$(uname -s)" == Linux ]] || die "This is the Linux installer. On macOS run mac.sh instead."

have_systemd() { have systemctl && systemctl --user show-environment >/dev/null 2>&1; }

remove_cron() {
  have crontab || return 0
  crontab -l 2>/dev/null | grep -v -F "$CRON_TAG" | crontab - 2>/dev/null
  return 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
  if have systemctl; then
    systemctl --user disable --now wallify.timer 2>/dev/null
    rm -f "$TIMER" "$SERVICE"
    systemctl --user daemon-reload 2>/dev/null
  fi
  remove_cron
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
if [[ -f "$TIMER" ]]; then
  OLD_INTERVAL=$(sed -n 's/^OnUnitActiveSec=\([0-9]*\)min$/\1m/p' "$TIMER" | head -n1)
fi

step "How often should the wallpaper change?"
say "Examples: 45m, 4h, 1d"
while :; do
  ask INTERVAL_RAW "Interval" "${OLD_INTERVAL:-4h}"
  INTERVAL_MINUTES=$(parse_interval "$INTERVAL_RAW") && break
  say "  Didn't understand '$INTERVAL_RAW'. Try a number of minutes, or 4h."
done

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
  say "Missing: ${missing[*]}"
  if   have apt-get; then install_cmd="sudo apt-get install -y ${missing[*]}"
  elif have dnf;     then install_cmd="sudo dnf install -y ${missing[*]}"
  elif have pacman;  then install_cmd="sudo pacman -S --needed ${missing[*]}"
  elif have zypper;  then install_cmd="sudo zypper install -y ${missing[*]}"
  elif have apk;     then install_cmd="sudo apk add ${missing[*]}"
  else install_cmd=""
  fi
  [[ -n "$install_cmd" ]] || die "Install ${missing[*]} with your package manager, then run this again."
  ask RUN_INSTALL "Run '$install_cmd'? (y/n)" "y"
  case "$RUN_INSTALL" in
    [Yy]*) eval "$install_cmd" || die "Install failed. Run it yourself, then try again." ;;
    *) die "Install ${missing[*]} first: $install_cmd" ;;
  esac
fi
have magick || have convert || say "ImageMagick not found — images are used at their original size."
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
  printf '# Wallify desktop config — written by linux.sh on %s\n' "$(date)"
  printf '# Re-run linux.sh to change these, or edit them here.\n\n'
  printf 'UNSPLASH_ACCESS_KEY="%s"\n' "$UNSPLASH_ACCESS_KEY"
  printf 'PEXELS_API_KEY="%s"\n'      "$PEXELS_API_KEY"
  printf 'PIXABAY_API_KEY="%s"\n'     "$PIXABAY_API_KEY"
  printf 'WALLHAVEN_API_KEY="%s"\n'   "$WALLHAVEN_API_KEY"
  printf 'NASA_API_KEY="%s"\n\n'      "$NASA_API_KEY"
  printf 'SOURCES="%s"\n'             "${SOURCES:-wallhaven unsplash pexels pixabay openverse bing nasa picsum}"
  printf 'REDDIT_SUBREDDITS="%s"\n'   "${REDDIT_SUBREDDITS:-wallpaper wallpapers EarthPorn spaceporn}"
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
  printf 'WALLIFY_DESKTOP="%s"\n'     "${WALLIFY_DESKTOP:-}"
  printf 'POST_SET_HOOK="%s"\n'       "${POST_SET_HOOK:-}"
} > "$CONFIG"
chmod 600 "$CONFIG"
say "$CONFIG"

step "Scheduling it every $INTERVAL_RAW ($INTERVAL_MINUTES min)"
SCHEDULE_DESC="every $INTERVAL_RAW"
if have_systemd; then
  mkdir -p "$UNIT_DIR"
  cat > "$SERVICE" <<UNITEOF
[Unit]
Description=Wallify wallpaper changer

[Service]
Type=oneshot
ExecStart=$BIN
UNITEOF
  cat > "$TIMER" <<UNITEOF
[Unit]
Description=Change the wallpaper every $INTERVAL_RAW

[Timer]
OnStartupSec=1min
OnUnitActiveSec=${INTERVAL_MINUTES}min
Persistent=true

[Install]
WantedBy=timers.target
UNITEOF
  remove_cron   # in case an earlier run used the cron fallback
  systemctl --user daemon-reload || die "systemctl --user daemon-reload failed"
  systemctl --user enable --now wallify.timer || die "Could not enable wallify.timer"
  # On a re-run the timer is already active, and enable --now leaves it alone —
  # restart it so a changed interval takes effect now rather than next login.
  systemctl --user restart wallify.timer 2>/dev/null
  SCHEDULER=systemd
  say "systemd user timer enabled."
  # A timer started from a TTY can outlive your login without this.
  if ! loginctl show-user "$(id -un)" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    say "Tip: to keep it running when you're logged out: sudo loginctl enable-linger $(id -un)"
  fi
else
  have crontab || die "Neither systemd nor cron is available. Schedule $BIN yourself."
  mkdir -p "$(dirname "$LOG")"
  # In case an earlier run scheduled a timer back when systemd was reachable.
  if have systemctl; then
    systemctl --user disable --now wallify.timer 2>/dev/null
  fi
  # cron only does fixed clock times, so anything that isn't a whole number of
  # minutes under an hour, or of hours under a day, is rounded to the nearest hour.
  if (( INTERVAL_MINUTES < 60 )); then
    schedule="*/$INTERVAL_MINUTES * * * *"
  else
    hours=$(( (INTERVAL_MINUTES + 30) / 60 ))
    if (( hours >= 24 )); then
      schedule="0 3 * * *"
      SCHEDULE_DESC="once a day at 03:00"
    else
      schedule="0 */$hours * * *"
      (( hours * 60 == INTERVAL_MINUTES )) || SCHEDULE_DESC="every ${hours}h"
    fi
    [[ "$SCHEDULE_DESC" == "every $INTERVAL_RAW" ]] ||
      say "cron can't do every $INTERVAL_RAW exactly — using $SCHEDULE_DESC."
  fi
  { crontab -l 2>/dev/null | grep -v -F "$CRON_TAG"
    printf '%s %s >> %s 2>&1 %s\n' "$schedule" "$BIN" "$LOG" "$CRON_TAG"
  } | crontab - || die "Could not write the crontab"
  SCHEDULER=cron
  say "cron entry added."
fi

# Wayland compositors don't hand their session to systemd by themselves.
case "$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')" in
  *sway*|*hyprland*|*i3*)
    say ""
    say "You're on sway/Hyprland/i3 — add this to your compositor config so the"
    say "timer can reach your display:"
    say "  # sway / i3"
    say "  exec systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP"
    say "  # hyprland"
    say "  exec-once = dbus-update-activation-environment --systemd --all"
    ;;
esac

step "Setting a wallpaper now"
if "$BIN" -f; then
  say ""
  say "Done. The wallpaper changes $SCHEDULE_DESC from now on."
else
  say ""
  say "Setup is complete, but that first run failed — see the output above."
  say "If it couldn't detect your desktop, set WALLIFY_DESKTOP in $CONFIG."
fi

cat <<EOF

Handy commands
  $BIN -f          change the wallpaper now
  $BIN -l          which sources are ready
EOF
if [[ "$SCHEDULER" == systemd ]]; then
  cat <<EOF
  systemctl --user list-timers wallify.timer   when it next runs
  journalctl --user -u wallify.service         the log
EOF
else
  cat <<EOF
  crontab -l                                   the schedule
  tail -f $LOG                                 the log
EOF
fi
cat <<EOF
  $SELF_CMD
      change the interval, keys or tags
  $SELF_CMD --uninstall
      stop the automatic changes
EOF
