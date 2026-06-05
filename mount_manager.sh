#!/bin/bash

# ==========================================
#      LazyMount - Universal Mount Manager
#      Version: 2.3 (APFS Health Monitor Fix)
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
#   - Auto-update from GitHub
#   - Background APFS health monitoring & auto-recovery
#
# ==========================================

# --- Script Version (for auto-update) ---
SCRIPT_VERSION="2.4"
GITHUB_RAW_URL="https://raw.githubusercontent.com/yuanweize/LazyMount-Mac/main/mount_manager.sh"

# ====================
#   DEFAULT CONFIGURATION
# ====================
# ⚠️ DO NOT EDIT THIS SECTION DIRECTLY IF YOU WANT TO AVOID GIT CONFLICTS.
# Instead, create a file named 'mount_manager.local.sh' in the same directory
# and override the variables there. The script will load it automatically.

# --- Global Settings ---
LOG_FILE="/tmp/mount_manager.log"
AUTO_UPDATE_ENABLED="true"                         # Set to "false" to disable auto-update

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
# Note: -noautofsck is kept to ensure APFS consistency on network shares.
# -noverify skips disk image checksum verification (not filesystem check)
# to reduce SMB I/O load during mount. APFS integrity is handled by -autofsck.
BUNDLE_MOUNT_ARGS=("-autofsck" "-noverify")

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
#   AUTO-UPDATE FUNCTION
# ====================
function check_and_update() {
    if [ "$AUTO_UPDATE_ENABLED" != "true" ]; then
        log "Update" "Auto-update disabled. Skipping."
        return 0
    fi
    
    log "Update" "Checking for updates (current version: $SCRIPT_VERSION) in background..."
    
    # Fetch remote script to temp file (with retries for slow boot networking)
    local temp_script="/tmp/mount_manager_update_$$.sh"
    local max_retries=12  # up to 60 seconds
    local retry_count=0
    local fetch_success=false
    
    while [ $retry_count -lt $max_retries ]; do
        if /usr/bin/curl -fsSL --connect-timeout 5 "$GITHUB_RAW_URL" -o "$temp_script" 2>/dev/null; then
            fetch_success=true
            break
        fi
        sleep 5
        ((retry_count++))
    done
    
    if [ "$fetch_success" != "true" ]; then
        log "Update" "Failed to fetch remote script after 60s. Skipping update."
        return 0
    fi
    
    # Extract version from remote script
    local remote_version
    remote_version=$(grep -E '^SCRIPT_VERSION=' "$temp_script" | head -1 | cut -d'"' -f2)
    
    if [ -z "$remote_version" ]; then
        log "Update" "Could not extract version from remote script. Skipping update."
        /bin/rm -f "$temp_script"
        return 0
    fi
    
    log "Update" "Remote version: $remote_version"
    
    # Compare versions (simple string comparison)
    if [ "$remote_version" = "$SCRIPT_VERSION" ]; then
        log "Update" "Already up to date."
        /bin/rm -f "$temp_script"
        return 0
    fi
    
    # Version differs, perform update
    log "Update" "New version available. Updating from $SCRIPT_VERSION to $remote_version..."
    
    # Backup current script
    local backup_script="${BASH_SOURCE[0]}.backup"
    /bin/cp "${BASH_SOURCE[0]}" "$backup_script"
    
    # Replace script with new version
    if /bin/mv "$temp_script" "${BASH_SOURCE[0]}"; then
        /bin/chmod +x "${BASH_SOURCE[0]}"
        log "Update" "Update successful. Backup saved to $backup_script"
        log "Update" "Please restart the script to use the new version."
        return 0
    else
        log "Update" "ERROR: Failed to replace script. Restoring backup..."
        /bin/cp "$backup_script" "${BASH_SOURCE[0]}"
        /bin/rm -f "$temp_script"
        return 1
    fi
}

# ====================
#   MAIN LOGIC
# ====================

