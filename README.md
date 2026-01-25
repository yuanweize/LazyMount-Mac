# LazyMount-Mac 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)

**[📖 中文文档](README_CN.md)**

> **Expand your Mac storage effortlessly** — Auto-mount SMB shares and cloud storage at boot, with zero manual intervention.

---

## ✨ Why LazyMount?

Mac storage is **expensive** — a 1TB upgrade can cost $200+. LazyMount solves this by seamlessly extending your Mac with external storage:

- 🎮 **Game Libraries** — Store Steam/Epic games on a NAS, play them like local installs
- 💾 **Time Machine Backups** — Back up to a remote server automatically
- 🎬 **Media Libraries** — Access your movie/music collection stored on a home server
- 📁 **Project Archives** — Keep large files on cheaper storage, access them on-demand
- ☁️ **Cloud Storage** — Mount Google Drive, Dropbox, or any rclone-supported service as a local folder

**Key Features:**
- 🔄 **Auto-mount at login** — No manual clicking required
- 🛡️ **Self-healing** — Reconnects automatically after network failures
- 🌐 **Works anywhere** — Access home storage remotely via Tailscale
- ⚡ **Dual-mode** — Supports both SMB (local) and Rclone (cloud/remote)

---

## 📦 Installation

### Prerequisites

1. **Rclone** (for cloud storage mounting):
   ```bash
   brew install rclone
   # Then configure your remote:
   rclone config
   ```

2. **macFUSE** (required for Rclone):
   ```bash
   brew install --cask macfuse
   ```

3. **(Recommended) Tailscale** — For remote access to home network:
   ```bash
   brew install --cask tailscale
   ```

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yuanweize/LazyMount-Mac.git
cd LazyMount-Mac

# 2. Copy script to your Scripts folder
mkdir -p ~/Scripts
cp mount_manager.sh ~/Scripts/
chmod +x ~/Scripts/mount_manager.sh

# 3. Edit the script with YOUR settings
nano ~/Scripts/mount_manager.sh  # or use any editor

# 4. Install LaunchAgent for auto-start
cp com.example.mountmanager.plist ~/Library/LaunchAgents/com.lazymount.plist
# Edit the plist to use your username:
sed -i '' "s/YOUR_USERNAME/$(whoami)/g" ~/Library/LaunchAgents/com.lazymount.plist

# 5. Load it!
launchctl load ~/Library/LaunchAgents/com.lazymount.plist
```

---

## ⚙️ Configuration

Edit `~/Scripts/mount_manager.sh` and modify the **USER CONFIGURATION** section:

### SMB Share Settings

```bash
SMB_ENABLED="true"
SMB_IP="192.168.1.100"           # Your NAS/Server IP
SMB_USER="your_username"         # SMB username
SMB_SHARE="SharedFolder"         # Share name
```

### Rclone Settings

```bash
RCLONE_ENABLED="true"
RCLONE_REMOTE="myremote:/path"   # Your rclone remote
RCLONE_MOUNT_POINT="$HOME/Mounts/Cloud"
RCLONE_IP="100.x.x.x"            # IP to ping (use Tailscale IP for remote)
```

### Sparse Bundle (Optional)

For mounting disk images stored on the SMB share:

```bash
BUNDLE_PATH="$SMB_MOUNT_POINT/Storage.sparsebundle"
BUNDLE_VOLUME_NAME="ExternalStorage"
```

---

## 🌍 Remote Access with Tailscale

LazyMount works beautifully with [Tailscale](https://tailscale.com/) for accessing your home storage from anywhere.

### Setup Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     YOUR HOME NETWORK                        │
│  ┌───────────┐     ┌───────────┐     ┌───────────────────┐  │
│  │   NAS     │     │  Server   │     │  Tailscale Node   │  │
│  │ 192.168.  │────▶│ (Rclone)  │────▶│  (Exit Node)      │  │
│  │   1.100   │     │           │     │  100.x.x.x        │  │
│  └───────────┘     └───────────┘     └─────────┬─────────┘  │
└─────────────────────────────────────────────────┼───────────┘
                                                  │
                    ──── Tailscale VPN ───────────┘
                                                  │
┌─────────────────────────────────────────────────┼───────────┐
│                    ANYWHERE IN THE WORLD        │           │
│                         ┌───────────────────────▼─────────┐ │
│                         │        Your MacBook             │ │
│                         │    LazyMount Auto-Connects!     │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Exit Node Configuration (Subnet Routing)

The magic feature you're looking for is called **"Subnet Router"** or **"Exit Node"** in Tailscale:

1. **On your home server** (Linux example):
   ```bash
   # Enable IP forwarding
   echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   
   # Advertise your home subnet
   sudo tailscale up --advertise-routes=192.168.1.0/24
   ```

2. **In Tailscale Admin Console** (https://login.tailscale.com/admin):
   - Go to Machines → Your server → Enable "Subnet routes"
   - Approve the `192.168.1.0/24` route

3. **On your Mac** (the client):
   ```bash
   # Accept the advertised routes
   sudo tailscale up --accept-routes
   ```

Now your Mac can access `192.168.1.x` addresses even when you're at a coffee shop! 🎉

---

## 🎮 Use Case Examples

### 1. Steam Game Library on NAS

Store games on a NAS to save SSD space:

```bash
# In mount_manager.sh:
SMB_IP="192.168.1.50"        # NAS IP
SMB_USER="steam"             
SMB_SHARE="Games"            # Share containing Steam library

