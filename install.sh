#!/bin/bash

# warning
echo "WARNING: This will overwrite existing config"
read -p "Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

find ~/dotfiles -type f -name "*.sh" -exec chmod +x {} \;

# pacman packages
pacman_packages=(
	linux-lts-headers
	dkms
	git
	base-devel
	hyprland
	hyprlock
	hypridle
	hyprpaper
	sddm
	waybar
	nwg-dock-hyprland
	kitty
	nano
	nvim
	nautilus
	xdg-user-dirs
	xdg-user-dirs-gtk
	ttf-jetbrains-mono-nerd
	less
	blueman
	pavucontrol
	gnome-calculator
	network-manager-applet
	loupe
	celluloid
	jq
	xdg-desktop-portal
	xdg-desktop-portal-gtk
	xdg-desktop-portal-hyprland
	polkit-gnome
	eza
	swaync
	hyprshot
	nwg-drawer
	fastfetch
	locate
	papirus-icon-theme
	ttf-fira-sans
	ttf-font-awesome
	noto-fonts
	noto-fonts-emoji
	noto-fonts-cjk
	gnome-text-editor
    fd
)

echo ">> Updating package database..."
sudo pacman -Syu --noconfirm

echo ">> Installing packages..."
for pkg in "${pacman_packages[@]}"; do
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
	zen-browser-bin
	oh-my-posh
	nerd-fonts-complete-mono-glyphs
)

yay -Syu --noconfirm

for pkg in "${aur_packages[@]}"; do
	if yay -Qi "$pkg" &>/dev/null; then
		echo "[*] $pkg is already installed (AUR)"
	else
		echo "[+] Installing $pkg (AUR)..."
		yay -S --noconfirm "$pkg"
	fi
done

# install packages used by sun
suns_pacman=(
	spotify-launcher
	discord
	obs-studio
	veracrypt
    go
    rustup
    jdk-openjdk
    maven
)

suns_aur=(
	rtl8852au-dkms-git
	visual-studio-code-bin
	github-desktop-bin
	tetrio-desktop
	wps-office
	ttf-ms-win10-auto
	libtiff5
	ttf-wps-fonts
	google-chrome
    dotnet-sdk-bin
    beekeeper-studio-bin
)

read -p "Install apps and packages used by sun (may contain bloat)? (y/n): " install_sun

if [[ "$install_sun" == "y" || "$install_sun" == "Y" || "$install_sun" == "yes" || "$install_sun" == "YES" ]]; then
	echo ">> Installing pacman packages..."
	for pkg in "${suns_pacman[@]}"; do
	        if pacman -Qi "$pkg" &>/dev/null; then
	                echo "[*] $pkg is already installed"
	        else
	                echo "[+] Installing $pkg..."
	                sudo pacman -S --needed --noconfirm "$pkg"
	        fi
	done

	for pkg in "${suns_aur[@]}"; do
	        if yay -Qi "$pkg" &>/dev/null; then
	                echo "[*] $pkg is already installed (AUR)"
	        else
	                echo "[+] Installing $pkg (AUR)..."
	                yay -S --noconfirm "$pkg"
	        fi
	done
fi

# nvidia
read -p "Install NVIDIA drivers? (y/n): " install_nvidia

if [[ "$install_nvidia" == "y" || "$install_nvidia" == "Y" || "$install_nvidia" == "yes" || "$install_nvidia" == "YES" ]]; then
	echo "[+] Installing NVIDIA drivers..."
	sudo pacman -S --needed --noconfirm nvidia-lts nvidia-utils nvidia-settings
	
	# Create the suspend-hyprland.sh script
	sudo tee /usr/local/bin/suspend-hyprland.sh >/dev/null << 'EOF'
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
	sudo tee /etc/systemd/system/hyprland-suspend.service >/dev/null << 'EOF'
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
	sudo tee /etc/systemd/system/hyprland-resume.service >/dev/null << 'EOF'
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

	sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

	sudo mkinitcpio -P
else
	echo "[*] Skipping NVIDIA driver installation."
fi

# install dotfiles
mkdir ~/.config
cp -a ~/dotfiles/home/. ~/
cp -a ~/dotfiles/dotconfig/. ~/.config/
cd
rm -rf dotfiles/

# sddm
sudo systemctl enable sddm

# folders
xdg-user-dirs-update

# clear cache
echo "[-] Clearing cache"
yay -Sc --noconfirm

echo "[!] Done"

# restart
read -p "Do you want to restart now? [y/N]: " restart
case "$restart" in
    [yY][eE][sS]|[yY])
        echo "Rebooting..."
        reboot
        ;;
    *)
        echo "Skipped restart."
        ;;
esac
