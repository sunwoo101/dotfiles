#!/usr/bin/env bash
set -euo pipefail

# On ARM, Mesa already bundles the open-source GPU drivers:
#   Panfrost  — Mali Midgard / Bifrost / Valhall (T-series, G-series)
#   Lima      — Mali-400 / Mali-450
#   Freedreno — Qualcomm Adreno (OpenGL only; Vulkan/Turnip is AUR)
#   v3dv      — Broadcom VideoCore VI (Raspberry Pi 4 / 5)
#   Etnaviv   — Vivante GCxxx
# All of these are active via the mesa package already installed.
# Vulkan on ARM (vulkan-panfrost, turnip) requires AUR and is not covered here.

echo "ARM GPU: OpenGL drivers for Panfrost, Lima, Freedreno, v3dv, and Etnaviv"
echo "are provided by mesa — no extra packages needed."
echo "Vulkan acceleration requires AUR packages (vulkan-panfrost, turnip)."
