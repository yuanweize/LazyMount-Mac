# LazyMount-Mac 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)

**[📖 English Documentation](README.md)**

> **轻松扩展 Mac 存储空间** — 开机自动挂载 SMB 共享和云存储，全程无需手动操作。

---

## ✨ 为什么选择 LazyMount？

Mac 存储空间**太贵了** — 升级 1TB 要多花 ¥1500+。LazyMount 帮你用外部存储无缝扩展 Mac：

- 🎮 **游戏库** — 把 Steam/Epic 游戏放在 NAS 上，玩起来跟本地一样
- 💾 **时间机器备份** — 自动备份到远程服务器
- 🎬 **媒体库** — 随时访问存放在家庭服务器上的电影/音乐
- 📁 **项目归档** — 大文件放在便宜的存储上，按需访问
- ☁️ **云存储** — 把 Google Drive、Dropbox 或任何 rclone 支持的服务挂载成本地文件夹

**核心特性：**
- 🔄 **开机自动挂载** — 不用手动点击
- 🛡️ **自动恢复** — 断网后自动重连
- 🌐 **随处可用** — 通过 Tailscale 远程访问家里的存储
- ⚡ **双模式** — 同时支持 SMB（局域网）和 Rclone（云存储/远程）

---

## 📦 安装

### 前置要求

1. **Rclone**（用于云存储挂载）：
   ```bash
   brew install rclone
   # 然后配置你的远程存储：
   rclone config
   ```

2. **macFUSE**（Rclone 依赖）：
   ```bash
   brew install --cask macfuse
   ```

3. **（推荐）Tailscale** — 用于远程访问家庭网络：
   ```bash
   brew install --cask tailscale
   ```

### 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/yuanweize/LazyMount-Mac.git
cd LazyMount-Mac

# 2. 复制脚本到 Scripts 文件夹
mkdir -p ~/Scripts
cp mount_manager.sh ~/Scripts/
chmod +x ~/Scripts/mount_manager.sh

# 3. 编辑脚本，填入你的配置
nano ~/Scripts/mount_manager.sh  # 或用任何编辑器

# 4. 安装 LaunchAgent 实现开机自启
cp com.example.mountmanager.plist ~/Library/LaunchAgents/com.lazymount.plist
# 把 YOUR_USERNAME 替换成你的用户名：
sed -i '' "s/YOUR_USERNAME/$(whoami)/g" ~/Library/LaunchAgents/com.lazymount.plist

# 5. 加载它！
launchctl load ~/Library/LaunchAgents/com.lazymount.plist
```

---

## ⚙️ 配置说明

编辑 `~/Scripts/mount_manager.sh`，修改 **USER CONFIGURATION** 部分：

### SMB 共享配置

```bash
SMB_ENABLED="true"
SMB_IP="192.168.1.100"           # 你的 NAS/服务器 IP
SMB_USER="your_username"         # SMB 用户名
SMB_SHARE="SharedFolder"         # 共享文件夹名称
```

### Rclone 配置

```bash
RCLONE_ENABLED="true"
RCLONE_REMOTE="myremote:/path"   # 你的 rclone 远程存储
RCLONE_MOUNT_POINT="$HOME/Mounts/Cloud"
RCLONE_IP="100.x.x.x"            # 用于网络检测的 IP（远程访问时用 Tailscale IP）
```

### 稀疏磁盘映像（可选）

用于挂载存放在 SMB 共享上的磁盘映像：

```bash
BUNDLE_PATH="$SMB_MOUNT_POINT/Storage.sparsebundle"
BUNDLE_VOLUME_NAME="ExternalStorage"
```

---

## 🌍 使用 Tailscale 远程访问

LazyMount 完美配合 [Tailscale](https://tailscale.com/)，让你在任何地方都能访问家里的存储。

### 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                       你的家庭网络                           │
│  ┌───────────┐     ┌───────────┐     ┌───────────────────┐  │
│  │   NAS     │     │   服务器   │     │  Tailscale 节点   │  │
│  │ 192.168.  │────▶│ (Rclone)  │────▶│  (子网路由器)     │  │
│  │   1.100   │     │           │     │  100.x.x.x        │  │
│  └───────────┘     └───────────┘     └─────────┬─────────┘  │
└─────────────────────────────────────────────────┼───────────┘
                                                  │
                    ──── Tailscale VPN ───────────┘
                                                  │
┌─────────────────────────────────────────────────┼───────────┐
│                      世界任何角落                │           │
│                         ┌───────────────────────▼─────────┐ │
│                         │        你的 MacBook             │ │
│                         │    LazyMount 自动连接！         │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 子网路由配置（内网穿透）

你需要的功能叫做 Tailscale 的 **"子网路由器 (Subnet Router)"**：

1. **在家里的服务器上**（Linux 示例）：
   ```bash
   # 开启 IP 转发
   echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   
   # 广播你的家庭子网
   sudo tailscale up --advertise-routes=192.168.1.0/24
   ```

2. **在 Tailscale 管理后台** (https://login.tailscale.com/admin)：
   - 转到 Machines → 你的服务器 → 启用 "Subnet routes"
   - 批准 `192.168.1.0/24` 路由

3. **在你的 Mac 上**（客户端）：
   ```bash
   # 接受广播的路由
   sudo tailscale up --accept-routes
   ```

现在你在咖啡店也能访问 `192.168.1.x` 地址了！🎉

---

## 🎮 使用场景示例

### 1. NAS 上的 Steam 游戏库

把游戏存到 NAS 上，节省 SSD 空间：

```bash
# 在 mount_manager.sh 中配置：
SMB_IP="192.168.1.50"        # NAS IP
SMB_USER="steam"             
SMB_SHARE="Games"            # 包含 Steam 库的共享

