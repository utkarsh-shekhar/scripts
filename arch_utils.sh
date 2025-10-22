#!/bin/bash
set -e  # exit on error

# --- Core system tools ---
sudo pacman -S --needed --noconfirm \
  base-devel git sudo bash-completion

# --- Editors & documentation ---
sudo pacman -S --needed --noconfirm \
  neovim less man-db man-pages which file tree

# --- Compression & transfer ---
sudo pacman -S --needed --noconfirm \
  zip unzip wget curl yt-dlp

# --- Monitoring & utilities ---
sudo pacman -S --needed --noconfirm \
  htop ncdu ripgrep fd bat exa jq

# --- Networking ---
sudo pacman -S --needed --noconfirm \
  openssh net-tools inetutils dnsutils iproute2 iputils

# --- Programming languages & runtimes ---
sudo pacman -S --needed --noconfirm \
 python go rust nodejs npm python-pip tk python-pillow python-pyqt5 pulumi

# --- Media ---
sudo pacman -S --needed --noconfirm \
  mpv ffmpeg vlc vlc-plugins-all

# --- Office ---
sudo pacman -S --needed --noconfirm \
  libreoffice-fresh

# --- Internationalization (fonts + input methods) ---
sudo pacman -S --needed --noconfirm \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  noto-fonts-extra \
  ttf-dejavu \
  ttf-liberation \
  fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt \
  fcitx5-mozc \
  fcitx5-hangul \
  fcitx5-chewing

# --- Ensure yay is installed ---
if ! command -v yay &> /dev/null; then
  echo "yay not found, installing..."
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# --- AUR packages ---
yay -S --needed --noconfirm \
  jellyfin-media-player \
  jellyfin-mpv-shim \
  jellyfin-mpv-shim-shaders \
  mpv-shim-default-shaders \
  python-pystray


# --- Configure fcitx5 environment variables ---
XPROFILE="$HOME/.xprofile"
echo
echo "🔧 Configuring fcitx5 environment variables in $XPROFILE ..."
mkdir -p "$(dirname "$XPROFILE")"

# Add lines only if they’re missing
grep -qxF 'export GTK_IM_MODULE=fcitx5' "$XPROFILE" 2>/dev/null || echo 'export GTK_IM_MODULE=fcitx5' >> "$XPROFILE"
grep -qxF 'export QT_IM_MODULE=fcitx5' "$XPROFILE" 2>/dev/null || echo 'export QT_IM_MODULE=fcitx5' >> "$XPROFILE"
grep -qxF 'export XMODIFIERS=@im=fcitx5' "$XPROFILE" 2>/dev/null || echo 'export XMODIFIERS=@im=fcitx5' >> "$XPROFILE"

echo
echo "✅ Installation complete."
echo "👉 Log out and back in, then run: fcitx5-configtool"

