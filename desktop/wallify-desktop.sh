#!/usr/bin/env bash
#
# wallify-desktop.sh — random wallpaper changer for macOS and Linux.
#
# Usage: wallify-desktop.sh [-f] [-s source] [-t tag] [-l] [-h]
#   -f  force: ignore ONLY_WHEN_CHARGING and MIN_INTERVAL_MINUTES
#   -s  use only this source (e.g. wallhaven)
#   -t  use this tag / search term instead of a random one
#   -l  list sources and whether they are ready, then exit
#
# Settings: ${XDG_CONFIG_HOME:-~/.config}/wallify/config (see config.example)
# Requires: curl, jq. Recommended: ImageMagick (crops to your screen size).

set -o pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

CONFIG_FILE="${WALLIFY_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/wallify/config}"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && . "$CONFIG_FILE"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
KEEP_WALLPAPERS="${KEEP_WALLPAPERS:-30}"
RESOLUTION="${RESOLUTION:-auto}"
ONLY_WHEN_CHARGING="${ONLY_WHEN_CHARGING:-false}"
MIN_INTERVAL_MINUTES="${MIN_INTERVAL_MINUTES:-0}"
SET_LOCK_SCREEN="${SET_LOCK_SCREEN:-true}"
# reddit is opt-in: it often answers 403 to requests without a logged-in session.
SOURCES="${SOURCES:-wallhaven unsplash pexels pixabay openverse bing nasa picsum}"
REDDIT_SUBREDDITS="${REDDIT_SUBREDDITS:-wallpaper wallpapers EarthPorn spaceporn}"
BING_MARKET="${BING_MARKET:-en-US}"
NASA_API_KEY="${NASA_API_KEY:-DEMO_KEY}"
WALLIFY_DESKTOP="${WALLIFY_DESKTOP:-}"
POST_SET_HOOK="${POST_SET_HOOK:-}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-4}"

