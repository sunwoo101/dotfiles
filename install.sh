#!/bin/bash

# pacman packages
pacman_packages=(
	git
	base-devel
	hyprland
	hyprlock
	hypridle
	hyprpaper
	firefox
	sddm
	waybar
	nwg-dock-hyprland
	rofi
	kitty
	nano
	nvim
	nautilus
	xdg-user-dirs
	xdg-user-dirs-gtk
	ttf-jetbrains-mono-nerd
	less
)

echo ">> Updating package database..."
sudo pacman -Syu --noconfirm

echo ">> Installing packages..."
for pkg in "${pacman_packages[@]}; do
	if pacman -Qi "$pkg" &>/dev/null; then
		echo "[*] $pkg is already installed"
	else
		echo "[+] Installing $pkg..."
		sudo pacman -S --needed --noconfirm "$pkg"
	fi
done

# install yay
if ! command -v yay &>/dev/null; then
	echo "[+] yay not found, installing..."
	git clone https://aur.archlinux.org/yay.git /tmp/yay
	cd /tmp/yay
	makepkg -si --noconfirm
	cd ~
	rm -rf /tmp/yay
else
	echo "[*] yay is already installed"
fi

# aur packages
aur_packages=(
	waypaper
)

for pkg in "${aur_packages[@]}"; do
	if yay -Qi "$pkg" &>/dev/null; do
		echo "[*] $pkg is already installed (AUR)"
	else
		echo "[+] Installing $pkg (AUR)..."
		yay -S --noconfirm "$pkg"
	fi
done

echo "[!] Done"
