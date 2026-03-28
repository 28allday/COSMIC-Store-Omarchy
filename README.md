# COSMIC Store - Omarchy

A graphical Flatpak app store for [Omarchy](https://omarchy.com) (Arch Linux + Hyprland), powered by System76's [COSMIC Store](https://github.com/pop-os/cosmic-store).

Browse and install thousands of Flatpak applications through a clean, modern GUI — with full Hyprland integration so installed apps appear in your app launcher.

## Requirements

- **OS**: [Omarchy](https://omarchy.com) (Arch Linux)
- **Compositor**: Hyprland
- **AUR Helper**: yay or paru (Omarchy ships with yay)

## Quick Start

```bash
git clone https://github.com/28allday/COSMIC-Store-Omarchy.git
cd COSMIC-Store-Omarchy
chmod +x cosmic.sh
./cosmic.sh
```

After installation, **log out and back in** so the environment variables take effect, then search for "COSMIC Store" in your app launcher.

## What It Does

### 1. Installs Dependencies

| Package | Purpose |
|---------|---------|
| `flatpak` | Sandboxed app distribution system (like Snap but open) |
| `xdg-desktop-portal` | D-Bus bridge between sandboxed apps and the desktop |
| `xdg-desktop-portal-gtk` | GTK fallback portal for file dialogs |
| `xdg-desktop-portal-hyprland` | Hyprland-specific portal (screen sharing, window picking) |
| `desktop-file-utils` | App menu integration tools |
| `base-devel`, `git` | Build tools for compiling COSMIC Store from AUR |

### 2. Configures Flathub

Adds the [Flathub](https://flathub.org) repository at both system and user level, giving you access to thousands of applications.

### 3. Installs COSMIC Store from AUR

Builds and installs `cosmic-store-git` — System76's app store built with the COSMIC toolkit. It provides a graphical interface for browsing, installing, and managing Flatpak apps.

### 4. Creates Hyprland Wrapper

COSMIC Store needs to know it's running under Hyprland to use the correct desktop portal. The wrapper script sets `XDG_CURRENT_DESKTOP=Hyprland` before launching the store.

### 5. Makes Flatpak Apps Visible in Launcher

Flatpak installs `.desktop` files in non-standard locations. The script:
- Adds Flatpak export directories to `XDG_DATA_DIRS`
- Sets environment variables in both systemd and Hyprland config
- Symlinks Flatpak `.desktop` files into `~/.local/share/applications/`

This ensures installed Flatpak apps appear in Walker/Elephant (Omarchy's app launchers).

### 6. Restarts Portal Services

Restarts the XDG desktop portal daemons so they pick up the new Hyprland configuration immediately.

## Files Created

| Path | Purpose |
|------|---------|
| `/usr/local/bin/cosmic-store-hypr` | Wrapper script (sets Hyprland environment) |
| `~/.local/share/applications/com.system76.CosmicStore.desktop` | User desktop entry |
| `~/.config/environment.d/flatpak.conf` | Flatpak environment variables |

## Usage

### Opening COSMIC Store

Search for **"COSMIC Store"** in your app launcher, or run:

```bash
cosmic-store-hypr
```

### Installing Apps via Command Line

```bash
# Search for an app
flatpak search firefox

# Install an app
flatpak install flathub org.mozilla.firefox

# Run an app
flatpak run org.mozilla.firefox

# List installed apps
flatpak list
```

### Making New Flatpak Apps Appear in Launcher

After installing a Flatpak app via the command line, you may need to symlink its desktop file:

```bash
# Symlink all Flatpak desktop files
for d in ~/.local/share/flatpak/exports/share/applications /var/lib/flatpak/exports/share/applications; do
  [ -d "$d" ] && find "$d" -maxdepth 1 -name '*.desktop' -exec ln -sf {} ~/.local/share/applications/ \;
done
```

Apps installed through COSMIC Store should appear automatically.

## Troubleshooting

### COSMIC Store can't launch installed apps

Make sure the wrapper is being used:
```bash
grep "Exec" ~/.local/share/applications/com.system76.CosmicStore.desktop
```
Should show: `Exec=/usr/local/bin/cosmic-store-hypr`

### Flatpak apps don't appear in app launcher

1. Log out and back in (environment variables need a session restart)
2. Check XDG_DATA_DIRS includes Flatpak paths:
   ```bash
   echo $XDG_DATA_DIRS | tr ':' '\n' | grep flatpak
   ```
3. Re-run the symlink step:
   ```bash
   for d in ~/.local/share/flatpak/exports/share/applications /var/lib/flatpak/exports/share/applications; do
     [ -d "$d" ] && find "$d" -maxdepth 1 -name '*.desktop' -exec ln -sf {} ~/.local/share/applications/ \;
   done
   ```

### COSMIC Store won't build from AUR

- Make sure `base-devel` and `git` are installed
- Try rebuilding yay first: `cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si`
- Check if Rust is installed (COSMIC is written in Rust): `pacman -S rustup && rustup default stable`

## Uninstalling

```bash
# Remove COSMIC Store
yay -Rns cosmic-store-git

# Remove wrapper and desktop entry
sudo rm -f /usr/local/bin/cosmic-store-hypr
rm -f ~/.local/share/applications/com.system76.CosmicStore.desktop

# Remove environment config
rm -f ~/.config/environment.d/flatpak.conf

# Optionally remove Flatpak entirely
sudo pacman -Rns flatpak

# Log out and back in to apply changes
```

## Credits

- [Omarchy](https://omarchy.com) - The Arch Linux distribution this was built for
- [System76](https://system76.com/) - COSMIC Store and desktop environment
- [Flatpak](https://flatpak.org/) - Sandboxed application framework
- [Flathub](https://flathub.org/) - Flatpak app repository
- [Hyprland](https://hyprland.org/) - Wayland compositor

## License

This project is provided as-is for the Omarchy community.
