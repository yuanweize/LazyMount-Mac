#!/bin/bash
# shellcheck disable=SC2034

# ==========================================
# Local Override Config (mount_manager.local.sh)
# ==========================================
# Copy this file to mount_manager.local.sh and fill in your settings.
# This file is git-ignored, safe to store personal config.

# --- Global Settings ---
# Updates: run ./install.sh update from an updated repository checkout.

# --- Rclone Configuration ---
# RCLONE_ENABLED="true"                          # Set to "false" to disable Rclone mounting
RCLONE_REMOTE="your-remote:/path/to/folder"      # Your rclone remote name and path
RCLONE_MOUNT_POINT="$HOME/Mounts/CloudStorage"   # Local mount point path
RCLONE_IP="100.100.100.100"                      # IP for network check (Tailscale users: use Tailscale IP; local users: use 8.8.8.8 or any reachable IP)

# --- SMB Configuration ---
# SMB_ENABLED="true"                             # Set to "false" to disable SMB mounting
SMB_IP="192.168.1.100"                           # NAS/Server IP (Tailscale users: use Tailscale IP for remote access)
SMB_USER="your_username"                         # SMB username
SMB_SHARE="SharedFolder"                         # Share folder name

# --- Sparse Bundle Configuration (Optional) ---
# Leave these empty or commented out if you don't need an encrypted disk image.
# NOTE: BUNDLE_PATH depends on $SMB_SHARE — make sure SMB_SHARE is defined above.
BUNDLE_PATH="/Volumes/$SMB_SHARE/my_secure_disk.sparsebundle"
BUNDLE_VOLUME_NAME="MyPrivateDisk"

# Optional identity pin and explicit backup approval. Leave approval empty by default.
BUNDLE_VOLUME_UUID=""
BUNDLE_REPAIR_APPROVED_UUID=""
BUNDLE_CHECK_INTERVAL=300
BUNDLE_RECOVERY_COOLDOWN=3600
