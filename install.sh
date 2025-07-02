#!/bin/bash

# check if sudo
if [ "$(id -u)" -ne 0 ]; then
	echo "Please run as sudo."
	exit 1
fi

# pacman packages
pacman_packages=(
	linux-lts-headers
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

# nvidia
read -p "Install NVIDIA drivers? (y/n): " install_nvidia

if [[ "$install_nvidia" == "y" || "$install_nvidia" == "Y" || "$install_nvidia" == "yes" || "$install_nvidia" == "YES" ]]; then
	echo "[+] Installing NVIDIA drivers..."
	sudo pacman -S --needed --noconfirm nvidia-lts nvidia-utils nvidia-settings
	
	# Create the suspend-hyprland.sh script
	cat > /usr/local/bin/suspend-hyprland.sh << 'EOF'
	#!/bin/bash

	case "$1" in
	    suspend)
	        killall -STOP Hyprland
	        ;;
	    resume)
	        killall -CONT Hyprland
	        ;;
	esac
	EOF

	# Make the script executable
	chmod +x /usr/local/bin/suspend-hyprland.sh

	# Create the hyprland-suspend.service systemd service file
	cat > /etc/systemd/system/hyprland-suspend.service << 'EOF'
	[Unit]
	Description=Suspend hyprland
	Before=systemd-suspend.service
	Before=systemd-hibernate.service
	Before=nvidia-suspend.service
	Before=nvidia-hibernate.service

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/suspend-hyprland.sh suspend

	[Install]
	WantedBy=systemd-suspend.service
	WantedBy=systemd-hibernate.service
	EOF

	# Create the hyprland-resume.service systemd service file
	cat > /etc/systemd/system/hyprland-resume.service << 'EOF'
	[Unit]
	Description=Resume hyprland
	After=systemd-suspend.service
	After=systemd-hibernate.service
	After=nvidia-resume.service

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/suspend-hyprland.sh resume

	[Install]
	WantedBy=systemd-suspend.service
	WantedBy=systemd-hibernate.service
	EOF

	# Reload the systemd daemon and enable the newly created services
	systemctl daemon-reload
	systemctl enable hyprland-suspend
	systemctl enable hyprland-resume

	sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<EOF
	blacklist nouveau
	options nouveau modeset-0
	EOF

	sudo mkinitcpio -P
else
	echo "[*] Skipping NVIDIA driver installation."
fi

# sddm
sudo systemctl enable sddm

# folders
xdg-user-dirs-update

echo "[!] Done"

