#!/bin/bash
# =============================================================================
#  arch_utils.sh — Modular Arch Linux setup utility
# =============================================================================
#  Install your Arch system in batches ("modules") instead of a single run.
#
#  Usage:
#    ./arch_utils.sh                  # interactive module selection
#    ./arch_utils.sh --all            # install every module
#    ./arch_utils.sh --only audio,gpu # install only listed modules
#    ./arch_utils.sh --list           # show available modules
#
#  Every module is idempotent (safe to re-run; uses --needed). Services are
#  enabled/started where appropriate. No file backup is needed: this file is
#  tracked in git (github.com/utkarsh-shekhar/scripts).
# =============================================================================
set -euo pipefail

mod_ollama() {
  step "Ollama (local LLM runtime for hyprwhspr cleaner)"
  # Base runtime (CPU inference) — this alone runs gemma3:1b for dictation cleanup.
  pac ollama

  # OPTIONAL GPU variant. Pulls the full ~5GB 'cuda' package. Skip unless you
  # want GPU inference (the dictation cleaner works fine on CPU).
  if [[ "${INSTALL_OLLAMA_CUDA:-no}" == "yes" ]]; then
    pac ollama-cuda 2>/dev/null || warn "ollama-cuda not available"
  else
    info "skipping ollama-cuda (optional GPU inference; set INSTALL_OLLAMA_CUDA=yes to enable)"
  fi

  # Use the packaged systemd service so it autostarts.
  # NOTE: the unit sets HOME=/var/lib/ollama, so models live there (root-owned),
  # independent of the user session. If you prefer ~/.ollama, run ollama manually.
  if systemctl list-unit-files | grep -q '^ollama.service'; then
    enable ollama
    sleep 1
    ollama pull gemma3:1b || warn "could not pull gemma3:1b (is the ollama service running?)"
  else
    warn "no ollama systemd unit; start 'ollama serve' manually, then pull gemma3:1b"
  fi
  install_ok
}

# ---------------------------------------------------------------- helpers ----
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

step()   { echo; echo -e "${BLUE}══════ $* ══════${NC}"; }
info()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()    { echo -e "${RED}  ✗ $*${NC}"; }

pac()    { sudo pacman -S --needed --noconfirm "$@"; }
yaypkg() { yay -S --needed --noconfirm "$@"; }
enable() { sudo systemctl enable --now "$1" 2>/dev/null || warn "could not enable $1"; }

declare -A INSTALLED_STATUS   # module -> "ok"|"skipped"

# ---------------------------------------------------------------- modules ----
mod_core() {
  step "Core system tools"
  pac base-devel git sudo bash-completion curl wget
  install_ok
}

mod_cli_tools() {
  step "CLI & terminal utilities"
  pac neovim less man-db man-pages which file tree \
      htop ncdu ripgrep fd bat eza jq fzf tmux vim nano zip unzip
  install_ok
}

mod_networking() {
  step "Networking"
  pac openssh net-tools inetutils dnsutils iproute2 iputils \
      networkmanager network-manager-applet iwd bind wireless_tools
  enable NetworkManager
  install_ok
}

mod_dev_langs() {
  step "Programming languages & runtimes"
  pac python go rust nodejs npm python-pip tk \
      python-pillow python-pyqt5 pulumi
  install_ok
}

mod_media() {
  step "Media"
  pac mpv ffmpeg vlc vlc-plugins-all obs-studio feh yt-dlp transmission-qt
  install_ok
}

mod_audio() {
  step "Audio (PipeWire + production)"
  pac pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
      gst-plugin-pipewire helvum libpulse \
      easyeffects qjackctl qpwgraph audacity lmms guitarix
  install_ok
}

mod_office() {
  step "Office"
  pac libreoffice-fresh
  install_ok
}

mod_fonts_i18n() {
  step "Fonts & input methods (fcitx5)"
  pac noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
      ttf-dejavu ttf-liberation \
      fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt \
      fcitx5-mozc fcitx5-hangul fcitx5-chewing
  configure_fcitx5
  install_ok
}

mod_kde_desktop() {
  step "KDE Plasma desktop"
  pac plasma-meta
  # Display manager
  pac sddm sddm-kcm
  enable sddm
  install_ok
}

mod_gpu_nvidia() {
  step "NVIDIA GPU drivers"
  pac nvidia-open-dkms nvidia-utils libva-nvidia-driver dkms realtime-privileges
  install_ok
}

