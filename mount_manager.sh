#!/bin/bash

# ==========================================
#      LazyMount - Universal Mount Manager
#      Version: 3.0.2 (DiskImages2 ownership compatibility)
#      https://github.com/yuanweize/LazyMount-Mac
# ==========================================
#
# This script automatically mounts:
#   1. SMB shares from local/remote servers
#   2. Rclone cloud storage (via SFTP/etc.)
#
# Features:
#   - External config support (git-friendly)
#   - Auto-retry on network failure
#   - Clean logging to single file
#   - Works with Tailscale for remote access
#   - Complete-release updates through install.sh
#   - Background APFS health monitoring & auto-recovery
#
# ==========================================

# --- Script Version (for auto-update) ---
SCRIPT_VERSION="3.0.2"

# ====================
#   DEFAULT CONFIGURATION
# ====================
# ⚠️ DO NOT EDIT THIS SECTION DIRECTLY IF YOU WANT TO AVOID GIT CONFLICTS.
# Instead, create a file named 'mount_manager.local.sh' in the same directory
# and override the variables there. The script will load it automatically.

# --- Global Settings ---
LOG_FILE="$HOME/Library/Logs/LazyMount/manager.log"

# AUTO_UPDATE_ENABLED from v2 is ignored; use install.sh update.

# --- Rclone Configuration ---
RCLONE_ENABLED="true"
RCLONE_REMOTE="your-remote:/path/to/folder"        # Override in .local.sh
RCLONE_MOUNT_POINT="$HOME/Mounts/CloudStorage"     # Override in .local.sh
RCLONE_BIN="$(command -v rclone || true)"
RCLONE_IP="100.100.100.100"                        # Tailscale IP or 8.8.8.8

# Advanced Rclone Flags (Array for easy customization)
# Note: --volname is set dynamically based on RCLONE_MOUNT_POINT, do not hardcode it here.
RCLONE_MOUNT_ARGS=(
    "--vfs-cache-mode" "full"
    "--vfs-cache-max-size" "20G"
    "--vfs-cache-max-age" "24h"
    "--vfs-read-chunk-size" "64M"
    "--vfs-read-chunk-size-limit" "off"
    "--buffer-size" "128M"
    "--dir-cache-time" "30s"
    "--attr-timeout" "30s"
    "--vfs-cache-poll-interval" "15s"
    "--vfs-fast-fingerprint"
    "--no-checksum"
    "--no-modtime"
    "--async-read=true"
    "--exclude" ".DS_Store"
    "--exclude" "._*"
    "--log-level=INFO"
)

# --- SMB Configuration ---
SMB_ENABLED="true"
SMB_IP="192.168.1.100"                             # Override in .local.sh
SMB_USER="your_username"                           # Override in .local.sh
SMB_SHARE="SharedFolder"                           # Override in .local.sh
# SMB_URL is constructed dynamically below

# --- Sparse Bundle Configuration (Optional) ---
BUNDLE_PATH=""                                     # Override in .local.sh
BUNDLE_VOLUME_NAME=""                              # Override in .local.sh
# APFS is managed independently. No automatic filesystem repair without UUID approval.
BUNDLE_VOLUME_UUID=""
BUNDLE_REPAIR_APPROVED_UUID=""
BUNDLE_CHECK_INTERVAL=300
BUNDLE_RECOVERY_COOLDOWN=3600
# Legacy BUNDLE_MOUNT_ARGS is ignored; runtime selects the supported image backend.

# ====================
#   LOAD EXTERNAL CONFIG
# ====================
# This allows users to override the default configuration without modifying this main script,
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Redirect all output to log file (before config load so all messages are captured)
mkdir -p "$(dirname "$LOG_FILE")"
exec 1>>"$LOG_FILE" 2>&1

# --- Global log function ---
log() { echo "$(date +'%H:%M:%S') [$1] $2"; }