# 可选：使用稀疏磁盘映像提升性能
BUNDLE_PATH="/Volumes/Games/SteamLibrary.sparsebundle"
BUNDLE_VOLUME_NAME="SteamLibrary"
```

然后在 Steam 中：设置 → 存储 → 添加库文件夹 → `/Volumes/SteamLibrary`

### 2. 时间机器备份到远程服务器

把 Mac 备份到网络上的服务器：

```bash
SMB_IP="192.168.1.10"
SMB_USER="timemachine"
SMB_SHARE="Backups"

BUNDLE_PATH="/Volumes/Backups/MyMac.sparsebundle"
BUNDLE_VOLUME_NAME="TimeMachine"
```

然后：系统设置 → 时间机器 → 选择磁盘 → 选择 "TimeMachine"

### 3. 媒体服务器（Plex/Jellyfin 片源）

访问存放在家庭服务器上的电影库：

```bash
RCLONE_ENABLED="true"
RCLONE_REMOTE="homeserver:/media"
RCLONE_MOUNT_POINT="$HOME/Movies/Server"
RCLONE_IP="100.64.0.1"       # 服务器的 Tailscale IP
```

### 4. Google Drive / Dropbox 当本地文件夹

把云存储挂载成本地磁盘：

```bash
# 首先配置 rclone：
# rclone config → New remote → "google" → Google Drive

RCLONE_REMOTE="google:/MyDrive"
RCLONE_MOUNT_POINT="$HOME/GoogleDrive"
RCLONE_IP="8.8.8.8"          # 用 Google DNS 检测网络
```

### 5. 公司项目归档

大型项目文件放在公司 NAS，在家也能访问：

```bash
SMB_ENABLED="true"
SMB_IP="10.0.0.50"           # 公司 NAS（通过 VPN/Tailscale）
SMB_USER="employee"
SMB_SHARE="Projects"
```

---

## 🔧 管理命令

```bash
# 查看状态
launchctl list | grep lazymount

# 查看日志
tail -f /tmp/mount_manager.log

# 重启服务
launchctl unload ~/Library/LaunchAgents/com.lazymount.plist
launchctl load ~/Library/LaunchAgents/com.lazymount.plist

# 停止服务
launchctl unload ~/Library/LaunchAgents/com.lazymount.plist

# 手动运行（用于测试）
~/Scripts/mount_manager.sh
```

---

## ❓ 常见问题

### Q: 挂载失败，提示 "permission denied"
**A:** 确保 SMB 凭证已保存到钥匙串：
1. 打开 Finder → 前往 → 连接服务器（⌘K）
2. 输入 SMB 地址：`smb://用户名@服务器/共享`
3. 勾选"在我的钥匙串中记住此密码"

### Q: Rclone 挂载很慢
**A:** 调整脚本中的缓存设置：
```bash
--vfs-cache-max-size 50G    # 增大缓存
--dir-cache-time 5m         # 延长目录缓存时间
```

### Q: 文件不会立即显示
**A:** 这是 Rclone 的正常现象。把 `--dir-cache-time` 改成 `10s` 可以加快刷新。

### Q: 怎么手动卸载？
```bash
# SMB
diskutil unmount /Volumes/你的共享

# Rclone
diskutil unmount force ~/Mounts/CloudStorage
```

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)。

---

## 🤝 贡献

欢迎提交 Pull Request！

---

**为拒绝支付苹果存储税的 Mac 用户而做 ❤️**
