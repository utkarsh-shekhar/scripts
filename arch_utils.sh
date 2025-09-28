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
  python go rust nodejs npm

# --- Media ---
sudo pacman -S --needed --noconfirm \
  mpv

# --- Internationalization (fonts + input methods) ---
sudo pacman -S --needed --noconfirm \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  noto-fonts-extra \
  ttf-dejavu \
  ttf-liberation \
  fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt \
  fcitx5-mozc \        # Japanese input
  fcitx5-hangul \      # Korean input
  fcitx5-chewing \     # Chinese (Zhuyin)
  fcitx5-pinyin \      # Chinese (Pinyin)
  fcitx5-thai          # Thai input

# --- Ensure yay is installed ---
if ! command -v yay &> /dev/null; then
  echo "yay not found, installing..."
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# --- AUR packages ---
yay -S --needed --noconfirm \
  jellyfin-mpv-shim jellyfin-media-player

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

