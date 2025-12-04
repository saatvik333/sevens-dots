#!/usr/bin/env bash
#
# Sevens-Dots Installer
#
set -Eeuo pipefail

# ==========================
# CONFIGURATION
# ==========================

readonly REPO_URL="https://github.com/saatvik333/niri-dotfiles.git"
readonly DOTDIR="$HOME/.dotfiles-sevens"
readonly CONFIG_DIR="$HOME/.config"
readonly BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="$HOME/.cache/sevens-dots-install-$(date +%Y%m%d_%H%M%S).log"

# AUR helper choice (will be set interactively)
AUR_HELPER=""

# Progress tracking
CURRENT_STEP=0
TOTAL_STEPS=18

# Installation summary tracking
declare -a INSTALL_SUMMARY=()

# Shell configuration choices (will be set interactively)
CONFIGURE_FISH=false
CONFIGURE_ZSH=false


# Expected configuration folders in the repo
readonly CONFIG_FOLDERS=(
  niri waybar fish zsh fastfetch mako alacritty kitty starship
  nvim yazi vicinae gtklock zathura wallust rofi
)

# AUR packages to install
readonly AUR_PACKAGES=(
  vicinae-bin
  wallust
  dust
  eza
  niri-switch
  ttf-nerd-fonts-symbols
)

# Official repository packages
readonly PACMAN_PACKAGES=(
  niri waybar fish fastfetch mako alacritty kitty starship neovim yazi
  zathura zathura-pdf-mupdf ttf-jetbrains-mono-nerd 
  qt5-wayland qt6-wayland polkit-gnome ffmpeg imagemagick unzip jq
  swww gtklock rofi curl gtk-engine-murrine libnotify
)

# ==========================
# COLOR OUTPUT
# ==========================

readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ==========================
# LOGGING & OUTPUT FUNCTIONS
# ==========================

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

msg() {
  echo -e "${GREEN}==>${NC} $1"
  log "INFO: $1"
}

info() {
  echo -e "${BLUE}==>${NC} $1"
  log "INFO: $1"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  log "WARNING: $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
  log "ERROR: $1"
}

fatal() {
  error "$1"
  error "Installation failed. Check log file: $LOG_FILE"
  exit 1
}

step() {
  ((CURRENT_STEP++))
  echo ""
  echo -e "${CYAN}${BOLD}[Step $CURRENT_STEP/$TOTAL_STEPS]${NC} ${MAGENTA}$1${NC}"
  echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
  log "STEP $CURRENT_STEP/$TOTAL_STEPS: $1"
}

separator() {
  echo ""
  echo -e "${BLUE}═════════════════════════════════════════════════════════${NC}"
  echo ""
}

add_summary() {
  INSTALL_SUMMARY+=("$1")
}

# ==========================
# UTILITY FUNCTIONS
# ==========================

retry_command() {
  local max_attempts="$1"
  shift
  local cmd="$@"
  local attempt=1
  
  while [ "$attempt" -le "$max_attempts" ]; do
    if eval "$cmd"; then
      return 0
    fi
    
    if [ "$attempt" -lt "$max_attempts" ]; then
      warn "Command failed (attempt $attempt/$max_attempts). Retrying in $((attempt * 2)) seconds..."
      sleep $((attempt * 2))
    fi
    ((attempt++))
  done
  
  return 1
}

check_internet() {
  info "Checking internet connectivity..."
  # Verify curl exists first
  if ! command -v curl &> /dev/null; then
    warn "curl not found, installing base tools first..."
    return 0 # Will be installed in install_base_tools
  fi

  # Try multiple endpoints for better reliability
  local endpoints=("https://archlinux.org" "https://google.com" "https://cloudflare.com")
  local connected=false
  
  for endpoint in "${endpoints[@]}"; do
    if curl -s --connect-timeout 5 --max-time 10 "$endpoint" > /dev/null 2>&1; then
      connected=true
      break
    fi
  done
  
  if [ "$connected" = false ]; then
    fatal "No internet connection. Please connect to the internet and try again."
  fi
  
  msg "Internet connection verified."
  
  # Check connection quality
  info "Testing connection quality..."
  if ! curl -s --connect-timeout 2 --max-time 5 https://archlinux.org > /dev/null 2>&1; then
    warn "Network connection appears slow. Installation may take longer than usual."
  fi
}

check_arch_based() {
  info "Verifying Arch-based system..."
  
  # Check if pacman exists (all Arch-based distros use pacman)
  if ! command -v pacman &> /dev/null; then
    fatal "This script requires pacman package manager (Arch-based distribution)."
  fi
  
  # Try to get distribution name from /etc/os-release
  local distro_name="Unknown"
  if [ -f /etc/os-release ]; then
    distro_name=$(grep -E '^NAME=' /etc/os-release | cut -d'"' -f2)
    
    # Verify it's Arch-based by checking ID or ID_LIKE
    local is_arch_based=false
    if grep -qE '^ID=arch$' /etc/os-release || \
       grep -qE '^ID_LIKE=.*arch.*' /etc/os-release || \
       [ -f /etc/arch-release ]; then
      is_arch_based=true
    fi
    
    if [ "$is_arch_based" = false ]; then
      fatal "This script is designed for Arch-based distributions only. Detected: $distro_name"
    fi
  fi
  
  msg "Arch-based system detected: $distro_name"
}

