# Contributing to LazyMount-Mac

Thank you for contributing to LazyMount-Mac! LazyMount-Mac helps macOS users keep their network storage (SMB/Rclone) reliably mounted and automatically repairs corrupt APFS sparsebundles.

## How You Can Help

- **Testing**: Test across different macOS versions (macOS Sonoma, Sequoia, etc.) and NAS environments (Synology, TrueNAS, Unraid).
- **Bug Reports**: Open an issue detailing macOS version, network setup, and relevant logs.
- **Pull Requests**: Shell script enhancements, improved error handling, and documentation updates.

## Script Guidelines

- Follow POSIX / Bash standards where applicable.
- Ensure scripts pass `shellcheck` when possible.
- Avoid hardcoded paths; use user configurations in `mount_manager.local.sh`.
