# APFS sparsebundle detection and safe recovery (v3)

A mounted APFS volume can report writable while file creation returns ENOTSUP.
Neither directory existence, `df`, nor `diskutil info` alone proves write health.
LazyMount tests a random exclusive 4 KiB file: create, write, fsync, reopen/read,
compare, delete. It does not open game files. Probe deadline: 10 seconds. A
kernel-stuck probe blocks further APFS recovery rather than overlapping operations.

## State and safety

`Healthy → Degraded → Recovering → Verified`; unsuccessful recovery stays Degraded.
Permission/capacity/sync failures are reported without invoking First Aid. Timeouts
also block recovery. I/O and read-only failures can trigger normal reattachment,
with a persistent one-hour cooldown. The service remains alive independently of
SMB and Rclone workers. No periodic filesystem scan and no unconditional boot repair.

Identity is derived from `hdiutil info -plist`, `diskutil apfs list -plist` and
`diskutil info -plist`: exact image path, owning UID, physical stores, container,
volume UUID and mountpoint. The first unambiguous UUID is pinned in the private
state directory; optionally configure `BUNDLE_VOLUME_UUID` before first use.
State/locks: `~/Library/Application Support/LazyMount`; logs:
`~/Library/Logs/LazyMount/manager.log`. Changing the configured image's UUID requires
reviewing and removing that image's saved state while the service is stopped.

Close Steam/Epic and other writers normally. Recovery checks handles with lsof,
then requests normal `diskutil unmountDisk`. Busy or uncertain inspection aborts;
there is no force option, game termination, formatting, token deletion or band edit.
Normal reattachment explicitly uses `-owners on` and validates actual writes.

## First Aid and command semantics

Apple recommends a current backup before First Aid, and checking volumes, then
containers, then the device in Disk Utility. LazyMount implements the **APFS
volume/container filesystem portion**, not every GUI check or partition-map repair.
Disk Utility's exact private invocation is not assumed to be a stable API.

| Command | Meaning and use |
| --- | --- |
| `diskutil verifyVolume` | Invokes the appropriate fsck; verifies underlying APFS storage and target volume. Can support live verification, which may block I/O. Not a cheap health probe. |
| `diskutil repairVolume` | Invokes the filesystem repair tool and repairs underlying storage plus target volume. Requires writable media and an unmountable target; LazyMount first requires all container volumes unmounted. |
| `fsck_apfs -n` | Verification without repair. Direct invocation needs the correct raw device and safe offline/live-mode handling. |
| `fsck_apfs -y` | Attempts repairs; modifies metadata. Not intrinsically non-destructive. LazyMount delegates to diskutil instead. |
| `fsck_apfs -x` | XML output. **Does not mount read-only on failure.** |
| `hdiutil -autofsck` | Forces filesystem checking before mounting. Not used on every normal mount. |
| `hdiutil -noautofsck` | Does not force automatic checking; does not establish filesystem health. |
| `hdiutil -noverify` | Skips image checksum verification, not filesystem verification. v3 does not require this optimization. |
| `hdiutil attach -nomount` | Exposes image devices without mounting volumes, for deliberate offline diagnosis. |

After a failed write and unsuccessful normal reattachment, filesystem repair is
allowed only when `BUNDLE_REPAIR_APPROVED_UUID` matches the pinned volume UUID.
Set it in the private local config **only after confirming a recoverable backup**.
The service then unmounts normally, verifies offline, repairs if verification
fails, checks the repair exit status, verifies again, mounts and probes writes.
Any failure stops the sequence. It never guesses a device number or falls back
to repairing an arbitrary whole disk. With an already pinned and approved UUID, failed normal attachment can fall back
to `-nomount` for offline recovery. If the image cannot attach at all or its APFS
identity cannot be resolved, automated repair fails closed and needs manual diagnosis.

If write checks still fail after a successful filesystem verification, investigate
permissions, ownership, storage I/O and unsupported sync separately. Do not repeat
First Aid in a tight loop. A `Verified` result proves this small file operation,
not every game workload or survival of a NAS power loss.

Sources: [Apple First Aid guide](https://support.apple.com/en-us/102611), and the
installed macOS `man diskutil`, `man fsck_apfs`, `man hdiutil`. The command behavior
above was checked on macOS 27.0.1; older supported APFS systems still need runtime
qualification. Python 3.9+ is required on both Intel and Apple Silicon.
