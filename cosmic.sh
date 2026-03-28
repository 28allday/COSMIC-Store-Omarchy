#!/usr/bin/env bash
# ==============================================================================
# COSMIC Store Installer for Omarchy (Arch Linux + Hyprland)
#
# This script installs System76's COSMIC Store on Omarchy so you can browse
# and install Flatpak applications through a graphical app store — similar
# to GNOME Software or KDE Discover, but built with the COSMIC desktop toolkit.
#
# Why this script exists:
#   Omarchy uses Hyprland (a Wayland compositor), not COSMIC Desktop or GNOME.
#   The COSMIC Store doesn't natively know how to launch apps through Hyprland's
#   portal system. This script bridges that gap by:
#     1. Installing the COSMIC Store from AUR
#     2. Setting up Flatpak with the Flathub repository
#     3. Creating a wrapper that tells COSMIC Store to use Hyprland's portal
#     4. Configuring environment variables so Flatpak apps appear in the
#        Omarchy app launcher (Walker/Elephant)
#     5. Symlinking Flatpak .desktop files so they're discoverable
#
# The result: you get a full graphical app store that works seamlessly with
# Hyprland, and installed Flatpak apps show up in your app launcher.
# ==============================================================================

set -euo pipefail

echo "== COSMIC Store + Hyprland one-shot setup for Omarchy (Arch) =="

