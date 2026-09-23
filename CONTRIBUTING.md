# Contributing to LazyMount-Mac

Thank you for contributing to LazyMount-Mac! LazyMount-Mac helps macOS users keep their network storage (SMB/Rclone) reliably mounted and automatically repairs corrupt APFS sparsebundles.

## How You Can Help

- **Testing**: Test across different macOS versions (macOS Sonoma, Sequoia, etc.) and NAS environments (Synology, TrueNAS, Unraid).
- **Bug Reports**: Open an issue detailing your macOS version, network setup, and sanitized logs.
  - **Important Log Sanitization**: Always redact passwords, mount tokens, user credentials, private filesystem paths, and sensitive internal IP addresses before posting logs publicly. For reports involving sensitive crash logs or credentials, use the private security channel in [SECURITY.md](SECURITY.md).
- **Pull Requests**: Shell script enhancements, improved error handling, and documentation updates.

## Script Guidelines

- Follow POSIX / Bash standards where applicable.
- Ensure scripts pass `shellcheck` when possible.
- Avoid hardcoded paths; use user configurations in `mount_manager.local.sh`.
