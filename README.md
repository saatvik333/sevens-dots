# Sevens-Dots

Automated installer for Niri window manager dotfiles on Arch Linux.

## Features

- **Interactive Shell Setup** - Choose Fish, Zsh, or both
- **Complete Desktop Environment** - Niri, Waybar, Mako, and more
- **GTK Themes** - Colloid, Rose Pine, and Osaka themes
- **Automatic Backups** - Your existing configs are safely backed up
- **Robust Installation** - Retry logic and comprehensive error handling

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/saatvik333/niri-dotfiles/main/install.sh)
```

Or clone and run locally:

```bash
git clone https://github.com/saatvik333/niri-dotfiles.git ~/.dotfiles-sevens
cd ~/.dotfiles-sevens
bash install.sh
```

## What Gets Installed

### Packages

- **Window Manager**: Niri
- **Bar**: Waybar
- **Shells**: Fish and/or Zsh (your choice)
- **Terminal**: Alacritty, Kitty
- **Launcher**: Rofi
- **Notifications**: Mako
- **Lock Screen**: GTKlock
- **File Manager**: Yazi
- **Editor**: Neovim
- **PDF Viewer**: Zathura
- **Wallpaper**: swww
- **Themes**: Colloid, Rose Pine, Osaka (GTK) + Colloid icons

### Configurations

All configs are symlinked from `~/.dotfiles-sevens/` to `~/.config/`:

- niri, waybar, fish, zsh, mako, alacritty, kitty, starship
- nvim, yazi, gtklock, zathura, wallust, rofi

## Requirements

- Arch-based Linux distribution
- Sudo privileges
- Internet connection
- 5GB+ free disk space

## Post-Installation

1. Log out of your current session
2. Select "Niri" from your display manager
3. Log in to start using your new setup

## Customization

All configuration files are in `~/.dotfiles-sevens/`. Edit them as needed:

```bash
cd ~/.dotfiles-sevens
# Modify configs
git pull  # Update dotfiles
```

## Troubleshooting

Check the install log for details:

```bash
cat ~/.cache/sevens-dots-install-*.log
```

Restore backup if needed:

```bash
rm -rf ~/.config/<folder>
cp -r ~/.config_backup_<timestamp>/<folder> ~/.config/
```