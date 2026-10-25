# Changelog

## v3.0.2 — 2026-10-25

- Respect macOS's volume ownership policy when attaching APFS images. An explicit `owners` option in v3.0.1 caused `EACCES` at the root of an existing root-owned image, although its user-owned game directory remained writable. A controlled automatic DiskImages2 remount without that option restored default disabled ownership and passed root create/write/fsync/readback.
- Retain the DiskImages2 attachment strategy introduced in v3.0.1 where supported; older macOS uses the legacy backend only when the modern interface is unavailable.
- Document why a large sparsebundle can appear mounted while `diskutil image attach` continues enumerating band statistics. Do not interrupt this operation or run competing detach/repair operations.
- Align English/Chinese READMEs, troubleshooting guidance, architecture, and verification report with the v3 behavior. No user credentials or private configuration are committed.

## v3.0.1 — 2026-10-25

- Prefer native `diskutil image attach` (DiskImages2) on supported macOS after identifying the legacy `diskimages-helper` band `F_FULLSYNC` / ENOTSUP failure on the affected SMB-backed image.
- Verify the actual image UUID offline before filesystem checks; `diskutil verifyVolume` reported the volume and container clean and normal eject and write/fsync/readback succeeded without a modifying First Aid.
- Keep a safe legacy fallback on systems without the DiskImages2 interface, never automatically falling back to the old driver after a modern attachment failure.

## v3.0.0 — 2026-10-25

- Add per-user `install.sh` / `install.py` with old LaunchAgent migration, rollback, and preservation of existing local config.
- Replace directory/`df`-only APFS monitoring with exclusive random-file create/write/fsync/readback/cleanup and categorized errno reporting.
- Pin image identity using disk-image metadata, APFS physical stores, and volume UUID. Implement per-image locks, cooldown, safe normal eject, and backup/UUID-gated offline repair.
- Keep SMB and Rclone workers independent from APFS health failures. Add unit and disposable APFS integration tests.

See [docs/validation-v3.md](docs/validation-v3.md) for tested behavior and unverified scenarios. This project does not claim local-SSD reliability for network-backed sparsebundles.
