# Steam disk write errors on macOS

A Steam write error can mean permissions, capacity, read-only state, filesystem
corruption or an I/O failure. A successful `df` does not rule these out.

1. Pause downloads and quit Steam/Epic normally. Do not kill writers or force-eject.
2. Inspect `~/Library/Logs/LazyMount/manager.log` for the failed probe stage and errno.
3. Let LazyMount attempt normal reattachment once the volume is idle. Open handles
   or failed inspection defer recovery. `-owners on` is explicit on reattachment.
4. Confirm a recoverable backup before allowing modifying First Aid. Follow the
   [APFS recovery guide](../guides/apfs-sparsebundle-nas-recovery.md).
5. Require `Verified` write/fsync/readback before resuming downloads. If the problem
   remains, preserve logs and investigate; do not repeatedly force-unmount or repair.

No automatic process termination, band deletion, token removal, partition-map
repair or formatting is performed. SMB and independent Rclone/SFTP/WebDAV mounts
continue when APFS recovery is blocked. No NAS configuration is assumed to be the
cause merely because a sparsebundle is stored on SMB.