mod_bluetooth() {
  step "Bluetooth"
  pac bluez bluez-utils
  enable bluetooth
  install_ok
}

mod_hardware() {
  step "Hardware & firmware"
  pac sof-firmware wacomtablet efibootmgr intel-ucode linux-headers \
      smartmontools zram-generator alsa-utils xdg-utils xorg-xinit
  install_ok
}

mod_browsers() {
  step "Browsers"
  pac chromium firefox
  install_ok
}

mod_games_apps() {
  step "Games & desktop apps"
  pac steam discord
  install_ok
}

mod_aur() {
  # Ensure yay (AUR helper) is present first
  step "AUR helper (yay)"
  if ! command -v yay &>/dev/null; then
    info "yay not found — installing from AUR..."
    git clone https://aur.archlinux.org/yay.git "$HOME/.cache/yay-build"
    (cd "$HOME/.cache/yay-build" && makepkg -si --noconfirm)
    rm -rf "$HOME/.cache/yay-build"
  else
    info "yay already installed"
  fi

  step "AUR packages"
  # NOTE: jellyfin-mpv-shim-shaders was removed — it does not exist in AUR.
  # mpv shaders are provided by mpv-shim-default-shaders (listed below).
  yaypkg \
    google-chrome \
    balena-etcher \
    armbian-imager-bin \
    jdownloader2 \
    vial-appimage \
    jellyfin-media-player \
    jellyfin-mpv-shim \
    mpv-shim-default-shaders \
    python-pystray \
    hyprwhspr
  install_ok
}

mod_hyprwhspr_setup() {
  step "Hyprwhspr post-install configuration"
  if command -v hyprwhspr &>/dev/null; then
    # Install the LLM dictation cleaner (with name/place grounding) from this repo
    local SCRIPT_SRC="$(dirname "$0")/hyprwhspr-cleantext.py"
    local SCRIPT_DST="$HOME/.local/bin/hyprwhspr-cleantext"
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$SCRIPT_SRC" ]]; then
      install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"
      info "installed cleaner to $SCRIPT_DST"
    else
      warn "hyprwhspr-cleantext.py not found next to arch_utils.sh"
    fi

    # Point the transcription hook at the cleaner (adds it to config.json)
    CFG="$HOME/.config/hyprwhspr/config.json"
    if [[ -f "$CFG" ]]; then
      python3 - "$CFG" "$SCRIPT_DST" <<'PY'
import json, sys
cfg, dst = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(cfg))
except Exception:
    d = {}
d['post_transcription_hook'] = dst
json.dump(d, open(cfg, 'w'), indent=2)
print("post_transcription_hook ->", dst)
PY
      info "wired post_transcription_hook into $CFG"
    else
      warn "hyprwhspr config not found — run 'hyprwhspr setup' first"
    fi

    # Enable the systemd user service (idempotent)
    systemctl --user enable hyprwhspr 2>/dev/null || warn "hyprwhspr user service not found yet"
    info "hyprwhspr ready — run 'hyprwhspr setup' once to complete backend install"
  else
    warn "hyprwhspr not found — install it (AUR module) first"
  fi
  install_ok
}

# ---------------------------------------------------------------- helpers ----
configure_fcitx5() {
  local XPROFILE="$HOME/.xprofile"
  echo
  echo "🔧 Configuring fcitx5 environment variables in $XPROFILE ..."
  mkdir -p "$(dirname "$XPROFILE")"
  grep -qxF 'export GTK_IM_MODULE=fcitx5'   "$XPROFILE" 2>/dev/null || echo 'export GTK_IM_MODULE=fcitx5'   >> "$XPROFILE"
  grep -qxF 'export QT_IM_MODULE=fcitx5'    "$XPROFILE" 2>/dev/null || echo 'export QT_IM_MODULE=fcitx5'    >> "$XPROFILE"
  grep -qxF 'export XMODIFIERS=@im=fcitx5'  "$XPROFILE" 2>/dev/null || echo 'export XMODIFIERS=@im=fcitx5'  >> "$XPROFILE"
  info "fcitx5 env configured in $XPROFILE"
}

install_ok() {
  INSTALLED_STATUS["$CURRENT_MODULE"]="ok"
}

