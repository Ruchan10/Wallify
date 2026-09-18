# Wallify ☁️📱

A wallpaper app for **Android**, plus a script that changes your **macOS / Linux**
desktop wallpaper on a schedule.

<a href="https://www.buymeacoffee.com/rk10" target="_blank"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&slug=rk10&button_colour=FFDD00&font_colour=000000&outline_colour=000000&coffee_colour=ffffff" height="40" /></a>

<img src="https://raw.githubusercontent.com/Ruchan10/Wallify/main/assets/screenshots/flutter_01.png" width="45%">

## Phone

Download the latest APK from [Releases](https://github.com/Ruchan10/Wallify/releases) and install it.

- Wallpapers from Wallhaven, Unsplash, Pexels, Pixabay and Lorem Picsum
- Automatic changes on a schedule, or when you plug in to charge
- Lock screen wallpapers, favorites, offline mode and home screen widgets
- API keys are entered in Settings

## Desktop

One command. It asks three questions — how often to change the wallpaper, your
API keys, and your tags — then installs and schedules everything.

**macOS**

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/mac.sh)
```

**Linux**

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/linux.sh)
```

That's it. The wallpaper changes on your chosen interval from then on
(launchd on macOS, a systemd user timer on Linux).

Run the same command again any time to change the interval, keys or tags — your
current answers come back as the defaults. To stop the automatic changes, add
`--uninstall`:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Ruchan10/Wallify/main/desktop/mac.sh) --uninstall
```

Prefer to read the script first? Clone the repo and run
[`desktop/mac.sh`](desktop/mac.sh) or [`desktop/linux.sh`](desktop/linux.sh)
directly — same thing.

### After setup

```bash
~/.local/bin/wallify-desktop.sh -f    # change the wallpaper now
~/.local/bin/wallify-desktop.sh -l    # which sources are ready
```

Settings live in `~/.config/wallify/config` if you'd rather edit them by hand;
every option is explained in [`desktop/config.example`](desktop/config.example).

### Sources

No API key at all still gives you five sources.

| Source | API key | Uses your tags |
| --- | --- | --- |
| [Wallhaven](https://wallhaven.cc/settings/account) | Optional | ✅ |
| [Unsplash](https://unsplash.com/oauth/applications) | Required | ✅ |
| [Pexels](https://www.pexels.com/api/) | Required | ✅ |
| [Pixabay](https://pixabay.com/api/docs/) | Required | ✅ |
| Openverse | None | ✅ |
| Reddit | None | ✅ (off by default — Reddit often blocks it) |
| Bing image of the day | None | ❌ |
| [NASA](https://api.nasa.gov) picture of the day | Optional | ❌ |
| Lorem Picsum | None | ❌ |

### Desktop support

Wallpapers work on macOS, GNOME, KDE, Cinnamon, MATE, XFCE, LXQt, Hyprland,
Sway and plain X11 window managers (via `feh`, `xwallpaper` or `nitrogen`).

Lock screens follow automatically on macOS, GNOME, KDE, Cinnamon, Hyprland and
Sway. Elsewhere, point your lock screen at `~/Pictures/Wallpapers/current.jpg` —
a symlink the script updates after every change:

```ini
# ~/.config/hypr/hyprlock.conf
background {
    path = ~/Pictures/Wallpapers/current.jpg
}
```

If your desktop is detected wrongly, set `WALLIFY_DESKTOP` in
`~/.config/wallify/config` to `gnome`, `kde`, `cinnamon`, `mate`, `xfce`,
`lxqt`, `hyprland` or `sway`.

## Build the app yourself

```bash
git clone https://github.com/Ruchan10/Wallify.git
cd Wallify
flutter pub get
flutter run
```

## 🤝 Contributing

Issues and pull requests are welcome.

## 📝 License

MIT
