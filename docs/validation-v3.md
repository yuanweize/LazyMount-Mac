# LazyMount 3.0.0 validation — 2026-10-25

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

## Limits

The important image remains Degraded: macOS refuses normal unmount. The owner subsequently confirmed a recoverable backup and authorized idle offline First Aid. A fresh identity/handle check passed, but normal unmount still failed. A safe offline maintenance opportunity is required for further repair. No claim is made that this image is repaired or that filesystem corruption was proven. Game workloads, reboot/wake, NAS outages, Intel and older macOS have not been physically validated.

Python 3.9+ is required. macOS 27 warns that hdiutil is deprecated; these commands worked in testing and retain older-macOS compatibility.