check_disk_space() {
  info "Checking available disk space..."
  local available_mb
  available_mb=$(df -P -BM "$HOME" | tail -n 1 | awk '{print $4}' | sed 's/M//')

  if [ "$available_mb" -lt 5000 ]; then
    warn "Low disk space detected: ${available_mb}MB available"
    warn "Installation requires at least 5GB free space for packages and builds"
    warn "You may encounter issues during installation"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      fatal "Installation cancelled by user"
    fi
  else
    msg "Sufficient disk space available: ${available_mb}MB"
  fi
}

check_not_root() {
  if [ "$EUID" -eq 0 ]; then
    fatal "Do not run this script as root. Run as a regular user with sudo privileges."
  fi
}

check_sudo() {
  info "Verifying sudo privileges..."
  if ! sudo -v; then
    fatal "Sudo privileges required. Please ensure you have sudo access."
  fi

  # Keep sudo alive
  (while true; do
    sudo -v
    sleep 50
  done 2> /dev/null) &
  readonly SUDO_PID=$!
  msg "Sudo privileges verified."
}

verify_binary() {
  local binary="$1"
  if ! command -v "$binary" &> /dev/null; then
    error "Binary '$binary' not found in PATH."
    return 1
  fi
  return 0
}

cleanup_on_exit() {
  # Kill sudo keep-alive safely
  if [ -n "${SUDO_PID:-}" ] && kill -0 "$SUDO_PID" 2> /dev/null; then
    kill "$SUDO_PID" 2> /dev/null || true
    wait "$SUDO_PID" 2> /dev/null || true
  fi
}

# Note: This trap is combined with offer_restore trap at the end of the script
# See line ~1190 for the combined trap handler

# ==========================
# BACKUP FUNCTIONS
# ==========================

create_backup() {
  msg "Creating backup of existing configurations..."
  mkdir -p "$BACKUP_DIR"
  mkdir -p "$CONFIG_DIR"

  local backed_up=0
  local symlinks_found=0

  for folder in "${CONFIG_FOLDERS[@]}"; do
    local target="$CONFIG_DIR/$folder"
    if [ -e "$target" ] || [ -L "$target" ]; then
      # Handle both symlinks and regular files/directories
      if [ -L "$target" ]; then
        # Warn about symlinks
        warn "Symlink detected: $folder -> $(readlink "$target")"
        ((symlinks_found++))
        # Remove symlink without backing up
        rm "$target"
        info "Removed symlink: $folder"
      elif cp -rL "$target" "$BACKUP_DIR/" 2> /dev/null; then
        rm -rf "$target"
        info "Backed up: $folder"
        ((backed_up++))
      else
        warn "Failed to backup: $folder"
      fi
    fi
  done

  if [ $symlinks_found -gt 0 ]; then
    warn "Found $symlinks_found symlink(s). These were removed without backup."
    warn "If they pointed to important data, you may want to restore them manually."
  fi

  if [ $backed_up -gt 0 ]; then
    msg "Backed up $backed_up configuration(s) to: $BACKUP_DIR"
  else
    info "No existing configurations found to backup."
  fi
}

offer_restore() {
  if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2> /dev/null)" ]; then
    echo ""
    warn "Installation encountered an error."
    echo -e "${YELLOW}Your previous configurations are backed up at:${NC}"
    echo "  $BACKUP_DIR"
    echo ""
    read -p "Would you like to restore your backup now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      restore_backup
    fi
  fi
}

