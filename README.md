# DMS Package Updates

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) widget that checks for pending **DNF** and **Flatpak** updates and lets you run them directly from the bar.

![Screenshot](https://raw.githubusercontent.com/rahulmysore23/dms-pkg-update/main/screenshot.png)

## Features

- Shows total pending update count in the bar pill
- Lists available DNF package updates with version numbers
- Lists available Flatpak app updates with remote origin
- **Update DNF** button — opens a terminal and runs `sudo dnf upgrade -y`
- **Update Flatpak** button — opens a terminal and runs `flatpak update -y`
- Configurable refresh interval
- Configurable terminal application

## Installation

### From Plugin Registry (Recommended)

```bash
dms plugins install pkgUpdate
# or use the Plugins tab in DMS Settings
```

### Manual

```bash
cp -r pkgUpdate ~/.config/DankMaterialShell/plugins/
```

Then enable the widget in the DMS Plugins tab and add it to DankBar.

## Configuration

| Setting | Default | Description |
|---|---|---|
| Terminal Application | `alacritty` | Terminal used to run updates (`kitty`, `foot`, `ghostty`, etc.) |
| Refresh Interval | `60` min | How often to check for updates (5–240 min) |
| Check on Startup | `true` | Run a check immediately when DMS starts |
| Max List Height | `180` px | Maximum height for each update list before scrolling |
| Show Flatpak Updates | `true` | Toggle Flatpak section on/off |
| Hide When Up-to-Date | `false` | Hide the bar widget when no updates are available |

## Requirements

- `dnf` (standard on Fedora/RHEL-based systems)
- `flatpak` (optional, can be disabled in settings)
- A terminal emulator that accepts `-e` to run a command

## License

MIT