# Utility functions:
#   have() — checks if a command exists on the system
#   need() — ensures a pacman package is installed (installs it if missing)
#   append_if_missing() — adds a line to a file only if it's not already there
#     (prevents duplicate entries when running the script multiple times)
have(){ command -v "$1" >/dev/null 2>&1; }
need(){ pacman -Q "$1" >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm "$1"; }
append_if_missing(){
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"; touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# Sanity check — this script uses pacman, so it only works on Arch-based systems.
if ! have pacman; then echo "This script is for Arch/Arch-based systems."; exit 1; fi

# Install dependencies:
#   base-devel:                  Build tools needed to compile AUR packages
#   git:                         Cloning AUR repos
#   flatpak:                     The Flatpak package manager itself — sandboxed app
#                                distribution system used by COSMIC Store
#   xdg-desktop-portal:          D-Bus interface that lets sandboxed apps talk to the
#                                desktop (file pickers, notifications, screen sharing)
#   xdg-desktop-portal-gtk:      GTK fallback portal for dialogs
#   xdg-desktop-portal-hyprland: Hyprland-specific portal (screen sharing, window picking)
#   desktop-file-utils:          Provides update-desktop-database for app menu integration
sudo pacman -Sy --noconfirm
need base-devel
need git
need flatpak
need xdg-desktop-portal
need xdg-desktop-portal-gtk
need xdg-desktop-portal-hyprland
need desktop-file-utils

# Add the Flathub repository — this is the main app store for Flatpak with
# thousands of applications. We add it at both system level (available to all
# users) and user level (can install without sudo). --if-not-exists prevents
# errors if it's already configured.
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak  remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

# Install COSMIC Store from AUR. cosmic-store-git is the development version
# built from source. It's not in the official Arch repos because COSMIC is
# still in active development by System76.
#
# Tries yay first (Omarchy default), then paru, and falls back to a manual
# makepkg build if neither AUR helper is available.
if have yay; then
  yay -S --noconfirm cosmic-store-git
elif have paru; then
  paru -S --noconfirm cosmic-store-git
else
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  git -C "$tmp" clone https://aur.archlinux.org/cosmic-store-git.git
  cd "$tmp/cosmic-store-git"
  makepkg -si --noconfirm
fi

# Create a wrapper script that sets XDG_CURRENT_DESKTOP=Hyprland before
# launching COSMIC Store. Without this, COSMIC Store doesn't know it's
# running under Hyprland and can't use the Hyprland portal to launch
# installed apps. The portal is how sandboxed Flatpak apps open files,
# show notifications, and interact with the desktop environment.
sudo install -Dm755 /dev/stdin /usr/local/bin/cosmic-store-hypr <<'EOF'
#!/usr/bin/env bash
export XDG_CURRENT_DESKTOP=Hyprland
exec cosmic-store "$@"
EOF

# Create a user-level .desktop entry that overrides the system one. User
# entries in ~/.local/share/applications/ take priority over system entries
# in /usr/share/applications/. This ensures COSMIC Store always launches
# through our wrapper with the correct environment variables.
USR_DESKTOP="$HOME/.local/share/applications/com.system76.CosmicStore.desktop"
install -Dm644 /dev/stdin "$USR_DESKTOP" <<'EOF'
[Desktop Entry]
Name=COSMIC Store
Comment=Browse and install Flatpak apps
Exec=/usr/local/bin/cosmic-store-hypr
Icon=com.system76.CosmicStore
Terminal=false
Type=Application
Categories=System;PackageManager;
StartupNotify=true
EOF

# Configure environment variables so Flatpak apps are visible in the
# Omarchy app launcher (Walker/Elephant).
#
# The key is XDG_DATA_DIRS — this tells the desktop where to look for
# .desktop files. Flatpak installs its .desktop files in special export
# directories that aren't in the default search path. By adding them,
# the app launcher can discover and display Flatpak apps.
#
# We set this in TWO places for reliability:
#   1. ~/.config/environment.d/flatpak.conf — picked up by systemd user session
#   2. ~/.config/hypr/hyprland.conf — picked up by Hyprland directly
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/flatpak.conf" <<'EOF'
XDG_DATA_DIRS=%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share
XDG_CURRENT_DESKTOP=Hyprland
EOF

HYPR_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
append_if_missing "env = XDG_CURRENT_DESKTOP,Hyprland" "$HYPR_CFG"
append_if_missing "env = XDG_DATA_DIRS,$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share" "$HYPR_CFG"

# Belt and suspenders — symlink all Flatpak .desktop files directly into
# the user's applications directory. Even if XDG_DATA_DIRS isn't picked up
# correctly by every launcher, the symlinks ensure Flatpak apps are always
# discoverable. Covers both user installs (~/.local/share/flatpak/) and
# system installs (/var/lib/flatpak/).
mkdir -p "$HOME/.local/share/applications"
for d in "$HOME/.local/share/flatpak/exports/share/applications" "/var/lib/flatpak/exports/share/applications"; do
  [ -d "$d" ] && find "$d" -maxdepth 1 -name '*.desktop' -exec ln -sf {} "$HOME/.local/share/applications/" \;
done

# Update Flatpak's appstream metadata (app descriptions, icons, categories)
# and refresh the desktop database so the app launcher picks up new entries.
flatpak update --appstream -y || true
update-desktop-database "$HOME/.local/share/applications" >/dev/null || true
sudo update-desktop-database /usr/share/applications >/dev/null || true

# Restart the XDG desktop portal services so they pick up the new
# configuration. The portals are D-Bus services that act as middlemen
# between sandboxed Flatpak apps and the desktop. Restarting ensures
# the Hyprland portal is active and ready to handle app launch requests.
systemctl --user daemon-reload || true
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal || true

# Install GNOME Calculator as a quick test to verify Flatpak is working.
# If this succeeds, the full Flatpak pipeline is functional and you can
# install any app from COSMIC Store or the command line.
flatpak install -y flathub org.gnome.Calculator || true

cat <<'EONOTE'

✅ Done.

Next:
1) Log out of Hyprland and back in (applies environment.d so Omarchy launcher sees Flatpaks).
2) Open "COSMIC Store" from your apps menu (it uses Hyprland portal via wrapper).
3) Verify Flatpak apps appear in the launcher. Test:
   flatpak run org.gnome.Calculator

If COSMIC can't "Open" an app, you can also launch the store directly with:
  env XDG_CURRENT_DESKTOP=Hyprland cosmic-store

To remove everything later:
  yay -Rns cosmic-store-git  # or: sudo pacman -Rns cosmic-store-git
  rm -f ~/.local/share/applications/com.system76.CosmicStore.desktop
  sudo rm -f /usr/local/bin/cosmic-store-hypr
  rm -f ~/.config/environment.d/flatpak.conf
  # (then log out/in)
EONOTE