if [ -f "$SCRIPT_DIR/mount_manager.local.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/mount_manager.local.sh"
    log "Init" "Loaded external config: mount_manager.local.sh"
fi

# ====================
#   DYNAMIC VARIABLES
# ====================
# Dynamic Variables
SMB_URL="smb://${SMB_USER}@${SMB_IP}/${SMB_SHARE}"
SMB_MOUNT_POINT="/Volumes/${SMB_SHARE}"
RCLONE_VOLNAME="$(basename "$RCLONE_MOUNT_POINT")"

# Updates are installed as one tested release using ./install.sh update.
# Single-file background downloads could downgrade or split the installed release.

# --- Module 1: SMB Share Mounting ---
function mount_smb() {
    if [ "$SMB_ENABLED" != "true" ]; then
        log "SMB" "SMB mounting disabled. Skipping."
        return 0
    fi
    
    log "SMB" "Starting sequence..."
    
    # 1. Network detection
    local max_retries=60
    local count=0
    while ! /sbin/ping -c 1 -W 1 "$SMB_IP" &> /dev/null; do
        if [ $count -ge $max_retries ]; then
            log "SMB" "Error: Network timeout ($SMB_IP). Giving up."
            return 1
        fi
        sleep 2
        ((count++))
    done
    log "SMB" "Network OK."

    # 2. Mount SMB share
    local t_start t_end
    if [ ! -d "$SMB_MOUNT_POINT" ]; then
        log "SMB" "Mounting SMB share..."
        t_start=$(date +%s)
        
        /usr/bin/osascript -e "try" -e "mount volume \"${SMB_URL}\"" -e "end try"
        
        local wait_count=0
        while [ ! -d "$SMB_MOUNT_POINT" ]; do
            sleep 1
            ((wait_count++))
            if [ $wait_count -gt 30 ]; then 
                log "SMB" "Error: SMB mount timeout."
                return 1
            fi
        done
        t_end=$(date +%s)
        log "SMB" "SMB mounted successfully (Took $((t_end - t_start))s)."
    else
        log "SMB" "SMB already mounted."
    fi

    log "SMB" "Sequence finished."
}

# --- Module 2: Rclone Cloud Storage Mounting ---
function mount_rclone() {
    if [ "$RCLONE_ENABLED" != "true" ]; then
        log "Rclone" "Rclone mounting disabled. Skipping."
        return 0
    fi
    
    log "Rclone" "Starting..."

    # Adopt an existing mount; never force-unmount an independent Rclone mount.
    if mount | grep -qF " on ${RCLONE_MOUNT_POINT} "; then
        log "Rclone" "Existing mount retained."
        return 0
    fi
    /bin/mkdir -p "$RCLONE_MOUNT_POINT"

    # 2. Network detection
    local max_retries=60
    local count=0
    log "Rclone" "Checking network ($RCLONE_IP)..."
    while ! /sbin/ping -c 1 -W 1 "$RCLONE_IP" &> /dev/null; do
        if [ $count -ge $max_retries ]; then
            log "Rclone" "Error: Network timeout. Giving up."
            return 1
        fi
        sleep 2
        ((count++))
    done
    log "Rclone" "Network OK."

    # 3. Execute mount using array arguments
    # We use "${RCLONE_MOUNT_ARGS[@]}" to properly expand the array
    "$RCLONE_BIN" mount "$RCLONE_REMOTE" "$RCLONE_MOUNT_POINT" \
        "--volname" "$RCLONE_VOLNAME" \
        "${RCLONE_MOUNT_ARGS[@]}"
}

# ====================
#   Main Execution
# ====================
case "${1:-}" in
    --smb) mount_smb; exit $? ;;
    --rclone) mount_rclone; exit $? ;;
esac
export BUNDLE_PATH BUNDLE_VOLUME_NAME BUNDLE_VOLUME_UUID BUNDLE_REPAIR_APPROVED_UUID
export BUNDLE_CHECK_INTERVAL BUNDLE_RECOVERY_COOLDOWN SCRIPT_VERSION
PYTHON_BIN="${LAZYMOUNT_PYTHON:-$(command -v python3 || true)}"
if [ -z "$PYTHON_BIN" ]; then
    log Main "Python 3.9+ required; run install.sh."
    exit 1
fi
exec "$PYTHON_BIN" "$SCRIPT_DIR/lazymount_runtime.py" service
