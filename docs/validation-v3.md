# LazyMount 3.0.0–3.0.2 validation — 2026-10-25

## Confirmed v2.4 defects

Already-mounted sparsebundles skipped write checks. The monitor relied on df without its claimed timeout. Recovery forced detach, ignored fsck exit status and guessed device nodes. Nested monitors lacked supervision. Plist renames did not migrate existing Labels; the single-file updater could downgrade an installation.

The affected host reproduced ENOTSUP (errno 45) when creating a dedicated probe file despite writable flags. Ownership was disabled. This proves a write failure, not its underlying filesystem cause. Normal volume/container unmount and hdiutil detach were refused. No forced detach or modifying First Aid was performed on the important image before backup confirmation.

## Validation

- Bash syntax, ShellCheck 0.11.0, Python compilation, git diff checks.
- Unit tests: mounted-unwritable, corrupt attach, device renumbering, wrong physical store, failed repair, error classification, busy volume, duplicate lock, cooldown, backup approval, legacy Label migration, config preservation through update/uninstall.
- Real disposable 128 MiB APFS image: attach, write/fsync/readback, normal reattach, offline verify/repair/verify, remount and probe.
- Real read-only mount: EROFS detected, automatically recovered to Verified.
- Damaged disposable image header: rejected safely without guessing a repair target.
- Local installation migrated to com.lazymount; configuration bytes preserved.

Run `python3 -m unittest discover -s tests -v` and opt-in `LAZYMOUNT_TEST_APFS=1 python3 tests/integration_apfs.py`. Integration retains temporary artifacts and normally detaches its images.

## Initial v3.0.0 limits (superseded by follow-up below)

The important image remains Degraded: macOS refuses normal unmount. The owner subsequently confirmed a recoverable backup and authorized idle offline First Aid. A fresh identity/handle check passed, but normal unmount still failed. A safe offline maintenance opportunity is required for further repair. No claim is made that this image is repaired or that filesystem corruption was proven. Game workloads, reboot/wake, NAS outages, Intel and older macOS have not been physically validated.

Python 3.9+ is required. macOS 27 warns that hdiutil is deprecated; these commands worked in testing and retain older-macOS compatibility.

## Follow-up: backend differential diagnosis

After the owner manually force-ejected the stuck image, the service was stopped
for controlled diagnosis. macOS logs showed legacy DiskImages `flushBand:
F_FULLSYNC failed ... band_res=45` and Disk Arbitration unmount status 0x2D.
The same NAS with a disposable APFS image attached through DiskImages2 passed
write/fsync/readback and normal eject. This supports selecting the modern
`diskutil image attach` backend where available rather than treating ENOTSUP as
healthy, repeatedly repairing, or merely toggling ownership.

v3.0.1 capability-detects the modern interface, uses it for normal and offline
attachment, and uses normal diskutil eject. Older systems retain hdiutil. Modern
attachment failures do not trigger fallback to the failing legacy driver.

### Actual image acceptance on v3.0.1

The important image was attached through DiskImages2 without mounting. Its pinned
UUID was confirmed. Offline `diskutil verifyVolume` ran `fsck_apfs -n -x` and
reported both volume and container OK, exit 0. No modifying repair was needed.
It was then mounted through Disk Arbitration, passed exclusive small-file
write/fsync/readback, and successfully ejected **normally**, without force.
This resolves the previously observed write/eject failure in this session.
The evidence points to the legacy DiskImages backing-store flush path, not
proven filesystem corruption; ownership alone was not isolated as the cause.

Large-image attach took several minutes enumerating band allocation for CLI
output; process sampling distinguished this from the earlier F_FULLSYNC failure.
The runtime now also lets Disk Arbitration create a missing default /Volumes
mountpoint during offline recovery, avoiding a root-only mkdir requirement.

## v3.0.2 ownership regression and automatic mount acceptance

An automated v3.0.1 attach with `diskutil image attach --mountOptions owners`
successfully used DiskImages2, but changed the mounted volume's effective
ownership behavior: `diskutil info` reported `Owners: Enabled`, its root
was `root:wheel` with mode 775, and the dedicated 4 KiB root probe returned
`EACCES (13)` during create. The pre-existing SteamLibrary subdirectory was
user-owned and successfully passed create/write/fsync/readback in the same
mount. This was a permissions regression, **not a return of ENOTSUP**.
The attach CLI also spent about ten minutes scanning sparsebundle bands for
image-info output *after* Disk Arbitration had mounted the filesystem; sampling
showed `DiskImageSparseBundle::count_mapped_bytes`, not `F_FULLSYNC`.

v3.0.2 removes the explicit ownership override for both DiskImages2 and the
legacy fallback, deferring to the macOS volume default. In a controlled
maintenance sequence, the service was booted out, `lsof` showed no APFS
handles, and `diskutil eject disk4` succeeded normally (no force). The
v3.0.2 installer then migrated/restarted `com.lazymount` without touching
local configuration. Its launchd worker issued
`diskutil image attach --plist --mountPoint /Volumes/SMB_APFS`. The real
image remounted through DiskImages2, macOS reported `Owners: Disabled`, its
root appeared owned by the current user, and the dedicated probe returned
`{"ok": true}` (create/write/fsync/readback/cleanup), without modifying
First Aid. A previous direct DiskImages2 attach had also passed normal eject.

**Final launchd acceptance:** the large-image `diskutil image attach`
command exited, and at **2026-10-25 18:07:04 local time** the v3.0.2 service
logged `APFS Healthy: write/fsync/readback passed`. The private image state
also records `Healthy`, `hdiutil info` identifies its backend as
`DiskImages2`, and launchctl shows only `com.lazymount` for this project.
Thus both the independently invoked probe *and* the real background worker
completed successfully. The time-consuming CLI image-info enumeration
remains a known performance limitation, not evidence of filesystem corruption.

### Regression coverage and remaining limits

- `python3 -m unittest discover -s tests -v`: **20 passed**.
- `shellcheck mount_manager.sh install.sh`: no findings.
- Disposable 128 MiB APFS: mount, healthy probe, normal recovery, offline
  verify/repair/verify, read-only recovery, broken header rejection **passed**.
- Production image (644.2 GB logical APFS container): DiskImages2 mount and
  independent root write/fsync/readback **passed** with default ownership;
  no forced eject or modifying First Aid.
- No full reboot/wake, Intel, older macOS, concurrent Steam game update,
  or NAS-disconnect endurance test has yet been performed.
- No automatic chown, chmod, ownership bypass, or system-wide TCC change was
  performed. Credentials and private local configuration were never committed.
