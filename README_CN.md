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

> **⚠️ 游戏特别说明：**
> *   Steam/Epic 游戏库 **必须** 使用 APFS 稀疏磁盘映像才能正常工作。
> *   **LOL (英雄联盟)** 不支持存放在网络驱动器或 APFS 磁盘映像中（必须使用本地磁盘或 iSCSI）。


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

### 6. 🧠 AI/大模型存储库 (Ollama, LM Studio 等)

把大语言模型 (LLaMA, Mistral, Qwen 等) 存在服务器上，而不是占用 Mac 有限的 SSD 空间：

```bash
RCLONE_ENABLED="true"
RCLONE_REMOTE="homeserver:/ai-models"
RCLONE_MOUNT_POINT="$HOME/.ollama/models"    # Ollama 的模型目录
RCLONE_IP="192.168.1.10"
```

**⚠️ 重要：网络速度非常关键！**

大模型在推理前必须先加载到内存。如果模型不在本地缓存，就要从网络传输。一个 70B 模型可能有 40GB+，所以网速很重要：

| 网络类型 | 速度 | 加载 40GB 模型耗时 |
|----------|------|-------------------|
| 千兆网 (1G) | ~120 MB/s | ~5.5 分钟 |
| **2.5G 网口** | ~300 MB/s | **~2.2 分钟** ✅ 推荐 (Mac Mini 自带) |
| 万兆网 (10G) | ~1.2 GB/s | ~33 秒 |

**硬件升级建议：**

```
┌─────────────────────────────────────────────────────────────────┐
│  💡 想获得最佳大模型体验？升级你的网络！                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  方案一：2.5G USB 网卡（约 ¥50-100）                            │
│  ┌─────────┐      ┌────────────────┐      ┌─────────────┐      │
│  │   Mac   │─USB─▶│ 2.5G USB 网卡  │─────▶│ 2.5G 交换机 │      │
│  └─────────┘      └────────────────┘      └─────────────┘      │
│                                                                 │
│  方案二：10G 雷电转换器（约 ¥500-1000）                         │
│  ┌─────────┐      ┌────────────────┐      ┌─────────────┐      │
│  │   Mac   │─TB4─▶│ 10G 雷电转换器 │─────▶│ 10G 交换机  │      │
│  └─────────┘      └────────────────┘      └─────────────┘      │
│                                                                 │
│  ⚠️ 注意：两端（Mac + 服务器）都要支持对应的速度！              │
└─────────────────────────────────────────────────────────────────┘
```

**大模型专用缓存设置（减少重复下载）：**

```bash
# 在 mount_manager.sh 中调整 Rclone 设置：
--vfs-cache-max-size 100G    # 大缓存存放模型文件
--vfs-cache-max-age 720h     # 缓存保留 30 天
--vfs-read-ahead 1G          # 预读取加快加载
```

**为什么这很重要：**
- 大模型应用 (Ollama, LM Studio) 闲置几分钟后会自动卸载模型（通常是 5 分钟）
- 下次对话需要重新加载整个模型
- 快网络 = 快速加载模型 = 更好的使用体验

---

## 📚 新手详细教程

第一次用终端/命令行？这个部分手把手教你每一步。

### 第 1 步：安装 Homebrew（包管理器）

Homebrew 就像命令行工具的 "App Store"。如果你还没装：

```bash
# 打开终端（聚焦搜索 → 输入 "终端" → 回车）
# 粘贴这个命令然后回车：
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 按照屏幕上的提示操作
# 完成后验证一下：
brew --version
```

### 第 2 步：安装必要的工具

```bash
# 安装 Rclone（用于云/远程挂载）
brew install rclone

# 安装 macFUSE（Rclone 依赖这个）
# ⚠️ 安装后需要重启！
brew install --cask macfuse

# （可选）安装 Tailscale 用于远程访问
brew install --cask tailscale
```

**安装 macFUSE 后：**
1. 打开系统设置 → 隐私与安全性
2. 往下滑，点击允许 macFUSE 扩展
3. **重启 Mac**

### 第 3 步：配置 Rclone 远程存储

```bash
# 启动配置向导
rclone config

# 例如：设置 SFTP 连接到你的服务器
# n) New remote（新建远程）
# name> homeserver
# Storage> sftp
# host> 192.168.1.10
# user> your_username
# （按提示输入 SSH 密钥或密码）
```

**常见远程类型：**

| 类型 | 用途 | 配置命令 |
|------|------|----------|
| SFTP | Linux 服务器、带 SSH 的 NAS | `rclone config` → sftp |
| Google Drive | Google 云盘 | `rclone config` → drive |
| Dropbox | Dropbox 文件 | `rclone config` → dropbox |
| S3 | AWS/MinIO 存储 | `rclone config` → s3 |

### 第 4 步：测试你的远程存储

