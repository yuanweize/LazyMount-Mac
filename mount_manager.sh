#!/bin/bash

# ==========================================
#      LazyMount - Universal Mount Manager
#      Version: 1.5 (Robust)
#      https://github.com/yuanweize/LazyMount-Mac
# ==========================================
#
# This script automatically mounts:
#   1. SMB shares from local/remote servers
#   2. Rclone cloud storage (via SFTP/etc.)
#
# Features:
#   - Auto-retry on network failure (60 retries × 2s = 120s timeout)
#   - Clean logging to single file
#   - Works with Tailscale for remote access
#   - LaunchAgent integration for boot-time mounting
#
# ==========================================

# ====================
#   USER CONFIGURATION - EDIT THESE VALUES
# ====================

# --- Global Settings ---
LOG_FILE="/tmp/mount_manager.log"

# --- Rclone Configuration ---
# Set RCLONE_ENABLED="false" to disable Rclone mounting
RCLONE_ENABLED="true"
RCLONE_REMOTE="your-remote:/path/to/folder"        # Rclone remote name and path
RCLONE_MOUNT_POINT="$HOME/Mounts/CloudStorage"     # Where to mount locally
RCLONE_BIN="/usr/local/bin/rclone"                 # Path to rclone binary
RCLONE_IP="100.x.x.x"                              # IP to ping for network check (Tailscale IP recommended)

# --- SMB Configuration ---
# Set SMB_ENABLED="false" to disable SMB mounting
SMB_ENABLED="true"
SMB_IP="192.168.1.100"                             # SMB server IP
SMB_USER="your_username"                           # SMB username
SMB_SHARE="SharedFolder"                           # SMB share name
SMB_URL="smb://${SMB_USER}@${SMB_IP}/${SMB_SHARE}"
SMB_MOUNT_POINT="/Volumes/${SMB_SHARE}"

# --- Sparse Bundle Configuration (Optional) ---
# Leave empty to disable sparse bundle mounting
BUNDLE_PATH=""                                     # e.g., "$SMB_MOUNT_POINT/Storage.sparsebundle"
BUNDLE_VOLUME_NAME=""                              # e.g., "ExternalStorage"

# ====================
#   END OF USER CONFIGURATION
# ====================

# Redirect all output to log file
exec 1>>"$LOG_FILE" 2>&1

echo "=== Mount Session Started: $(date) ==="

# ==========================================
#   Module 1: SMB Share Mounting
# ==========================================
function mount_smb() {
    log() { echo "$(date +'%H:%M:%S') [SMB] $1"; }
    
    if [ "$SMB_ENABLED" != "true" ]; then
        log "SMB mounting disabled. Skipping."
        return 0
    fi
    
    log "Starting sequence..."
    
    # 1. Network detection with timeout
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
        
        # Use osascript to avoid Finder popup dialogs
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
                
                # -owners off: Ignore ownership for better compatibility
                /usr/bin/hdiutil attach "$BUNDLE_PATH" -noverify -noautofsck -owners off -mountpoint "/Volumes/$BUNDLE_VOLUME_NAME"
                
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

# ==========================================
#   Module 2: Rclone Cloud Storage Mounting
# ==========================================
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

    # 2. Network detection with timeout
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

    # 3. Execute mount
    # Adjust these parameters based on your needs:
    #   --vfs-cache-max-size: Local cache size (increase for better performance)
    #   --dir-cache-time: How long to cache directory listings
    #   --vfs-cache-mode full: Full caching for best compatibility
    $RCLONE_BIN mount $RCLONE_REMOTE $RCLONE_MOUNT_POINT \
        --volname "CloudStorage" \
        --vfs-cache-mode full \
        --vfs-cache-max-size 20G \
        --vfs-cache-max-age 24h \
        --vfs-read-chunk-size 64M \
        --vfs-read-chunk-size-limit off \
        --buffer-size 128M \
        --dir-cache-time 30s \
        --attr-timeout 30s \
        --vfs-cache-poll-interval 15s \
        --vfs-fast-fingerprint \
        --no-checksum \
        --no-modtime \
        --async-read=true \
        --exclude ".DS_Store" \
        --exclude "._*" \
        --log-level=INFO
}

# ==========================================
#   Main Execution
# ==========================================

# Run SMB mounting in background (finishes quickly)
mount_smb &

# Run Rclone in foreground (stays alive)
# If Rclone exits or network times out, script ends and LaunchAgent restarts it
mount_rclone
