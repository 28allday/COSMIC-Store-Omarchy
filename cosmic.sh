#!/usr/bin/env bash
set -euo pipefail

echo "== COSMIC Store + Hyprland one-shot setup for Omarchy (Arch) =="

have(){ command -v "$1" >/dev/null 2>&1; }
need(){ pacman -Q "$1" >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm "$1"; }
append_if_missing(){
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"; touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# 0) sanity
if ! have pacman; then echo "This script is for Arch/Arch-based systems."; exit 1; fi

# 1) deps
sudo pacman -Sy --noconfirm
need base-devel
need git
need flatpak
need xdg-desktop-portal
need xdg-desktop-portal-gtk
need xdg-desktop-portal-hyprland
need desktop-file-utils

# 2) flathub (system + user)
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak  remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

# 3) install COSMIC Store (AUR)
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

# 4) wrapper so COSMIC Store uses Hyprland portal for launching apps
sudo install -Dm755 /dev/stdin /usr/local/bin/cosmic-store-hypr <<'EOF'
#!/usr/bin/env bash
export XDG_CURRENT_DESKTOP=Hyprland
exec cosmic-store "$@"
EOF

# 5) user desktop override to use our wrapper
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

# 6) Omarchy launcher visibility: export env via systemd user + Hyprland config
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/flatpak.conf" <<'EOF'
XDG_DATA_DIRS=%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share
XDG_CURRENT_DESKTOP=Hyprland
EOF

HYPR_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
append_if_missing "env = XDG_CURRENT_DESKTOP,Hyprland" "$HYPR_CFG"
append_if_missing "env = XDG_DATA_DIRS,$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share" "$HYPR_CFG"

# 7) belt & suspenders: symlink Flatpak .desktop files into user's applications dir
mkdir -p "$HOME/.local/share/applications"
for d in "$HOME/.local/share/flatpak/exports/share/applications" "/var/lib/flatpak/exports/share/applications"; do
  [ -d "$d" ] && find "$d" -maxdepth 1 -name '*.desktop' -exec ln -sf {} "$HOME/.local/share/applications/" \;
done

# 8) update appstream + refresh desktop DB
flatpak update --appstream -y || true
update-desktop-database "$HOME/.local/share/applications" >/dev/null || true
sudo update-desktop-database /usr/share/applications >/dev/null || true

# 9) restart portals so launches go through Hyprland
systemctl --user daemon-reload || true
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal || true

# 10) quick test app (optional)
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