```bash
# 列出远程存储上的文件（把 'homeserver' 换成你的远程名）
rclone ls homeserver:/

# 如果能看到文件，说明配置成功！
```

### 第 5 步：下载并配置 LazyMount

```bash
# 创建 Scripts 文件夹
mkdir -p ~/Scripts

# 下载脚本
curl -o ~/Scripts/mount_manager.sh https://raw.githubusercontent.com/yuanweize/LazyMount-Mac/main/mount_manager.sh

# 设置可执行权限
chmod +x ~/Scripts/mount_manager.sh

# 用文本编辑器打开编辑
open -e ~/Scripts/mount_manager.sh
```

**在脚本中找到并修改这些行：**

```bash
# === RCLONE 配置 ===
RCLONE_ENABLED="true"                          # 启用 Rclone？(true/false)
RCLONE_REMOTE="homeserver:/data"               # ← 你的远程名和路径
RCLONE_MOUNT_POINT="$HOME/Mounts/Server"       # ← Mac 上的挂载位置
RCLONE_IP="192.168.1.10"                       # ← 用于网络检测的 IP

# === SMB 配置 ===
SMB_ENABLED="true"                             # 启用 SMB？(true/false)
SMB_IP="192.168.1.100"                         # ← 你的 NAS/服务器 IP
SMB_USER="your_username"                       # ← 你的 SMB 用户名
SMB_SHARE="SharedFolder"                       # ← 共享文件夹名
```

### 第 6 步：把 SMB 密码保存到钥匙串

**这步很重要！** 脚本需要钥匙串里存有密码：

1. 打开 **Finder** → 按 `⌘ + K`（连接服务器）
2. 输入：`smb://你的用户名@192.168.1.100/共享文件夹`
3. 输入密码
4. ✅ 勾选 **"在我的钥匙串中记住此密码"**
5. 点击连接

这样脚本就能自动连接，不用每次输密码！

### 第 7 步：手动测试脚本

```bash
# 运行脚本看看能不能用
~/Scripts/mount_manager.sh

# 在另一个终端窗口实时查看日志
tail -f /tmp/mount_manager.log

# 你应该能看到：
# === Mount Session Started: ... ===
# HH:MM:SS [SMB] Starting sequence...
# HH:MM:SS [SMB] Network OK.
# ...
```

### 第 8 步：设置开机自启

```bash
# 下载 LaunchAgent 配置文件
curl -o ~/Library/LaunchAgents/com.lazymount.plist https://raw.githubusercontent.com/yuanweize/LazyMount-Mac/main/com.example.mountmanager.plist

# 把 YOUR_USERNAME 替换成你的用户名
sed -i '' "s/YOUR_USERNAME/$(whoami)/g" ~/Library/LaunchAgents/com.lazymount.plist

# 加载它（立即生效）
launchctl load ~/Library/LaunchAgents/com.lazymount.plist

# 验证是否正在运行
launchctl list | grep lazymount
```

### 第 9 步：验证一切正常

```bash
# 检查卷是否已挂载：

# SMB：
ls /Volumes/

# Rclone：
ls ~/Mounts/

# 查看最近的日志：
tail -20 /tmp/mount_manager.log
```

**🎉 搞定！** 你的存储空间现在每次登录都会自动挂载。

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

## ⚠️ 已知问题

### APFS 稀疏磁盘映像与重启
如果你的 Mac 在关机时没有"优雅断开"（例如断电、强制重启、死机），Steam/Epic 游戏库使用的 APFS 磁盘映像可能会出现数据校验错误。这会导致磁盘变为 **只读** 状态，或者无法写入新游戏数据。

**解决方法：**
1. 打开系统自带的 **磁盘工具 (Disk Utility)**。
2. 选中挂载的卷（例如 `SteamLibrary`）。
3. 点击顶部的 **急救 (First Aid)** 按钮并运行。
4. 修复完成后即可恢复正常读写。

*注：普通的 SMB、Rclone 和 SFTP 挂载不受此问题影响。*

---

## 🛠️ 进阶存储管理

**[AppPorts](https://github.com/wzh4869/AppPorts)** — *外接硬盘拯救世界！*

> LazyMount 的最佳拍档。LazyMount 负责**连接**存储，AppPorts 负责**应用程序**。

*   📦 **应用瘦身**：一键将巨大应用（Logic Pro, Xcode, 游戏）迁移到外置硬盘/NAS。
*   🔗 **无缝链接**：独家 "App Portal" 技术，让系统误以为应用还在本地，不影响任何功能。
*   🛡️ **安全可靠**：专为 macOS 目录结构优化，支持随时一键还原。

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)。

---

## 🤝 贡献

欢迎提交 Pull Request！

---

**为拒绝支付苹果存储税的 Mac 用户而做 ❤️**
