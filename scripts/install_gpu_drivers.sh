#!/usr/bin/env bash
set -euo pipefail

echo "detected GPU(s):"
lspci | grep -iE "VGA|3D|Display" | sed 's/^/  /'
echo
echo "  1) AMD"
echo "  2) Intel"
echo "  3) NVIDIA (proprietary)"
echo "  4) NVIDIA (open — Turing 16xx/20xx+)"
echo "  5) Skip"
echo

while true; do
    read -rp "Pick GPU driver [1-5]: " choice
    case "$choice" in
        1)
            echo "installing AMD drivers"
            sudo pacman -S --needed --noconfirm \
                vulkan-radeon lib32-vulkan-radeon libva-mesa-driver mesa-vdpau
            break
            ;;
        2)
            echo "installing Intel drivers"
            sudo pacman -S --needed --noconfirm \
                vulkan-intel lib32-vulkan-intel intel-media-driver
            break
            ;;
        3)
            echo "installing NVIDIA proprietary drivers"
            sudo pacman -S --needed --noconfirm \
                nvidia nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
            echo "note: for Hyprland on NVIDIA you may need:"
            echo "  - 'nvidia_drm.modeset=1' in kernel boot params"
            echo "  - LIBVA_DRIVER_NAME=nvidia, GBM_BACKEND=nvidia-drm,"
            echo "    __GLX_VENDOR_LIBRARY_NAME=nvidia (in environment.d)"
            break
            ;;
        4)
            echo "installing NVIDIA open kernel modules"
            sudo pacman -S --needed --noconfirm \
                nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
            break
            ;;
        5)
            echo "skipping GPU driver install"
            break
            ;;
        *)
            echo "invalid choice, enter 1-5"
            ;;
    esac
done
