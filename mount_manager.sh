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
# Custom hdiutil flags (e.g. -noverify, -readonly)
# Note: -noautofsck and -noverify are REMOVED by default to ensure APFS
# consistency on network shares. Skipping fsck can leave the volume in
# a dirty state after unclean SMB disconnect, causing read-only mounts.
BUNDLE_MOUNT_ARGS=("-autofsck" "-verify" "-owners" "off")

# ====================
#   LOAD EXTERNAL CONFIG
# ====================
# This allows users to override the default configuration without modifying this main script,
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Redirect all output to log file (before config load so all messages are captured)
exec 1>>"$LOG_FILE" 2>&1

# --- Global log function ---
log() { echo "$(date +'%H:%M:%S') [$1] $2"; }

if [ -f "$SCRIPT_DIR/mount_manager.local.sh" ]; then
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

# ====================
#   MAIN LOGIC
# ====================

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

    # 3. Mount sparse bundle (optional)
    if [ -n "$BUNDLE_PATH" ] && [ -n "$BUNDLE_VOLUME_NAME" ]; then
        if [ ! -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
            log "SMB" "Mounting Sparse Bundle..."
            if [ -d "$BUNDLE_PATH" ]; then
                t_start=$(date +%s)
                
                # Use configured arguments
                /usr/bin/hdiutil attach "$BUNDLE_PATH" "${BUNDLE_MOUNT_ARGS[@]}" -mountpoint "/Volumes/$BUNDLE_VOLUME_NAME"
                
                t_end=$(date +%s)
                sleep 1
                
                if [ -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
                    log "SMB" "Sparse Bundle mounted successfully (Took $((t_end - t_start))s)."
                    
                    # --- Post-mount health check ---
                    # Check if volume is writable (not stuck in read-only mode)
                    local test_file="/Volumes/$BUNDLE_VOLUME_NAME/.lazymount_write_test"
                    if touch "$test_file" 2>/dev/null; then
                        rm -f "$test_file"
                        log "SMB" "Volume is writable. Health OK."
                    else
                        log "SMB" "WARNING: Volume is READ-ONLY. Running fsck + remount..."
                        
                        # 1. Detach the broken mount
                        /usr/bin/hdiutil detach "/Volumes/$BUNDLE_VOLUME_NAME" -force 2>/dev/null
                        sleep 2
                        
                        # 2. Attach WITHOUT mounting, to get the device node for fsck
                        log "SMB" "Attaching bundle for filesystem repair..."
                        local dev_node
                        dev_node=$(/usr/bin/hdiutil attach -nomount -noverify -noautofsck "$BUNDLE_PATH" 2>&1 | grep -oE '/dev/disk[0-9]+' | head -1)
                        
                        if [ -n "$dev_node" ]; then
                            # 3. Run fsck_apfs on the raw device node
                            log "SMB" "Running fsck_apfs on $dev_node..."
                            local fsck_output
                            fsck_output=$(/sbin/fsck_apfs -q -y "$dev_node" 2>&1)
                            log "SMB" "fsck_apfs result: $fsck_output"
                            
                            # 4. Detach the nomount attachment
                            /usr/bin/hdiutil detach "$dev_node" -force 2>/dev/null
                            sleep 2
                        else
                            log "SMB" "WARNING: Could not get device node for fsck. Trying diskutil repair..."
                        fi
                        
                        # 5. Re-attach the bundle (now with fsck already done)
                        log "SMB" "Re-attaching sparse bundle..."
                        /usr/bin/hdiutil attach "$BUNDLE_PATH" "${BUNDLE_MOUNT_ARGS[@]}" -mountpoint "/Volumes/$BUNDLE_VOLUME_NAME"
                        sleep 2
                        
                        # 6. Verify writability
                        if touch "$test_file" 2>/dev/null; then
                            rm -f "$test_file"
                            log "SMB" "Volume is now writable after fsck repair."
                        else
                            log "SMB" "ERROR: Volume still read-only after fsck. Manual intervention required."
                        fi
                    fi
                else
                    log "SMB" "Error: hdiutil finished but volume not found."
                fi
            else
                log "SMB" "Error: Bundle file not found at $BUNDLE_PATH"
                return 1
            fi
        else
            log "SMB" "Sparse Bundle already mounted."
        fi
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

    # 1. Cleanup old mount
    if [ -d "$RCLONE_MOUNT_POINT" ]; then
        log "Rclone" "Cleaning up old mount..."
        if /usr/sbin/diskutil unmount force "$RCLONE_MOUNT_POINT" 2>/dev/null; then
            log "Rclone" "Old mount unmounted successfully."
            sleep 2
        else
            log "Rclone" "WARNING: diskutil unmount failed. Checking if still mounted..."
            if mount | grep -qF " on ${RCLONE_MOUNT_POINT} "; then
                log "Rclone" "ERROR: Mount point still active after unmount attempt. Aborting cleanup."
                return 1
            fi
        fi
        /bin/rm -rf "$RCLONE_MOUNT_POINT"
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

echo "=== Mount Session Started: $(date) ==="

# Run SMB mounting in background
mount_smb &
SMB_PID=$!

# Run Rclone in foreground
mount_rclone
RCLONE_EXIT=$?

# Wait for SMB background process to finish
wait "$SMB_PID"
SMB_EXIT=$?

log "Main" "Finished. SMB exit=$SMB_EXIT, Rclone exit=$RCLONE_EXIT"