# --------------------------------------------------------- module registry ----
declare -A MODULES=(
  [core]="${BLUE}Core system tools${NC} — base-devel, git, sudo, curl"
  [cli_tools]="${BLUE}CLI & terminal${NC} — neovim, htop, ripgrep, fd, bat, eza, jq, fzf, tmux"
  [networking]="${BLUE}Networking${NC} — openssh, networkmanager, iwd, bind"
  [dev_langs]="${BLUE}Dev languages${NC} — python, go, rust, nodejs, npm, pulumi"
  [media]="${BLUE}Media${NC} — mpv, ffmpeg, vlc, obs-studio, yt-dlp"
  [audio]="${BLUE}Audio${NC} — pipewire, easyeffects, audacity, lmms, guitarix"
  [office]="${BLUE}Office${NC} — libreoffice"
  [fonts_i18n]="${BLUE}Fonts & IME${NC} — noto fonts, fcitx5 + mozc/hangul/chewing"
  [kde_desktop]="${BLUE}KDE Plasma${NC} — plasma-meta + sddm"
  [gpu_nvidia]="${BLUE}NVIDIA GPU${NC} — nvidia-open-dkms, nvidia-utils, realtime-privileges"
  [bluetooth]="${BLUE}Bluetooth${NC} — bluez + utils"
  [hardware]="${BLUE}Hardware/firmware${NC} — wacom, sof-firmware, intel-ucode, zram"
  [browsers]="${BLUE}Browsers${NC} — chromium, firefox"
  [games_apps]="${BLUE}Games & apps${NC} — steam, discord"
  [aur]="${BLUE}AUR${NC} — yay + chrome, etcher, armbian, jellyfin, hyprwhspr"
  [hyprwhspr_setup]="${BLUE}Hyprwhspr setup${NC} — systemd user service + backend"
  [ollama]="${BLUE}Ollama${NC} — local LLM runtime + gemma3:1b model for cleaner"
)

ORDER=(core cli_tools networking dev_langs media audio office fonts_i18n
       kde_desktop gpu_nvidia bluetooth hardware browsers games_apps aur
       ollama hyprwhspr_setup)

# ---------------------------------------------------------------- runner ----
run_module() {
  CURRENT_MODULE="$1"
  local fn="mod_$1"
  if declare -F "$fn" >/dev/null; then
    INSTALLED_STATUS["$1"]="skip"   # default; install_ok() flips it
    "$fn"
  else
    err "Unknown module: $1"
  fi
}

# ---------------------------------------------------------------- main -------
usage() {
  echo "Usage:"
  echo "  $0                 interactive module selection"
  echo "  $0 --all           install every module"
  echo "  $0 --only a,b,c    install only the listed modules"
  echo "  $0 --list          show available modules"
}

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
    --list)
      for m in "${ORDER[@]}"; do
        printf "  %-16s %s\n" "$m" "${MODULES[$m]}"
      done
      exit 0
      ;;
    --all)
      for m in "${ORDER[@]}"; do run_module "$m"; done
      ;;
    --only)
      IFS=',' read -ra SELECTED <<< "$2"
      for m in "${SELECTED[@]}"; do
        case "${MODULES[$m]+x}" in
          x) run_module "$m" ;;
          *) err "Unknown module: $m" ;;
        esac
      done
      ;;
    *)
      usage; exit 1
      ;;
  esac
else
  # interactive selection
  echo "Available modules:"
  declare -A IDX
  i=1
  for m in "${ORDER[@]}"; do
    printf "  %2d) %-16s %s\n" "$i" "$m" "${MODULES[$m]}"; IDX[$i]="$m"; i=$((i+1))
  done
  echo "  a)  all"
  echo "Enter numbers to select (space/comma separated), or 'a' for all, or q to quit:"
  read -r choice
  for token in ${choice//,/ }; do
    case "$token" in
      q) echo "Aborted."; exit 0 ;;
      a) for m in "${ORDER[@]}"; do run_module "$m"; done; break ;;
      *) if [[ -n "${IDX[$token]:-}" ]]; then run_module "${IDX[$token]}"; else warn "invalid: $token"; fi ;;
    esac
  done
fi

# ---------------------------------------------------------------- summary ----
echo
step "Summary"
for m in "${ORDER[@]}"; do
  st="${INSTALLED_STATUS[$m]:-not run}"
  case "$st" in
    ok)      info "$m" ;;
    skip)    warn "$m — skipped (no packages)" ;;
    *)       warn "$m — $st" ;;
  esac
done
echo
echo -e "${GREEN}✅ Done. Log out/in or reboot if a reboot is required for new group memberships / kernel modules.${NC}"
echo "fcitx5: run fcitx5-configtool after login if using IME."