if [[ ${#TAGS[@]} -eq 0 ]]; then
  TAGS=("cool" "forest" "amoled" "beach" "office" "sunset" "code" "open source" "outdoor"
        "games" "music" "grass" "universe" "technology" "black" "4K" "dark" "night" "space"
        "anime" "landscape" "cyberpunk" "nature" "computer" "linux" "minimal" "minimalist"
        "terminal" "developer" "star wars" "mountains" "city" "ocean" "abstract")
fi

ALL_SOURCES="wallhaven unsplash pexels pixabay openverse reddit bing nasa picsum"
STAMP_FILE="$WALLPAPER_DIR/.wallify-last-change"
OS=$(uname -s)

log()   { printf '[wallify] %s\n' "$*"; }
die()   { log "$*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
slug()  { lower "$1" | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//'; }
urlenc() { jq -rn --arg v "$1" '$v|@uri'; }
lock_enabled() { [[ "$SET_LOCK_SCREEN" == true ]]; }

http() {
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 90 \
    -A "Wallify-Desktop/1.0 (+https://github.com/Ruchan10/Wallify)" "$@"
}

# Prints one of its arguments at random.
pick() {
  (( $# )) || return 1
  local i=$(( RANDOM % $# + 1 ))
  printf '%s' "${!i}"
}

# ---------------------------------------------------------------------------
# Sources: each prints a single image URL, or nothing on failure.
# Available globals: TAG, TAG_Q (url-encoded), WIDTH, HEIGHT.
# ---------------------------------------------------------------------------

source_ready() {
  case "$1" in
    unsplash) [[ -n "$UNSPLASH_ACCESS_KEY" ]] ;;
    pexels)   [[ -n "$PEXELS_API_KEY" ]] ;;
    pixabay)  [[ -n "$PIXABAY_API_KEY" ]] ;;
    wallhaven|openverse|reddit|bing|nasa|picsum) return 0 ;;
    *) return 1 ;;
  esac
}

src_wallhaven() {
  local url="https://wallhaven.cc/api/v1/search?q=${TAG_Q}&categories=110&purity=100&atleast=${WIDTH}x${HEIGHT}&ratios=landscape&sorting=random"
  [[ -n "$WALLHAVEN_API_KEY" ]] && url+="&apikey=${WALLHAVEN_API_KEY}"
  http "$url" | jq -r '.data[0].path // empty'
}

src_unsplash() {
  local json ping
  json=$(http -H "Accept-Version: v1" -H "Authorization: Client-ID ${UNSPLASH_ACCESS_KEY}" \
    "https://api.unsplash.com/photos/random?query=${TAG_Q}&orientation=landscape&content_filter=high") || return 1
  # Unsplash API guidelines ask apps to hit download_location when a photo is used.
  ping=$(jq -r '.links.download_location // empty' <<<"$json")
  [[ -n "$ping" ]] && http -H "Authorization: Client-ID ${UNSPLASH_ACCESS_KEY}" "$ping" >/dev/null 2>&1
  jq -r --arg w "$WIDTH" --arg h "$HEIGHT" \
    '.urls.raw // empty | "\(.)&w=\($w)&h=\($h)&fit=crop&crop=entropy&fm=jpg&q=90"' <<<"$json"
}

src_pexels() {
  http -H "Authorization: ${PEXELS_API_KEY}" \
    "https://api.pexels.com/v1/search?query=${TAG_Q}&orientation=landscape&size=large&per_page=80" |
    jq -r --argjson r "$RANDOM" --arg w "$WIDTH" --arg h "$HEIGHT" \
      '.photos | if length > 0 then .[$r % length].src.original + "?auto=compress&cs=tinysrgb&fit=crop&w=\($w)&h=\($h)" else empty end'
}

src_pixabay() {
  local base url filter
  base="https://pixabay.com/api/?key=${PIXABAY_API_KEY}&q=${TAG_Q}&image_type=photo&orientation=horizontal&safesearch=true&per_page=200&order=$(pick popular latest)"
  # imageURL (full size) is only returned to accounts with full API access.
  filter='.hits | if length > 0 then .[$r % length] | (.imageURL // .largeImageURL) else empty end'
  url=$(http "${base}&min_width=${WIDTH}&min_height=${HEIGHT}" | jq -r --argjson r "$RANDOM" "$filter")
  # Few photos meet a large minimum size, so retry without it.
  [[ -z "$url" ]] && url=$(http "$base" | jq -r --argjson r "$RANDOM" "$filter")
  [[ -n "$url" ]] && printf '%s\n' "$url"
}

src_openverse() {
  http "https://api.openverse.org/v1/images/?q=${TAG_Q}&aspect_ratio=wide&size=large&mature=false&page_size=20" |
    jq -r --argjson r "$RANDOM" '.results | if length > 0 then .[$r % length].url else empty end'
}

src_reddit() {
  local sub
  # shellcheck disable=SC2086
  sub=$(pick $REDDIT_SUBREDDITS)
  http "https://www.reddit.com/r/${sub}/search.json?q=${TAG_Q}&restrict_sr=1&sort=top&t=year&limit=100" |
    jq -r --argjson r "$RANDOM" --argjson w "$WIDTH" '
      [.data.children[].data
        | select(.over_18 | not)
        | select(.url | test("\\.(jpe?g|png)$"; "i"))
        | select((.preview.images[0].source // {width: 0, height: 1}) as $s
                 | $s.width >= $s.height and $s.width >= ($w * 0.75))
        | .url]
      | if length > 0 then .[$r % length] else empty end'
}

src_bing() {
  http "https://www.bing.com/HPImageArchive.aspx?format=js&idx=$(( RANDOM % 8 ))&n=1&mkt=${BING_MARKET}" |
    jq -r '.images[0].urlbase // empty | "https://www.bing.com\(.)_UHD.jpg"'
}

src_nasa() {
  http "https://api.nasa.gov/planetary/apod?api_key=${NASA_API_KEY}&count=20" |
    jq -r --argjson r "$RANDOM" \
      '[.[] | select(.media_type == "image") | (.hdurl // .url)] | if length > 0 then .[$r % length] else empty end'
}

src_picsum() {
  printf 'https://picsum.photos/%s/%s.jpg?random=%s\n' "$WIDTH" "$HEIGHT" "$RANDOM"
}

# ---------------------------------------------------------------------------
# System helpers
# ---------------------------------------------------------------------------

on_ac_power() {
  if [[ "$OS" == Darwin ]]; then
    pmset -g batt | grep -q "AC Power"
    return
  fi
  local ps has_battery=false
  for ps in /sys/class/power_supply/*; do
    [[ -r "$ps/type" ]] || continue
    # Mice, headsets etc. report scope=Device; only system batteries matter.
    [[ "$(cat "$ps/scope" 2>/dev/null)" == Device ]] && continue
    case "$(cat "$ps/type")" in
      Mains|USB) [[ "$(cat "$ps/online" 2>/dev/null)" == 1 ]] && return 0 ;;
      Battery)
        has_battery=true
        case "$(cat "$ps/status" 2>/dev/null)" in Charging|Full) return 0 ;; esac ;;
    esac
  done
  # No battery means a desktop PC, which is always plugged in.
  [[ "$has_battery" == false ]]
}

detect_resolution() {
  local res=""
  if [[ "$OS" == Darwin ]]; then
    res=$(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Resolution:/ {print $2 "x" $4; exit}')
  elif have hyprctl && [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    res=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
  elif have swaymsg && [[ -n "$SWAYSOCK" ]]; then
    res=$(swaymsg -t get_outputs -r | jq -r '[.[] | select(.active)][0].current_mode | "\(.width)x\(.height)"')
  elif have xrandr && [[ -n "$DISPLAY" ]]; then
    res=$(xrandr --current 2>/dev/null | awk '/\*/ {print $1; exit}')
  fi
  [[ $res =~ ^[0-9]+x[0-9]+$ ]] || res="1920x1080"
  printf '%s' "$res"
}

# cron and systemd timers don't always inherit the graphical session's environment.
fill_session_env() {
  local run="/run/user/$(id -u)" found
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$run/bus}"
  [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" ]] && export DISPLAY=:0
  if [[ -z "$SWAYSOCK" ]]; then
    found=$(ls "$run"/sway-ipc.*.sock 2>/dev/null | head -n1)
    [[ -n "$found" ]] && export SWAYSOCK="$found"
  fi
  if [[ -z "$HYPRLAND_INSTANCE_SIGNATURE" && -d "$run/hypr" ]]; then
    found=$(ls -t "$run/hypr" 2>/dev/null | head -n1)
    [[ -n "$found" ]] && export HYPRLAND_INSTANCE_SIGNATURE="$found"
  fi
}

detect_desktop() {
  local d
  d=$(lower "${WALLIFY_DESKTOP:-${XDG_CURRENT_DESKTOP:-$DESKTOP_SESSION}}")
  if [[ -z "$d" ]]; then
    if   pgrep -x gnome-shell  >/dev/null; then d=gnome
    elif pgrep -x plasmashell  >/dev/null; then d=kde
    elif pgrep -x cinnamon     >/dev/null; then d=cinnamon
    elif pgrep -x mate-session >/dev/null; then d=mate
    elif pgrep -x xfdesktop    >/dev/null; then d=xfce
    elif pgrep -x Hyprland     >/dev/null; then d=hyprland
    elif pgrep -x sway         >/dev/null; then d=sway
    fi
  fi
  printf '%s' "$d"
}

is_image() {
  [[ -s "$1" ]] || return 1
  have file || return 0
  case "$(file -b --mime-type "$1")" in image/*) return 0 ;; *) return 1 ;; esac
}

# Crops to the screen size (when ImageMagick is installed) and moves the file into WALLPAPER_DIR.
finalize_image() {
  local tmp="$1" name out magick="" ext=jpg
  name="wallify_${2}_$(slug "$3")_$(date +%s)"
  if have magick; then magick=magick; elif have convert; then magick=convert; fi

  if [[ -n "$magick" ]]; then
    out="$WALLPAPER_DIR/$name.jpg"
    "$magick" "${tmp}[0]" -auto-orient -resize "${WIDTH}x${HEIGHT}^" -gravity center \
      -extent "${WIDTH}x${HEIGHT}" -quality 92 "$out" || return 1
    rm -f "$tmp"
  else
    if have file; then
      case "$(file -b --mime-type "$tmp")" in image/png) ext=png ;; image/webp) ext=webp ;; esac
    fi
    out="$WALLPAPER_DIR/$name.$ext"
    mv "$tmp" "$out" || return 1
  fi
  printf '%s' "$out"
}

prune_old() {
  (( KEEP_WALLPAPERS > 0 )) || return 0
  ls -1t "$WALLPAPER_DIR"/wallify_* 2>/dev/null | tail -n +$(( KEEP_WALLPAPERS + 1 )) |
    while IFS= read -r old; do rm -f "$old"; done
}

# ---------------------------------------------------------------------------
# Setters
# ---------------------------------------------------------------------------

set_macos() {
  local f="$1"
  # The macOS lock screen shows the desktop wallpaper, so there is nothing separate to set.
  if have wallpaper; then
    # The Swift CLI (brew) uses `wallpaper set <file>`; the older npm CLI uses `wallpaper <file>`.
    if wallpaper --help 2>&1 | grep -qE '^[[:space:]]+set([[:space:]]|$)'; then
      wallpaper set "$f"
    else
      wallpaper "$f"
    fi
  else
    osascript -e 'on run argv' \
      -e 'tell application "System Events" to tell every desktop to set picture to POSIX file (item 1 of argv)' \
      -e 'end run' "$f" >/dev/null
  fi
}

set_linux() {
  local f="$1" uri="file://$1" de kw
  de=$(detect_desktop)

  case "$de" in
    *gnome*|*ubuntu*|*unity*|*budgie*|*pantheon*|*pop*)
      gsettings set org.gnome.desktop.background picture-uri "$uri" || return 1
      gsettings set org.gnome.desktop.background picture-uri-dark "$uri" 2>/dev/null
      gsettings set org.gnome.desktop.background picture-options zoom
      if lock_enabled; then
        # Used by older GNOME and some distros; GNOME 42+ blurs the desktop wallpaper instead.
        gsettings set org.gnome.desktop.screensaver picture-uri "$uri" 2>/dev/null
      fi
      ;;
    *kde*|*plasma*)
      plasma-apply-wallpaperimage "$f" >/dev/null || return 1
      kw=$(command -v kwriteconfig6 || command -v kwriteconfig5)
      if lock_enabled && [[ -n "$kw" ]]; then
        "$kw" --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
        "$kw" --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "$uri"
        "$kw" --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "$uri"
      fi
      ;;
    *cinnamon*)
      gsettings set org.cinnamon.desktop.background picture-uri "$uri" || return 1
      gsettings set org.cinnamon.desktop.background picture-options zoom
      ;;
    *mate*)
      gsettings set org.mate.background picture-filename "$f" || return 1
      gsettings set org.mate.background picture-options zoom
      ;;
    *xfce*)
      local props p
      props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep 'last-image$')
      [[ -n "$props" ]] || return 1
      while IFS= read -r p; do
        xfconf-query -c xfce4-desktop -p "$p" -s "$f"
      done <<<"$props"
      ;;
    *lxqt*)
      pcmanfm-qt --set-wallpaper "$f" --wallpaper-mode=zoom || return 1
      ;;
    *hyprland*)
      if have swww; then
        swww img "$f" --transition-type fade >/dev/null || return 1
      elif have hyprctl; then
        hyprctl hyprpaper reload ",$f" >/dev/null || return 1
      else
        return 1
      fi
      ;;
    *sway*)
      swaymsg "output * bg \"$f\" fill" >/dev/null || return 1
      ;;
    *)
      if   have feh;        then feh --bg-fill "$f"
      elif have xwallpaper; then xwallpaper --zoom "$f"
      elif have nitrogen;   then nitrogen --set-zoom-fill --save "$f"
      else
        log "Unknown desktop '$de'. Set WALLIFY_DESKTOP or POST_SET_HOOK in $CONFIG_FILE"
        false
      fi || return 1
      ;;
  esac

  if lock_enabled && have betterlockscreen; then
    betterlockscreen -u "$f" >/dev/null 2>&1
  fi
  return 0
}

# ---------------------------------------------------------------------------

main() {
  local force=false only_source="" only_tag="" opt s
  while getopts "fs:t:lh" opt; do
    case "$opt" in
      f) force=true ;;
      s) only_source=$(lower "$OPTARG") ;;
      t) only_tag="$OPTARG" ;;
      l)
        for s in $ALL_SOURCES; do
          if source_ready "$s"; then echo "$s: ready"; else echo "$s: needs an API key"; fi
        done
        exit 0 ;;
      *) sed -n '3,12p' "$0"; exit 0 ;;
    esac
  done

  have curl || die "curl is required"
  have jq || die "jq is required (brew install jq / apt install jq)"
  [[ "$OS" == Linux ]] && fill_session_env

  if ! $force; then
    if [[ "$ONLY_WHEN_CHARGING" == true ]] && ! on_ac_power; then
      log "Not charging. Exiting."
      exit 0
    fi
    if (( MIN_INTERVAL_MINUTES > 0 )) && [[ -f "$STAMP_FILE" ]]; then
      local last age
      last=$(cat "$STAMP_FILE" 2>/dev/null)
      age=$(( ($(date +%s) - ${last:-0}) / 60 ))
      if (( age < MIN_INTERVAL_MINUTES )); then
        log "Last change was ${age}m ago (minimum ${MIN_INTERVAL_MINUTES}m). Exiting."
        exit 0
      fi
    fi
  fi

  mkdir -p "$WALLPAPER_DIR" || die "Cannot create $WALLPAPER_DIR"

  local res
  if [[ "$RESOLUTION" == auto ]]; then res=$(detect_resolution); else res="$RESOLUTION"; fi
  WIDTH=${res%x*}
  HEIGHT=${res#*x}

  local candidates=()
  if [[ -n "$only_source" ]]; then
    source_ready "$only_source" || die "Source '$only_source' is unknown or missing its API key"
    candidates=("$only_source")
  else
    for s in $(printf '%s\n' $SOURCES | awk -v seed="$RANDOM" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' | sort -n | cut -f2-); do
      source_ready "$s" && candidates+=("$s")
    done
  fi
  (( ${#candidates[@]} )) || die "No usable sources. Add API keys or edit SOURCES in $CONFIG_FILE"

  # Try sources in random order until one produces an image.
  local source url tmp file="" attempts=0
  for source in "${candidates[@]}"; do
    (( attempts >= MAX_ATTEMPTS )) && break
    attempts=$(( attempts + 1 ))

    TAG=${only_tag:-$(pick "${TAGS[@]}")}
    TAG_Q=$(urlenc "$TAG")
    log "Source: $source · Tag: $TAG · ${WIDTH}x${HEIGHT}"

    url=$("src_$source" | head -n1)
    if [[ -z "$url" || "$url" == null ]]; then
      log "No image from $source"
      continue
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/wallify.XXXXXX")
    if ! http -o "$tmp" "$url" || ! is_image "$tmp"; then
      log "Download from $source failed"
      rm -f "$tmp"
      continue
    fi

    if file=$(finalize_image "$tmp" "$source" "$TAG"); then
      break
    fi
    rm -f "$tmp"
    file=""
  done
  [[ -n "$file" ]] || die "Could not fetch a wallpaper after $attempts attempt(s)"

  if [[ "$OS" == Darwin ]]; then set_macos "$file"; else set_linux "$file"; fi ||
    die "Downloaded $file but failed to set it as wallpaper"

  # Stable path for lock screens that read an image file (swaylock, hyprlock, ...).
  ln -sfn "$file" "$WALLPAPER_DIR/current.jpg"
  date +%s > "$STAMP_FILE"

  if [[ -n "$POST_SET_HOOK" ]]; then
    # Unquoted on purpose so the hook may include arguments.
    # shellcheck disable=SC2086
    $POST_SET_HOOK "$file" || log "POST_SET_HOOK failed"
  fi

  prune_old
  log "Wallpaper set from $source using tag '$TAG': $file"
}

main "$@"