# --- Health Monitor for Sparse Bundle ---
# NOTE: APFS on SMB backing store has a known limitation — APFS periodic sync()
# calls fail with ENOTSUP because SMB doesn't support the required fsync semantics.
# This causes `touch` and other write tests to hang/fail intermittently even when
# the volume is healthy. Therefore we use a LIGHTWEIGHT check strategy:
#   1. `df` to verify the volume is responsive (does NOT trigger APFS sync)
#   2. Only escalate to re-attach when the volume is completely unresponsive
#   3. Long intervals to minimize I/O pressure on the SMB share
function monitor_bundle_health() {
    local volume="/Volumes/$BUNDLE_VOLUME_NAME"
    local check_interval=300       # 5 minutes (reduce I/O pressure on SMB)
    local consecutive_failures=0
    local max_failures=3           # 3 failures × 5min = 15 min before recovery
    local recovery_cooldown=600    # 10 min cooldown after recovery
    
    log "Monitor" "Starting health monitor for $volume (interval=${check_interval}s, tolerance=$((check_interval * max_failures))s)"
    
    # Suppress Spotlight indexing (prevents mds from hammering APFS journal over SMB)
    /usr/bin/mdutil -i off "$volume" 2>/dev/null
    
    while true; do
        sleep "$check_interval"
        
        # Stop if volume directory disappeared (detached externally)
        if [ ! -d "$volume" ]; then
            log "Monitor" "Volume gone. Stopping monitor."
            break
        fi
        
        # Lightweight responsiveness check using `df`.
        # `df` reads mount metadata and does NOT trigger APFS sync/flush,
        # so it won't hit the ENOTSUP issue on SMB backing stores.
        # We use a 10s timeout — if df hangs, the volume is truly stuck.
        if /bin/df "$volume" &>/dev/null; then
            # Volume is responsive — reset failure counter
            if [ $consecutive_failures -gt 0 ]; then
                log "Monitor" "Volume responsive again. Resetting failure counter (was $consecutive_failures)."
            fi
            consecutive_failures=0
        else
            ((consecutive_failures++))
            log "Monitor" "WARNING: Volume unresponsive ($consecutive_failures/$max_failures)"
            
            if [ $consecutive_failures -ge $max_failures ]; then
                log "Monitor" "CRITICAL: Volume unresponsive for $((check_interval * max_failures))s. Detach + re-attach..."
                
                /usr/bin/hdiutil detach "$volume" -force 2>/dev/null
                sleep 5
                
                if [ -d "$BUNDLE_PATH" ]; then
                    /usr/bin/hdiutil attach "$BUNDLE_PATH" \
                        "${BUNDLE_MOUNT_ARGS[@]}" \
                        -mountpoint "$volume"
                    sleep 5
                    
                    # Suppress Spotlight to prevent index storm
                    /usr/bin/mdutil -i off "$volume" 2>/dev/null
                    
                    if /bin/df "$volume" &>/dev/null; then
                        log "Monitor" "Volume recovered. Cooling down ${recovery_cooldown}s..."
                        sleep "$recovery_cooldown"
                    else
                        log "Monitor" "ERROR: Volume still unresponsive after re-attach. Cooling down ${recovery_cooldown}s..."
                        sleep "$recovery_cooldown"
                    fi
                else
                    log "Monitor" "ERROR: Bundle path inaccessible. SMB down?"
                    break
                fi
                consecutive_failures=0
            fi
        fi
    done
}

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
                local hdiutil_exit=$?
                
                t_end=$(date +%s)
                sleep 1
                
                if [ $hdiutil_exit -ne 0 ]; then
                    log "SMB" "WARNING: hdiutil attach exited with code $hdiutil_exit"
                fi
                
                if [ -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
                    log "SMB" "Sparse Bundle mounted successfully (Took $((t_end - t_start))s)."
                    
                    # --- Post-mount health check ---
                    # Check if volume is mounted read-only (indicates APFS corruption).
                    # NOTE: We use `mount` flags instead of `touch` because APFS on SMB
                    # backing store always fails sync() with ENOTSUP, making touch unreliable.
                    local mount_flags
                    mount_flags=$(mount | grep " on /Volumes/$BUNDLE_VOLUME_NAME " | head -1)
                    if echo "$mount_flags" | grep -q "read-only"; then
                        log "SMB" "WARNING: Volume is READ-ONLY. Running fsck + remount..."
                        
                        # 1. Detach the broken mount
                        /usr/bin/hdiutil detach "/Volumes/$BUNDLE_VOLUME_NAME" -force 2>/dev/null
                        sleep 2
                        
                        # 2. Attach WITHOUT mounting, to get the device node for fsck
                        log "SMB" "Attaching bundle for filesystem repair..."
                        local attach_output dev_node whole_disk
                        attach_output=$(/usr/bin/hdiutil attach -nomount -noverify -noautofsck "$BUNDLE_PATH" 2>&1)
                        log "SMB" "Nomount attach output: $attach_output"
                        # Get the APFS partition device node (e.g. /dev/disk5s1)
                        dev_node=$(echo "$attach_output" | grep "Apple_APFS" | grep -oE '/dev/disk[0-9]+s[0-9]+' | head -1)
                        if [ -z "$dev_node" ]; then
                            # Fallback: get the container device
                            dev_node=$(echo "$attach_output" | grep -oE '/dev/disk[0-9]+' | head -1)
                        fi
                        
                        if [ -n "$dev_node" ]; then
                            # 3. Run fsck_apfs on the device node
                            log "SMB" "Running fsck_apfs on $dev_node..."
                            local fsck_output
                            fsck_output=$(/sbin/fsck_apfs -y "$dev_node" 2>&1)
                            log "SMB" "fsck_apfs result: $fsck_output"
                            
                            # 4. Detach using the whole disk device
                            whole_disk=$(echo "$dev_node" | grep -oE '/dev/disk[0-9]+')
                            /usr/bin/hdiutil detach "$whole_disk" -force 2>/dev/null
                            sleep 2
                        else
                            log "SMB" "WARNING: Could not get device node for fsck."
                        fi
                        
                        # 5. Re-attach the bundle (now with fsck already done)
                        log "SMB" "Re-attaching sparse bundle..."
                        /usr/bin/hdiutil attach "$BUNDLE_PATH" "${BUNDLE_MOUNT_ARGS[@]}" -mountpoint "/Volumes/$BUNDLE_VOLUME_NAME"
                        sleep 2
                        
                        # 6. Verify read-only flag is gone
                        mount_flags=$(mount | grep " on /Volumes/$BUNDLE_VOLUME_NAME " | head -1)
                        if echo "$mount_flags" | grep -q "read-only"; then
                            log "SMB" "ERROR: Volume still read-only after fsck. Manual intervention required."
                        else
                            log "SMB" "Volume is now read-write after fsck repair."
                        fi
                    else
                        log "SMB" "Volume is read-write. Health OK."
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
        
        # Start health monitor if volume is mounted
        if [ -d "/Volumes/$BUNDLE_VOLUME_NAME" ]; then
            monitor_bundle_health &
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

# Clean up background processes on exit
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Run auto-update check in the background (so it doesn't block mounting)
( check_and_update ) &

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
