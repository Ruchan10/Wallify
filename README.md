# Wallify ☁️📱

A smart wallpaper app built with **Flutter**, featuring automatic wallpaper updates, charging event triggers, and a rich set of customization options.

---

## 🚀 Features

- 🖼️ Browse & set wallpapers from Wallhaven, Unsplash, Pexels, Pixabay and Lorem Picsum
- 🖥️ Companion [desktop script](desktop/wallify-desktop.sh) for macOS & Linux (setup guide below)
- ⚡ Automatic wallpaper updates with granular scheduling (days + time range)
- 🔌 Charging event listener to trigger wallpaper changes
- 📱 Lock screen wallpaper support via dual wallpaper setup
- 🔔 Wallpaper change notification with "Try Another" quick action
- 🆎 Search autocomplete with popular & user tag suggestions
- 👆 Long-press context menu (Copy URL, Download, Toggle Favorite)
- ✨ Crossfade animation on wallpaper set
- 🎨 Dynamic Monet theming on home screen widgets
- 📶 Offline mode with connectivity-aware UI fallback
- 📟 Home screen widgets (Quick Toggle, Stats, Schedule) with auto-refresh
- 🧩 Monochrome adaptive app icon
- 🔑 All API keys configurable via Settings UI

---

## Screenshots

| <img src="https://raw.githubusercontent.com/Ruchan10/Wallify/main/assets/screenshots/flutter_01.png" width="45%"> |

## Try the app