# Optional: Use sparse bundle for better performance
BUNDLE_PATH="/Volumes/Games/SteamLibrary.sparsebundle"
BUNDLE_VOLUME_NAME="SteamLibrary"
```

Then in Steam: Settings → Storage → Add Library Folder → `/Volumes/SteamLibrary`

### 2. Time Machine to Remote Server

Back up your Mac to a server over the network:

```bash
SMB_IP="192.168.1.10"
SMB_USER="timemachine"
SMB_SHARE="Backups"

BUNDLE_PATH="/Volumes/Backups/MyMac.sparsebundle"
BUNDLE_VOLUME_NAME="TimeMachine"
```

Then: System Settings → Time Machine → Select Disk → Choose "TimeMachine"

### 3. Media Server (Plex/Jellyfin Source)

Access your movie library stored on a home server:

```bash
RCLONE_ENABLED="true"
RCLONE_REMOTE="homeserver:/media"
RCLONE_MOUNT_POINT="$HOME/Movies/Server"
RCLONE_IP="100.64.0.1"       # Tailscale IP of your server
```

### 4. Google Drive / Dropbox as Local Folder

Mount cloud storage as if it were a local drive:

```bash
# First, configure rclone:
# rclone config → New remote → "google" → Google Drive

RCLONE_REMOTE="google:/MyDrive"
RCLONE_MOUNT_POINT="$HOME/GoogleDrive"
RCLONE_IP="8.8.8.8"          # Use Google DNS to check internet
```

### 5. Work Project Archives

Keep large project files on office NAS, access from home:

```bash
SMB_ENABLED="true"
SMB_IP="10.0.0.50"           # Office NAS (via VPN/Tailscale)
SMB_USER="employee"
SMB_SHARE="Projects"
```

---

## 🔧 Management Commands

```bash
# Check status
launchctl list | grep lazymount

# View logs
tail -f /tmp/mount_manager.log

# Restart the service
launchctl unload ~/Library/LaunchAgents/com.lazymount.plist
launchctl load ~/Library/LaunchAgents/com.lazymount.plist

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.lazymount.plist

# Manual mount (for testing)
~/Scripts/mount_manager.sh
```

---

## ❓ FAQ

### Q: Mount fails with "permission denied"
**A:** Ensure your SMB credentials are saved in Keychain:
1. Open Finder → Go → Connect to Server (⌘K)
2. Enter your SMB URL: `smb://username@server/share`
3. Check "Remember this password in my keychain"

### Q: Rclone mount is slow
**A:** Adjust cache settings in the script:
```bash
--vfs-cache-max-size 50G    # Increase cache size
--dir-cache-time 5m         # Longer directory cache
```

### Q: Files don't appear immediately
**A:** This is normal for Rclone. Reduce `--dir-cache-time` to `10s` for faster refresh.

### Q: How do I unmount manually?
```bash
# SMB
diskutil unmount /Volumes/YourShare

# Rclone
diskutil unmount force ~/Mounts/CloudStorage
```

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

Contributions welcome! Please feel free to submit pull requests.

---

**Made with ❤️ for Mac users who refuse to pay Apple's storage tax.**
