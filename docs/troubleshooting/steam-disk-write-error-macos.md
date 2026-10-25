# Steam disk write errors on macOS

A Steam write error can mean permissions, capacity, read-only state, filesystem
corruption or an I/O failure. A successful `df` does not rule these out.

1. Pause downloads and quit Steam/Epic normally. Do not kill writers or force-eject.
2. Inspect `~/Library/Logs/LazyMount/manager.log` for the failed probe stage and errno.
3. Let LazyMount attempt normal reattachment once the volume is idle. Open handles
   or failed inspection defer recovery. Reattachment respects the default macOS ownership policy.
4. Confirm a recoverable backup before allowing modifying First Aid. Follow the
   [APFS recovery guide](../guides/apfs-sparsebundle-nas-recovery.md).
5. Require `Verified` write/fsync/readback before resuming downloads. If the problem
   remains, preserve logs and investigate; do not repeatedly force-unmount or repair.

**How to distinguish the two observed failures:** legacy DiskImages may log
`flushBand F_FULLSYNC ... errno 45` and block both creates and normal eject on
some SMB-backed images. On supported macOS, the DiskImages2 backend avoided
this specific failure. Separately, forcing `--mountOptions owners` on a volume
whose root is owned by root may cause `EACCES (13)` on the volume root while
user-owned folders work. v3.0.2 now follows the macOS default ownership policy.
Inspect `diskutil info /Volumes/VOLUME` and
`ls -ldOe@ /Volumes/VOLUME` before changing ownership settings. Never mass-chown
the volume to disguise an ACL or identity issue.

The modern `diskutil image attach` command can take minutes to finish enumerating
the bands of a large image *after* the volume becomes accessible. Do not
overlap it with a second attach, eject, or First Aid. A real write/fsync/readback
test is necessary, but `Healthy` should only be declared when the background
attach command has finished.

No automatic process termination, band deletion, token removal, partition-map
repair or formatting is performed. SMB and independent Rclone/SFTP/WebDAV mounts
continue when APFS recovery is blocked. No NAS configuration is assumed to be the
cause merely because a sparsebundle is stored on SMB.