restore_backup() {
  info "Restoring backup..."
  for folder in "$BACKUP_DIR"/*; do
    if [ -e "$folder" ]; then
      local basename=$(basename "$folder")
      rm -rf "$CONFIG_DIR/$basename"
      mv "$folder" "$CONFIG_DIR/"
      info "Restored: $basename"
    fi
  done
  msg "Backup restored successfully."
}

# ==========================
# PACKAGE MANAGEMENT
# ==========================

update_system() {
  info "Updating system packages..."
  if sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
    msg "System updated successfully."
  else
    fatal "Failed to update system packages."
  fi
}

install_base_tools() {
  info "Installing base development tools..."
  if sudo pacman -S --needed --noconfirm git base-devel curl >> "$LOG_FILE" 2>&1; then
    msg "Base tools installed."
  else
    fatal "Failed to install base development tools."
  fi
}

choose_aur_helper() {
  info "Checking for existing AUR helpers..."
  
  # Check if yay or paru already exists
  local has_yay=false
  local has_paru=false
  
  if verify_binary yay; then
    has_yay=true
  fi
  
  if verify_binary paru; then
    has_paru=true
  fi
  
  # If both exist, let user choose
  if [ "$has_yay" = true ] && [ "$has_paru" = true ]; then
    echo ""
    echo -e "${YELLOW}Both yay and paru are installed.${NC}"
    echo "Which AUR helper would you like to use?"
    echo "  1) yay"
    echo "  2) paru"
    echo ""
    read -p "Enter your choice (1/2) [default: 1]: " -r
    echo
    
    if [[ $REPLY == "2" ]]; then
      AUR_HELPER="paru"
      msg "Using paru as AUR helper."
    else
      AUR_HELPER="yay"
      msg "Using yay as AUR helper."
    fi
    return 0
  fi
  
  # If only one exists, use it
  if [ "$has_yay" = true ]; then
    AUR_HELPER="yay"
    msg "yay AUR helper already installed."
    return 0
  fi
  
  if [ "$has_paru" = true ]; then
    AUR_HELPER="paru"
    msg "paru AUR helper already installed."
    return 0
  fi
  
  # Neither exists, ask user which to install
  echo ""
  echo -e "${BLUE}Choose your preferred AUR helper:${NC}"
  echo "  1) yay   - Yet Another Yogurt (popular, feature-rich)"
  echo "  2) paru  - Pacman AUR helper (modern, fast, written in Rust)"
  echo ""
  read -p "Enter your choice (1/2) [default: 1]: " -r
  echo
  
  if [[ $REPLY == "2" ]]; then
    AUR_HELPER="paru"
    install_paru
  else
    AUR_HELPER="yay"
    install_yay
  fi
}

install_yay() {
  info "Installing yay AUR helper..."

  # Try installing from official repos first (works on Manjaro, Garuda, etc.)
  if sudo pacman -S --noconfirm yay >> "$LOG_FILE" 2>&1; then
    msg "yay installed from official repository."
    return 0
  fi

  # If that fails, build from AUR (vanilla Arch Linux)
  info "yay not in official repos, building from AUR..."
  local yay_dir
  yay_dir=$(mktemp -d)

  info "Cloning yay repository (this may take a moment)..."
  if ! retry_command 3 "git clone --depth=1 https://aur.archlinux.org/yay-bin.git '$yay_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$yay_dir"
    fatal "Failed to clone yay repository after multiple attempts."
  fi

  # Build in subshell but handle errors properly
  info "Building yay package (this may take a few minutes)..."
  if ! (cd "$yay_dir" && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1); then
    rm -rf "$yay_dir"
    fatal "Failed to build and install yay."
  fi

  rm -rf "$yay_dir"

  if verify_binary yay; then
    msg "yay installed successfully from AUR."
  else
    fatal "yay installation completed but binary not found."
  fi
}

install_paru() {
  info "Installing paru AUR helper..."

  # Try installing from official repos first (some distros include it)
  if sudo pacman -S --noconfirm paru >> "$LOG_FILE" 2>&1; then
    msg "paru installed from official repository."
    return 0
  fi

  # If that fails, build from AUR
  info "paru not in official repos, building from AUR..."
  local paru_dir
  paru_dir=$(mktemp -d)

  info "Cloning paru repository (this may take a moment)..."
  if ! retry_command 3 "git clone --depth=1 https://aur.archlinux.org/paru-bin.git '$paru_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$paru_dir"
    fatal "Failed to clone paru repository after multiple attempts."
  fi

  # Build in subshell but handle errors properly
  info "Building paru package (this may take a few minutes)..."
  if ! (cd "$paru_dir" && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1); then
    rm -rf "$paru_dir"
    fatal "Failed to build and install paru."
  fi

  rm -rf "$paru_dir"

  if verify_binary paru; then
    msg "paru installed successfully from AUR."
  else
    fatal "paru installation completed but binary not found."
  fi
}

install_pacman_packages() {
  info "Installing official repository packages..."
  info "This may take several minutes..."
  if sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}" >> "$LOG_FILE" 2>&1; then
    msg "Official packages installed successfully."
  else
    fatal "Failed to install official repository packages."
  fi
}

install_aur_packages() {
  info "Installing AUR packages using $AUR_HELPER..."
  info "This may take several minutes..."
  if "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}" >> "$LOG_FILE" 2>&1; then
    msg "AUR packages installed successfully."
  else
    fatal "Failed to install AUR packages."
  fi
}

install_colloid_theme() {
  local theme_dir
  theme_dir=$(mktemp -d)
  
  info "Installing Colloid GTK theme..."
  info "Cloning Colloid theme repository (this may take a moment)..."
  
  if ! retry_command 3 "git clone --depth=1 https://github.com/vinceliuice/Colloid-gtk-theme '$theme_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$theme_dir"
    warn "Failed to clone Colloid theme repository after multiple attempts."
    return 1
  fi
  
  info "Installing Colloid theme variants..."
  if ! (cd "$theme_dir" && ./install.sh --libadwaita --tweaks all rimless >> "$LOG_FILE" 2>&1); then
    rm -rf "$theme_dir"
    warn "Failed to install Colloid theme (default variant)."
    return 1
  fi
  
  info "Installing Colloid theme (grey-black variant)..."
  if ! (cd "$theme_dir" && ./install.sh --libadwaita --theme grey --tweaks black rimless >> "$LOG_FILE" 2>&1); then
    rm -rf "$theme_dir"
    warn "Failed to install Colloid theme (grey-black variant)."
    return 1
  fi
  
  rm -rf "$theme_dir"
  msg "Colloid GTK theme installed successfully."
  return 0
}

install_rosepine_theme() {
  local theme_dir
  theme_dir=$(mktemp -d)
  
  info "Installing Rose Pine GTK theme..."
  info "Cloning Rose Pine theme repository (this may take a moment)..."
  
  if ! retry_command 3 "git clone --depth=1 https://github.com/Fausto-Korpsvart/Rose-Pine-GTK-Theme '$theme_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$theme_dir"
    warn "Failed to clone Rose Pine theme repository after multiple attempts."
    return 1
  fi
  
  info "Installing Rose Pine theme with moon variant..."
  if ! (cd "$theme_dir" && ./install.sh --libadwaita --tweaks moon macos >> "$LOG_FILE" 2>&1); then
    rm -rf "$theme_dir"
    warn "Failed to install Rose Pine theme."
    return 1
  fi
  
  rm -rf "$theme_dir"
  msg "Rose Pine GTK theme installed successfully."
  return 0
}

install_osaka_theme() {
  local theme_dir
  theme_dir=$(mktemp -d)
  
  info "Installing Osaka GTK theme..."
  info "Cloning Osaka theme repository (this may take a moment)..."
  
  if ! retry_command 3 "git clone --depth=1 https://github.com/Fausto-Korpsvart/Osaka-GTK-Theme '$theme_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$theme_dir"
    warn "Failed to clone Osaka theme repository after multiple attempts."
    return 1
  fi
  
  info "Installing Osaka theme with solarized variant..."
  if ! (cd "$theme_dir" && ./install.sh --libadwaita --tweaks solarized macos >> "$LOG_FILE" 2>&1); then
    rm -rf "$theme_dir"
    warn "Failed to install Osaka theme."
    return 1
  fi
  
  rm -rf "$theme_dir"
  msg "Osaka GTK theme installed successfully."
  return 0
}

install_gtk_themes() {
  info "Installing GTK themes..."
  info "This may take several minutes..."
  
  local themes_dir="$HOME/.themes"
  mkdir -p "$themes_dir"
  
  local installed_themes=()
  local failed_themes=()
  
  # Install Colloid theme
  if install_colloid_theme; then
    installed_themes+=("Colloid")
  else
    failed_themes+=("Colloid")
  fi
  
  # Install Rose Pine theme
  if install_rosepine_theme; then
    installed_themes+=("Rose-Pine")
  else
    failed_themes+=("Rose-Pine")
  fi
  
  # Install Osaka theme
  if install_osaka_theme; then
    installed_themes+=("Osaka")
  else
    failed_themes+=("Osaka")
  fi
  
  # Report results
  if [ ${#installed_themes[@]} -gt 0 ]; then
    msg "Successfully installed ${#installed_themes[@]} GTK theme(s): ${installed_themes[*]}"
  fi
  
  if [ ${#failed_themes[@]} -gt 0 ]; then
    warn "Failed to install ${#failed_themes[@]} GTK theme(s): ${failed_themes[*]}"
    warn "You can manually install these themes later if needed."
  fi
  
  # Only fail if ALL themes failed to install
  if [ ${#installed_themes[@]} -eq 0 ]; then
    error "All GTK themes failed to install."
    return 1
  fi
  
  return 0
}

install_colloid_icons() {
  local icons_dir
  icons_dir=$(mktemp -d)
  
  info "Installing Colloid icon theme..."
  info "Cloning Colloid icon theme repository (this may take a moment)..."
  
  if ! retry_command 3 "git clone --depth=1 https://github.com/vinceliuice/Colloid-icon-theme '$icons_dir' >> '$LOG_FILE' 2>&1"; then
    rm -rf "$icons_dir"
    warn "Failed to clone Colloid icon theme repository after multiple attempts."
    return 1
  fi
  
  info "Installing Colloid icon theme with all schemes (bold)..."
  if ! (cd "$icons_dir" && ./install.sh --scheme all --bold >> "$LOG_FILE" 2>&1); then
    rm -rf "$icons_dir"
    warn "Failed to install Colloid icon theme."
    return 1
  fi
  
  rm -rf "$icons_dir"
  msg "Colloid icon theme installed successfully."
  return 0
}

install_icon_themes() {
  info "Installing icon themes..."
  info "This may take several minutes..."
  
  local icons_dir="$HOME/.icons"
  mkdir -p "$icons_dir"
  
  local installed_icons=()
  local failed_icons=()
  
  # Install Colloid icon theme
  if install_colloid_icons; then
    installed_icons+=("Colloid")
  else
    failed_icons+=("Colloid")
  fi
  
  # Report results
  if [ ${#installed_icons[@]} -gt 0 ]; then
    msg "Successfully installed ${#installed_icons[@]} icon theme(s): ${installed_icons[*]}"
  fi
  
  if [ ${#failed_icons[@]} -gt 0 ]; then
    warn "Failed to install ${#failed_icons[@]} icon theme(s): ${failed_icons[*]}"
    warn "You can manually install these icon themes later if needed."
  fi
  
  # Only fail if ALL icon themes failed to install
  if [ ${#installed_icons[@]} -eq 0 ]; then
    error "All icon themes failed to install."
    return 1
  fi
  
  return 0
}

verify_all_binaries() {
  info "Verifying all required binaries are installed..."
  local missing_binaries=()
  local binaries_to_check=(
    niri waybar fish fastfetch mako alacritty kitty starship
    nvim yazi vicinae gtklock zathura wallust swww rofi
  )

  for binary in "${binaries_to_check[@]}"; do
    if ! verify_binary "$binary"; then
      missing_binaries+=("$binary")
    fi
  done

  if [ ${#missing_binaries[@]} -gt 0 ]; then
    error "The following required binaries are missing:"
    printf '  - %s\n' "${missing_binaries[@]}"
    fatal "Please install missing packages manually and re-run the script."
  fi

  msg "All required binaries verified."
}

# ==========================
# SHELL MANAGEMENT
# ==========================

configure_shells() {
  info "Shell configuration setup..."
  echo ""
  echo -e "${BLUE}${BOLD}Which shell configuration(s) would you like to set up?${NC}"
  echo ""
  echo -e "${CYAN}This will install and configure the selected shell(s) with the dotfiles.${NC}"
  echo ""
  echo "  1) Fish only      - Modern, user-friendly shell with auto-suggestions"
  echo "  2) Zsh only       - Powerful, highly customizable shell"
  echo "  3) Both Fish & Zsh - Set up both shell configurations"
  echo "  4) Neither        - Skip shell configuration (keep current setup)"
  echo ""
  read -p "Enter your choice (1-4) [default: 3]: " -r
  echo

  case "$REPLY" in
    1)
      CONFIGURE_FISH=true
      CONFIGURE_ZSH=false
      msg "Selected: Fish shell configuration"
      ;;
    2)
      CONFIGURE_FISH=false
      CONFIGURE_ZSH=true
      msg "Selected: Zsh shell configuration"
      ;;
    4)
      CONFIGURE_FISH=false
      CONFIGURE_ZSH=false
      msg "Selected: No shell configuration"
      info "Skipping shell setup. You can configure shells manually later."
      return 0
      ;;
    *)
      # Default to both
      CONFIGURE_FISH=true
      CONFIGURE_ZSH=true
      msg "Selected: Both Fish and Zsh configurations"
      ;;
  esac

  # Install selected shells
  local shells_to_install=()
  
  if [ "$CONFIGURE_FISH" = true ]; then
    if ! verify_binary fish; then
      shells_to_install+=("fish")
    fi
  fi
  
  if [ "$CONFIGURE_ZSH" = true ]; then
    if ! verify_binary zsh; then
      shells_to_install+=("zsh")
    fi
  fi

  # Install any missing shells
  if [ ${#shells_to_install[@]} -gt 0 ]; then
    info "Installing selected shell(s): ${shells_to_install[*]}"
    if sudo pacman -S --needed --noconfirm "${shells_to_install[@]}" >> "$LOG_FILE" 2>&1; then
      msg "Shell(s) installed successfully."
    else
      warn "Failed to install some shells. They may already be installed."
    fi
  else
    info "Selected shell(s) already installed."
  fi

  # Summarize what was configured
  local configured_shells=()
  [ "$CONFIGURE_FISH" = true ] && configured_shells+=("Fish")
  [ "$CONFIGURE_ZSH" = true ] && configured_shells+=("Zsh")
  
  if [ ${#configured_shells[@]} -gt 0 ]; then
    msg "Shell configuration(s) ready: ${configured_shells[*]}"
  fi
}


set_default_shell() {
  # Skip if no shells were configured
  if [ "$CONFIGURE_FISH" = false ] && [ "$CONFIGURE_ZSH" = false ]; then
    info "No shell configurations were set up. Skipping default shell selection."
    return 0
  fi

  info "Checking default shell..."
  local current_shell=$(getent passwd "$USER" | cut -d: -f7)
  local current_shell_name=$(basename "$current_shell")

  echo ""
  echo -e "${BLUE}Your current shell is:${NC} $current_shell_name ($current_shell)"
  echo ""
  echo -e "${YELLOW}Would you like to change your default shell?${NC}"
  
  # Build dynamic menu based on configured shells
  local option_num=1
  local -A shell_options
  
  echo "  $option_num) Keep current shell ($current_shell_name)"
  ((option_num++))
  
  if [ "$CONFIGURE_ZSH" = true ]; then
    shell_options[$option_num]="zsh"
    echo "  $option_num) zsh   - Z Shell (powerful, highly customizable)"
    ((option_num++))
  fi
  
  if [ "$CONFIGURE_FISH" = true ]; then
    shell_options[$option_num]="fish"
    echo "  $option_num) fish  - Friendly Interactive Shell (user-friendly, modern)"
    ((option_num++))
  fi
  
  local max_option=$((option_num - 1))
  echo ""
  read -p "Enter your choice (1-$max_option) [default: 1]: " -r
  echo

  # Handle user selection
  if [[ -z "$REPLY" ]] || [[ "$REPLY" == "1" ]]; then
    msg "Keeping current shell: $current_shell_name"
    return 0
  fi

  # Validate selection
  if [[ ! "$REPLY" =~ ^[0-9]+$ ]] || [ "$REPLY" -lt 1 ] || [ "$REPLY" -gt "$max_option" ]; then
    warn "Invalid selection. Keeping current shell: $current_shell_name"
    return 0
  fi

  local shell_name="${shell_options[$REPLY]}"
  if [ -z "$shell_name" ]; then
    msg "Keeping current shell: $current_shell_name"
    return 0
  fi

  local selected_shell=$(command -v "$shell_name")

  # Check if selected shell exists (should already be installed from configure_shells)
  if [ -z "$selected_shell" ]; then
    warn "$shell_name is not installed. Installing it now..."
    
    if sudo pacman -S --needed --noconfirm "$shell_name" >> "$LOG_FILE" 2>&1; then
      selected_shell=$(command -v "$shell_name")
      msg "$shell_name installed successfully."
    else
      error "Failed to install $shell_name."
      return 1
    fi
  fi

  # Check if it's already the current shell
  if [ "$current_shell" = "$selected_shell" ]; then
    msg "$shell_name is already your default shell."
    return 0
  fi

  info "Changing default shell to $shell_name..."
  
  # Ensure the shell is in /etc/shells
  if ! grep -q "^$selected_shell$" /etc/shells 2> /dev/null; then
    info "Adding $shell_name to /etc/shells..."
    echo "$selected_shell" | sudo tee -a /etc/shells >> "$LOG_FILE" 2>&1
  fi

  # Change the shell
  if chsh -s "$selected_shell" >> "$LOG_FILE" 2>&1; then
    msg "Default shell changed to $shell_name successfully."
    warn "You'll need to log out and back in for this to take effect."
  else
    error "Failed to change default shell."
    info "You can manually change it later with: chsh -s $selected_shell"
  fi
}

# ==========================
# DOTFILES MANAGEMENT
# ==========================

clone_or_update_dotfiles() {
  if [ -d "$DOTDIR/.git" ]; then
    msg "Dotfiles directory exists. Updating..."
    if ! retry_command 3 "git -C '$DOTDIR' pull --rebase >> '$LOG_FILE' 2>&1"; then
      warn "Failed to update dotfiles after retries. Removing and re-cloning..."
      rm -rf "$DOTDIR"
      clone_dotfiles
    else
      msg "Dotfiles updated successfully."
    fi
  elif [ -d "$DOTDIR" ]; then
    warn "Dotfiles directory exists but is not a git repository. Removing and re-cloning..."
    rm -rf "$DOTDIR"
    clone_dotfiles
  else
    clone_dotfiles
  fi

  # Initialize submodules
  info "Updating git submodules..."
  if retry_command 3 "git -C '$DOTDIR' submodule update --init --recursive >> '$LOG_FILE' 2>&1"; then
    msg "Submodules updated."
  else
    warn "Failed to update submodules after retries. Continuing anyway..."
  fi
}

clone_dotfiles() {
  info "Cloning dotfiles repository (this may take a moment)..."
  if ! retry_command 3 "git clone --depth=1 '$REPO_URL' '$DOTDIR' >> '$LOG_FILE' 2>&1"; then
    fatal "Failed to clone dotfiles repository after multiple attempts. Check your internet connection."
  fi
  
  # Validate the cloned repository
  if [ ! -d "$DOTDIR/.git" ]; then
    fatal "Repository cloned but .git directory not found. Clone may be corrupted."
  fi
  
  msg "Dotfiles cloned successfully."
}

validate_repo_structure() {
  info "Validating repository structure..."
  local missing_folders=()

  for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ ! -d "$DOTDIR/$folder" ]; then
      missing_folders+=("$folder")
    fi
  done

  if [ ${#missing_folders[@]} -gt 0 ]; then
    warn "The following expected folders are missing from the repository:"
    printf '  - %s\n' "${missing_folders[@]}"
    warn "Installation will continue, but these configurations will be skipped."
  else
    msg "Repository structure validated."
  fi
}

create_symlinks() {
  msg "Creating symbolic links to ~/.config..."
  local linked=0
  local skipped=0

  set +e # Disable exit on error for symlink loop

  for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ -d "$DOTDIR/$folder" ]; then
      local target="$CONFIG_DIR/$folder"
      # Target should already be handled by backup, but double-check
      if [ -e "$target" ] || [ -L "$target" ]; then
        warn "Target still exists: $folder (removing)"
        rm -rf "$target"
      fi

      if ln -s "$DOTDIR/$folder" "$target" 2>> "$LOG_FILE"; then
        info "Linked: $folder"
        ((linked++))
      else
        error "Failed to link: $folder (check log for details)"
      fi
    else
      info "Skipping: $folder (not found in repository)"
      ((skipped++))
    fi
  done

  msg "Created $linked symlink(s), skipped $skipped."
  set -e # Re-enable exit on error
}

install_wallpapers() {
  if [ -d "$DOTDIR/wallpapers" ]; then
    info "Installing wallpapers..."
    local wallpaper_dir="$HOME/Pictures/wallpapers"
    mkdir -p "$wallpaper_dir"

    shopt -s nullglob
    local wallpapers=("$DOTDIR/wallpapers/"*)
    shopt -u nullglob

    if [ ${#wallpapers[@]} -gt 0 ]; then
      if cp -r "$DOTDIR/wallpapers/"* "$wallpaper_dir/" 2> /dev/null; then
        msg "Wallpapers installed to: $wallpaper_dir"
      else
        warn "Failed to copy wallpapers."
      fi
    else
      info "No wallpapers found in repository."
    fi
  else
    info "No wallpapers directory found in repository."
  fi
}

install_scripts() {
  if [ -d "$DOTDIR/scripts" ]; then
    info "Installing scripts..."
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    shopt -s nullglob
    local scripts=("$DOTDIR/scripts/"*)
    shopt -u nullglob

    if [ ${#scripts[@]} -gt 0 ]; then
      if cp -r "$DOTDIR/scripts/"* "$bin_dir/" 2> /dev/null; then
        # Only make script files executable
        find "$bin_dir" -type f -name "*.sh" -exec chmod +x {} \; 2> /dev/null || true
        find "$bin_dir" -type f ! -name "*.*" -exec chmod +x {} \; 2> /dev/null || true
        msg "Scripts installed to: $bin_dir"

        # Check if ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
          warn "~/.local/bin is not in your PATH."
          info "Add the appropriate line to your shell profile:"
          echo "  For zsh (~/.zshrc):  export PATH=\"\$HOME/.local/bin:\$PATH\""
          echo "  For fish (~/.config/fish/config.fish):  set -gx PATH \$HOME/.local/bin \$PATH"
        fi
      else
        warn "Failed to copy scripts."
      fi
    else
      info "No scripts found in repository."
    fi
  else
    info "No scripts directory found in repository."
  fi
}

# ==========================
# SYSTEMD SERVICE MANAGEMENT
# ==========================

create_systemd_services() {
  info "Niri handles autostart via its config file."
  info "The following services are started by niri.conf:"
  echo "  - polkit-gnome-authentication-agent"
  echo "  - swww-daemon"
  echo "  - waybar"
  echo "  - vicinae server"
  echo ""
  info "Creating gtklock service for manual/idle trigger only..."

  local service_dir="$HOME/.config/systemd/user"
  mkdir -p "$service_dir"
  create_gtklock_service "$service_dir"

  systemctl --user daemon-reload >> "$LOG_FILE" 2>&1 || warn "Failed to reload systemd daemon."
  msg "Systemd services configured."
}

create_gtklock_service() {
  local service_dir="$1"

  if ! verify_binary gtklock; then
    warn "gtklock binary not found, skipping service creation"
    return
  fi

  local gtklock_bin=$(command -v gtklock)

  # gtklock service for manual invocation or idle trigger ONLY
  # Do NOT add to WantedBy - it should never autostart
  cat > "$service_dir/gtklock.service" <<EOF
[Unit]
Description=GTKLock Screen Locker
Documentation=man:gtklock(1)

[Service]
Type=simple
ExecStart=$gtklock_bin
Restart=no
EOF

  info "Created: gtklock.service (manual trigger only)"
  info "Note: gtklock will NOT autostart. Trigger it via 'systemctl --user start gtklock'"
}

# ==========================
# MAIN INSTALLATION FLOW
# ==========================

print_header() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  cat <<"EOF"
════════════════════════════════════════════════════════════
  SEVENS-DOTS - Installation Script v1.0
  Automated setup for your Niri window manager configuration
════════════════════════════════════════════════════════════
EOF
  echo -e "${NC}"
  echo -e "Repository: ${BLUE}$REPO_URL${NC}"
  echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
  echo ""
}

print_summary() {
  separator
  echo -e "${GREEN}${BOLD}"
  cat <<"EOF"
════════════════════════════════════════════════════════════
  INSTALLATION COMPLETED SUCCESSFULLY!
  Your sevens-dots configuration has been installed
════════════════════════════════════════════════════════════
EOF
  echo -e "${NC}"
  
  # Display installation summary
  if [ ${#INSTALL_SUMMARY[@]} -gt 0 ]; then
    echo ""
    echo -e "${CYAN}${BOLD}Installation Summary:${NC}"
    echo -e "${CYAN}────────────────────${NC}"
    for item in "${INSTALL_SUMMARY[@]}"; do
      echo -e "  ${GREEN}✓${NC} $item"
    done
  fi
  
  separator
  echo -e "${MAGENTA}${BOLD}Next Steps:${NC}"
  echo "  1. Log out of your current session"
  echo "  2. Select 'Niri' from your display manager"
  echo "  3. Log in to start using your new setup"
  echo ""
  echo -e "${BLUE}${BOLD}Important Notes:${NC}"
  echo "  • Services are auto-started by niri.conf, not systemd"
  echo "  • swww-daemon, waybar, vicinae, and polkit start automatically"
  echo "  • gtklock can be triggered manually or via idle timeout"
  echo ""

  if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2> /dev/null)" ]; then
    echo -e "${YELLOW}${BOLD}Backup Information:${NC}"
    echo "  Your previous configurations are backed up at:"
    echo -e "  ${CYAN}$BACKUP_DIR${NC}"
    echo ""
    read -p "Would you like to remove the backup directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "$BACKUP_DIR"
      msg "Backup directory removed."
    else
      info "Backup kept for your reference."
    fi
    echo ""
  fi

  echo -e "${BLUE}${BOLD}Troubleshooting:${NC}"
  echo "  If you encounter any issues, check the log file:"
  echo -e "  ${CYAN}$LOG_FILE${NC}"
  separator
}

main() {
  # Ensure log directory exists
  mkdir -p "$(dirname "$LOG_FILE")"

  print_header

  # Pre-flight checks
  step "Pre-flight System Checks"
  check_not_root
  check_arch_based
  check_disk_space
  check_sudo
  check_internet
  add_summary "System validated and prerequisites checked"

  # System preparation
  step "System Update"
  update_system
  add_summary "System packages updated"
  
  step "Installing Base Development Tools"
  install_base_tools
  add_summary "Base development tools installed (git, base-devel, curl)"
  
  step "AUR Helper Selection and Installation"
  choose_aur_helper
  add_summary "AUR helper configured: $AUR_HELPER"

  # Package installation
  step "Installing Official Repository Packages"
  install_pacman_packages
  add_summary "Official packages installed (niri, waybar, fish, etc.)"
  
  step "Installing AUR Packages"
  install_aur_packages
  add_summary "AUR packages installed (vicinae, wallust)"
  
  step "Installing GTK Themes"
  install_gtk_themes
  add_summary "GTK themes installed (Colloid, Rose-Pine, Osaka)"
  
  step "Installing Icon Themes"
  install_icon_themes
  add_summary "Icon themes installed (Colloid icons)"
  
  step "Verifying Installed Binaries"
  verify_all_binaries
  add_summary "All required binaries verified"

  # Shell configuration
  step "Selecting Shell Configurations"
  configure_shells
  add_summary "Shell configuration(s) selected and installed"
  
  step "Setting Default Shell"
  set_default_shell
  add_summary "Default shell configured"

  # Dotfiles setup
  step "Cloning Dotfiles Repository"
  clone_or_update_dotfiles
  add_summary "Dotfiles repository cloned from $REPO_URL"
  
  step "Validating Repository Structure"
  validate_repo_structure
  add_summary "Repository structure validated"

  # Backup and configuration
  step "Creating Configuration Backup"
  create_backup
  add_summary "Existing configurations backed up to $BACKUP_DIR"
  
  step "Creating Symbolic Links"
  create_symlinks
  add_summary "Configuration symlinks created in ~/.config"
  
  step "Installing Wallpapers"
  install_wallpapers
  add_summary "Wallpapers installed to ~/Pictures/wallpapers"
  
  step "Installing Scripts"
  install_scripts
  add_summary "Scripts installed to ~/.local/bin"

  # Service setup
  step "Configuring System Services"
  create_systemd_services
  add_summary "Systemd services configured"

  # Done
  print_summary
}

# ==========================
# ERROR HANDLING
# ==========================

trap 'offer_restore; cleanup_on_exit' ERR EXIT INT TERM

# ==========================
# EXECUTE
# ==========================

main "$@"