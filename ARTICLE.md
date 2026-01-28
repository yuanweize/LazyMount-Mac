# LazyMount-Mac: The Ultimate Solution for Infinite Mac Storage
# LazyMount-Mac：Mac 无限存储的终极方案

Are you tired of the "Apple Tax" on storage? Does your 256GB MacBook Air constantly scream "Disk Full"?
你是否厌倦了昂贵的“苹果税”存储价格？你的 256GB MacBook Air 是否经常发出“磁盘已满”的警告？

**LazyMount-Mac** is here to save your wallet and your sanity. It turns your NAS, cloud storage, and remote servers into local folders on your Mac, seamlessly and automatically.
**LazyMount-Mac** 就是为了拯救你的钱包和理智而生的。它能将你的 NAS、云存储和远程服务器无缝地转化为 Mac 上的本地文件夹，全自动运行，无需人工干预。

---

## 🚀 What is LazyMount? / 什么是 LazyMount？

LazyMount is a smart automation script designed specifically for macOS. It manages the mounting of external storage protocols like **SMB** and **Rclone** (for cloud storage).
LazyMount 是一个专为 macOS 设计的智能自动化脚本。它管理着 **SMB** 和 **Rclone**（云存储）等外部存储协议的挂载。

Unlike the default macOS "Connect to Server", LazyMount is **resilient**. If your Wi-Fi drops, it waits. If you close your laptop and open it at a coffee shop, it reconnects (via Tailscale). It ensures your storage is always there when you need it.
与 macOS 默认的“连接服务器”不同，LazyMount 具有**鲁棒性**。如果你的 Wi-Fi 断开，它会等待。如果你合上笔记本并在咖啡馆打开，它会（通过 Tailscale）自动重连。它确保你的存储在你需要的时候随时可用。

### ✨ Key Features / 核心功能

1.  **Zero-Touch Automation / 零接触自动化**
    Starts at login, quietly in the background. No more `Cmd+K` every time you restart.
    登录时自动启动，后台静默运行。再也不用每次重启都按 `Cmd+K` 手动连接了。

2.  **Self-Healing Connections / 自愈连接**
    Network glitch? VPN reconnecting? LazyMount detects outages and automatically remounts your drives once the connection is restored.
    网络波动？VPN 重连？LazyMount 能检测中断，并在网络恢复后自动重新挂载你的磁盘。

3.  **Dual-Mode Power / 双模动力**
    -   **SMB**: Perfect for high-speed local NAS access (Synology, QNAP, TrueNAS).
    -   **Rclone**: Mount Google Drive, Dropbox, OneDrive, or S3 buckets as local drives.
    -   **SMB**: 完美支持高速本地 NAS 访问（群晖, QNAP, TrueNAS）。
    -   **Rclone**: 将 Google Drive, Dropbox, OneDrive 或 S3 存储桶挂载为本地磁盘。

4.  **Tailscale Integration / Tailscale 集成**
    Access your home NAS from anywhere in the world securely, as if you were sitting on your couch.
    通过 Tailscale 安全集成，让你在世界任何地方都能访问家里的 NAS，就像坐在自家沙发上一样。

---

## 🎮 Use Cases: What Can You Do? / 使用场景：你能做什么？

### 1. Steam Gaming Library on NAS / NAS 上的 Steam 游戏库
**Problem**: *Baldur's Gate 3* is 150GB. Your Mac has 20GB free.
**Solution**: Create a sparse bundle on your NAS, mount it with LazyMount, and install games there. macOS sees it as a local disk!
**问题**：《博德之门 3》需要 150GB 空间，而你的 Mac 只剩 20GB 了。
**方案**：在 NAS 上创建一个稀疏磁盘束（sparse bundle），用 LazyMount 挂载，然后把游戏装进去。macOS 会把它当作本地磁盘！

### 2. AI Model Offloading (Ollama) / AI 模型外挂 (Ollama)
**Problem**: You want to run Llama-3-70B, but the model file is 40GB.
**Solution**: Store your `.ollama/models` folder on your home server. LazyMount makes it available to your local Ollama instance instantly. (Recommendation: Use 2.5GbE or 10GbE network for best performance).
**问题**：你想运行 Llama-3-70B，但模型文件高达 40GB。
**方案**：将 `.ollama/models` 文件夹存放在家庭服务器上。LazyMount 让你的本地 Ollama 实例能瞬间访问这些模型。（建议：使用 2.5GbE 或 10GbE 网络以获得最佳性能）。

### 3. Infinite Media Server / 无限媒体服务器
**Problem**: Your 4TB movie collection is on an external drive plugged into a server in the basement.
**Solution**: Mount it to `~/Movies/Server` via Rclone/SMB. Point Plex, Infuse, or IINA to that folder and stream instantly.
**问题**：你 4TB 的电影收藏存在地下室服务器的外接硬盘里。
**方案**：通过 Rclone/SMB 把它挂载到 `~/Movies/Server`。将 Plex, Infuse 或 IINA 指向该文件夹，即刻开始流媒体播放。

### 4. Automated Time Machine / 自动 Time Machine 备份
**Problem**: You forget to plug in your backup drive.
**Solution**: LazyMount ensures your Time Machine network share is always mounted. Backups happen silently in the background without you thinking about it.
**问题**：你总是忘记插上备份硬盘。
**方案**：LazyMount 确保你的 Time Machine 网络共享始终处于挂载状态。备份在后台静默进行，完全无需操心。

---

## 🛠️ How It Works / 工作原理

LazyMount uses a simple but powerful Bash script (`mount_manager.sh`) combined with a macOS LaunchAgent (`plist`).
LazyMount 使用一个简单但强大的 Bash 脚本 (`mount_manager.sh`) 结合 macOS 的 LaunchAgent (`plist`) 工作。

When you log in:
当你登录时：

1.  **Check**: The script aggressively checks for network connectivity (pinging your server).
    **检查**：脚本会积极检查网络连通性（ping 你的服务器）。
2.  **Mount**: It mounts your configured drives using optimized flags for performance.
    **挂载**：它使用优化过的参数挂载你配置的磁盘，确保最佳性能。
3.  **Monitor**: If a mount fails, it logs the error and retries.
    **监控**：如果挂载失败，它会记录错误并重试。

### Configuration Snippet / 配置片段

It's as easy as editing a text file:
配置就像编辑文本文件一样简单：

```bash
# === SMB CONFIG ===
SMB_IP="192.168.1.100"
SMB_SHARE="MyData"

# === RCLONE CONFIG ===
RCLONE_REMOTE="google-drive:/Work"
RCLONE_MOUNT_POINT="$HOME/Work"
```

---

## 📥 Get Started / 立即开始

Stop managing mounts manually. Let your Mac work for you.
停止手动管理挂载吧。让你的 Mac 为你工作。

**👉 Download & Guide / 下载与指南**:  
[https://github.com/yuanweize/LazyMount-Mac](https://github.com/yuanweize/LazyMount-Mac)

**License**: MIT (Open Source & Free)
**协议**: MIT (开源且免费)

---
*Made with ❤️ for the Mac community.*
*为 Mac 社区倾情通过 ❤️ 制作。*