1. Navigate to the [Releases](https://github.com/Ruchan10/Wallify/releases) section of this repository.
2. Download the latest APK.
3. Install the APK on your Android device to explore the app.

## 🖥️ Desktop auto wallpaper changer (macOS & Linux)

[`desktop/wallify-desktop.sh`](desktop/wallify-desktop.sh) brings Wallify to your computer. Each run it:

- picks a random source and tag, and tries another source if one fails
- downloads the image and crops it to your screen size (with ImageMagick)
- sets the desktop wallpaper, plus the **lock screen** on Linux desktops that support it
- keeps only the latest `KEEP_WALLPAPERS` downloads, so the folder doesn't grow forever
- can skip runs while on battery (`ONLY_WHEN_CHARGING=true`)

API keys live in a config file, never in the script.

### Sources

| Source | API key | Uses tags | Notes |
| --- | --- | --- | --- |
| `wallhaven` | Optional ([get key](https://wallhaven.cc/settings/account)) | ✅ | SFW only, landscape, at least your resolution |
| `unsplash` | Required ([get key](https://unsplash.com/oauth/applications)) | ✅ | Use the app's *Access Key*. Cropped server-side to your screen |
| `pexels` | Required ([get key](https://www.pexels.com/api/)) | ✅ | Cropped server-side to your screen |
| `pixabay` | Required ([get key](https://pixabay.com/api/docs/)) | ✅ | Max 1280px wide unless your account has full API access |
| `openverse` | None | ✅ | Openly licensed images (Flickr, Wikimedia, …) |
| `reddit` | None | ✅ | Searches `REDDIT_SUBREDDITS`. Not enabled by default because Reddit often blocks requests without a logged-in session |
| `bing` | None | ❌ | Bing image of the day (last 8 days, UHD) |
| `nasa` | Optional ([get key](https://api.nasa.gov)) | ❌ | Astronomy Picture of the Day. `DEMO_KEY` is heavily rate limited |
| `picsum` | None | ❌ | Random Lorem Picsum photo at your exact resolution |

Sources that need a key are skipped until you add one. With no keys at all you still get five sources by default.

### 1. Install dependencies

```bash
# macOS
brew install jq imagemagick
brew install wallpaper            # optional, sets every screen more reliably than AppleScript

# Debian / Ubuntu
sudo apt install curl jq imagemagick file

# Fedora
sudo dnf install curl jq ImageMagick file

# Arch
sudo pacman -S curl jq imagemagick file
```

ImageMagick is optional. Without it, images are used at their original size.

### 2. Install the script and config

```bash
mkdir -p ~/.local/bin ~/.config/wallify
curl -fsSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/wallify-desktop.sh -o ~/.local/bin/wallify-desktop.sh
curl -fsSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/config.example -o ~/.config/wallify/config
chmod +x ~/.local/bin/wallify-desktop.sh
chmod 600 ~/.config/wallify/config   # it holds your API keys
```

### 3. Add your API keys and preferences

Edit `~/.config/wallify/config`:

```bash
UNSPLASH_ACCESS_KEY="your-unsplash-access-key"
PEXELS_API_KEY="your-pexels-key"
PIXABAY_API_KEY="your-pixabay-key"

SOURCES="wallhaven unsplash pexels pixabay openverse bing nasa picsum"
TAGS=("nature" "space" "minimal" "cyberpunk" "linux")

RESOLUTION="auto"          # or "2560x1440"
ONLY_WHEN_CHARGING=true
KEEP_WALLPAPERS=30
SET_LOCK_SCREEN=true
```

Every option is described in [`config.example`](desktop/config.example).

### 4. Test it

```bash
wallify-desktop.sh -l                   # which sources are ready
wallify-desktop.sh -f                   # change now, even on battery
wallify-desktop.sh -f -s bing           # a specific source
wallify-desktop.sh -f -s wallhaven -t "mountains"
```

### 5. Run it automatically

#### macOS: launchd (every 4 hours)

Create `~/Library/LaunchAgents/com.wallify.desktop.plist`, replacing `YOUR_USER` with your username (launchd does not expand `~`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.wallify.desktop</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOUR_USER/.local/bin/wallify-desktop.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>14400</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/YOUR_USER/Library/Logs/wallify.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USER/Library/Logs/wallify.log</string>
</dict>
</plist>
```

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.wallify.desktop.plist   # enable
launchctl kickstart -k gui/$(id -u)/com.wallify.desktop                              # run now
launchctl bootout gui/$(id -u)/com.wallify.desktop                                   # disable
```

> **Tip:** with `ONLY_WHEN_CHARGING=true`, a 4-hour run that lands while you're on battery is skipped. To change the wallpaper soon after you plug in instead, set `StartInterval` to `1800` and `MIN_INTERVAL_MINUTES=240` in the config.

If you don't install `wallpaper`, macOS asks the first time for permission to control **System Events**. Allow it under *System Settings → Privacy & Security → Automation*.

#### Linux: systemd user timer (every 4 hours)

`~/.config/systemd/user/wallify.service`

```ini
[Unit]
Description=Wallify wallpaper changer

[Service]
Type=oneshot
ExecStart=%h/.local/bin/wallify-desktop.sh
```

`~/.config/systemd/user/wallify.timer`

```ini
[Unit]
Description=Change wallpaper every 4 hours

[Timer]
OnCalendar=*-*-* 00/4:00:00
OnStartupSec=1min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now wallify.timer
systemctl --user start wallify.service    # run now
journalctl --user -u wallify.service      # logs
```

GNOME, KDE and Cinnamon pass their session environment to systemd automatically. On Sway, Hyprland or i3, add this to your compositor/WM config so the timer can reach your display:

```bash
# sway / i3
exec systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
# hyprland
exec-once = dbus-update-activation-environment --systemd --all
```

#### Linux: cron (alternative)

```bash
crontab -e
0 */4 * * * $HOME/.local/bin/wallify-desktop.sh >> $HOME/.cache/wallify.log 2>&1
```

The script fills in `DBUS_SESSION_BUS_ADDRESS`, `DISPLAY`, `SWAYSOCK` and `HYPRLAND_INSTANCE_SIGNATURE` when cron doesn't provide them.

### Lock screen support

| Desktop | Wallpaper | Lock screen |
| --- | --- | --- |
| macOS | ✅ `wallpaper` CLI or AppleScript | ✅ macOS shows the desktop wallpaper on the lock screen, so it changes too. There is no separate lock screen API |
| GNOME / Ubuntu / Budgie | ✅ `gsettings` | ✅ Sets `org.gnome.desktop.screensaver picture-uri`. GNOME 42+ shows a blurred copy of the desktop wallpaper, so it follows automatically |
| KDE Plasma 5/6 | ✅ `plasma-apply-wallpaperimage` | ✅ Updates `kscreenlockerrc` |
| Cinnamon | ✅ `gsettings` | ✅ Uses the desktop wallpaper |
| MATE | ✅ `gsettings` | ➖ Depends on your screensaver theme |
| XFCE | ✅ `xfconf-query` | ➖ light-locker / LightDM greeter backgrounds are system-wide, so use `POST_SET_HOOK` |
| LXQt | ✅ `pcmanfm-qt` | ➖ |
| Hyprland | ✅ `swww` or `hyprpaper` | ✅ Point hyprlock at `current.jpg` (below) |
| Sway | ✅ `swaymsg` | ✅ Point swaylock at `current.jpg` (below) |
| i3 / other X11 WMs | ✅ `feh`, `xwallpaper` or `nitrogen` | ✅ Refreshes `betterlockscreen` if installed, or use `POST_SET_HOOK` |

After each change the script updates the `~/Pictures/Wallpapers/current.jpg` symlink, so lock screens that read an image file always show the latest wallpaper:

```ini
# ~/.config/hypr/hyprlock.conf
background {
    path = ~/Pictures/Wallpapers/current.jpg
}
```

```ini
# ~/.config/swaylock/config (use an absolute path)
image=/home/YOUR_USER/Pictures/Wallpapers/current.jpg
scaling=fill
```

If auto-detection picks the wrong desktop, set `WALLIFY_DESKTOP` (`gnome`, `kde`, `cinnamon`, `mate`, `xfce`, `lxqt`, `hyprland` or `sway`) in the config.

## ☕ Support

If you like my work, consider buying me a coffee:
<a href="https://www.buymeacoffee.com/rk10" target="_blank"> <img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&slug=rk10&button_colour=FFDD00&font_colour=000000&outline_colour=000000&coffee_colour=ffffff" /> </a>

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!
Feel free to open a pull request.

## 📦 Installation

1. Clone this repo:
   ```bash
   git clone https://github.com/Ruchan10/wallify.git
   cd wallify
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## 📝 License

MIT License
