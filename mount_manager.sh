#!/bin/bash

# ==========================================
#      LazyMount - Universal Mount Manager
#      Version: 2.0 (Modular & Configurable)
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
#
# ==========================================

# ====================
#   DEFAULT CONFIGURATION
# ====================
# ⚠️ DO NOT EDIT THIS SECTION DIRECTLY IF YOU WANT TO AVOID GIT CONFLICTS.
# Instead, create a file named 'mount_manager.local.sh' in the same directory
# and override the variables there. The script will load it automatically.

# --- Global Settings ---
LOG_FILE="/tmp/mount_manager.log"

# --- Rclone Configuration ---
RCLONE_ENABLED="true"
RCLONE_REMOTE="your-remote:/path/to/folder"        # Override in .local.sh
RCLONE_MOUNT_POINT="$HOME/Mounts/CloudStorage"     # Override in .local.sh
RCLONE_BIN="/usr/local/bin/rclone"
RCLONE_IP="100.100.100.100"                        # Tailscale IP or 8.8.8.8

# Advanced Rclone Flags (Array for easy customization)
RCLONE_MOUNT_ARGS=(
    "--volname" "CloudStorage"
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
# Custom hdiutil flags (e.g. -noverify, -readonly)
BUNDLE_MOUNT_ARGS=("-noverify" "-noautofsck" "-owners" "off")

# ====================
#   LOAD EXTERNAL CONFIG
# ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CONFIG="${SCRIPT_DIR}/mount_manager.local.sh"
USER_RC="${HOME}/.lazymountrc"

if [ -f "$LOCAL_CONFIG" ]; then
    echo "[Init] Loading local config: $LOCAL_CONFIG"
    source "$LOCAL_CONFIG"
elif [ -f "$USER_RC" ]; then
    echo "[Init] Loading user config: $USER_RC"
    source "$USER_RC"
fi

# Dynamic Variables (Constructed after loading config)
SMB_URL="smb://${SMB_USER}@${SMB_IP}/${SMB_SHARE}"
if [ -n "$SMB_SHARE_PATH" ]; then
    # Support for subfolders in SMB share if needed
    SMB_MOUNT_POINT="/Volumes/${SMB_SHARE}"
else
    SMB_MOUNT_POINT="/Volumes/${SMB_SHARE}"
fi

# ====================
#   MAIN LOGIC
# ====================

# Redirect all output to log file
exec 1>>"$LOG_FILE" 2>&1

echo "=== Mount Session Started: $(date) ==="

# --- Module 1: SMB Share Mounting ---
function mount_smb() {
    log() { echo "$(date +'%H:%M:%S') [SMB] $1"; }
    
    if [ "$SMB_ENABLED" != "true" ]; then
        log "SMB mounting disabled. Skipping."
        return 0
    fi
    
    log "Starting sequence..."
    
    # 1. Network detection
    local max_retries=60
    local count=0
    while ! ping -c 1 -W 1 $SMB_IP &> /dev/null; do
        if [ $count -ge $max_retries ]; then
            log "Error: Network timeout ($SMB_IP). Giving up."
            return 1
        fi
        sleep 2
        ((count++))
    done
    log "Network OK."

    # 2. Mount SMB share
    if [ ! -d "$SMB_MOUNT_POINT" ]; then
        log "Mounting SMB share..."
        local t_start=$(date +%s)
        
        /usr/bin/osascript -e "try" -e "mount volume \"${SMB_URL}\"" -e "end try"
        
        local wait_count=0
        while [ ! -d "$SMB_MOUNT_POINT" ]; do
            sleep 1
            ((wait_count++))
            if [ $wait_count -gt 30 ]; then 
                log "Error: SMB mount timeout."
                return 1
            fi
        done
        local t_end=$(date +%s)
        log "SMB mounted successfully (Took $((t_end - t_start))s)."
    else
        log "SMB already mounted."
    fi

    # 3. Mount sparse bundle (optional)
    if [ -n "$BUNDLE_PATH" ] && [ -n "$BUNDLE_VOLUME_NAME" ]; then
        if [ ! -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
            log "Mounting Sparse Bundle..."
            if [ -d "$BUNDLE_PATH" ]; then
                local t_start=$(date +%s)
                
                # Use configured arguments
                /usr/bin/hdiutil attach "$BUNDLE_PATH" "${BUNDLE_MOUNT_ARGS[@]}" -mountpoint "/Volumes/$BUNDLE_VOLUME_NAME"
                
                local t_end=$(date +%s)
                sleep 1
                
                if [ -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
                    log "Sparse Bundle mounted successfully (Took $((t_end - t_start))s)."
                else
                    log "Error: hdiutil finished but volume not found."
                fi
            else
                log "Error: Bundle file not found at $BUNDLE_PATH"
                return 1
            fi
        else
            log "Sparse Bundle already mounted."
        fi
    fi
    
    log "Sequence finished."
}

# --- Module 2: Rclone Cloud Storage Mounting ---
function mount_rclone() {
    if [ "$RCLONE_ENABLED" != "true" ]; then
        echo "$(date +'%H:%M:%S') [Rclone] Rclone mounting disabled. Skipping."
        return 0
    fi
    
    echo "$(date +'%H:%M:%S') [Rclone] Starting..."

    # 1. Cleanup old mount
    if [ -d "$RCLONE_MOUNT_POINT" ]; then
        echo "$(date +'%H:%M:%S') [Rclone] Cleaning up old mount..."
        /usr/sbin/diskutil unmount force "$RCLONE_MOUNT_POINT"
        sleep 2
    fi
    /bin/rm -rf "$RCLONE_MOUNT_POINT"
    /bin/mkdir -p "$RCLONE_MOUNT_POINT"

    # 2. Network detection
    local max_retries=60
    local count=0
    echo "$(date +'%H:%M:%S') [Rclone] Checking network ($RCLONE_IP)..."
    while ! /sbin/ping -c 1 -W 1 $RCLONE_IP &> /dev/null; do
        if [ $count -ge $max_retries ]; then
            echo "$(date +'%H:%M:%S') [Rclone] Error: Network timeout. Giving up."
            return 1
        fi
        sleep 2
        ((count++))
    done
    echo "$(date +'%H:%M:%S') [Rclone] Network OK."

    # 3. Execute mount using array arguments
    # We use "${RCLONE_MOUNT_ARGS[@]}" to properly expand the array
    $RCLONE_BIN mount "$RCLONE_REMOTE" "$RCLONE_MOUNT_POINT" \
        "${RCLONE_MOUNT_ARGS[@]}"
}

# ====================
#   Main Execution
# ====================

# Run SMB mounting in background
mount_smb &

# Run Rclone in foreground
mount_rclone
