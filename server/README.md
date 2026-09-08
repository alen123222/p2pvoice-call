# 硅谷辅助服务器部署指南 (信令 + 纯 STUN 服务)

本项目包含：
1. **轻量 WebSocket 信令服务**（端口 `8080`）：负责在呼叫开始前交换手机双方的连接元数据（SDP 和 ICE 候选）。接通后音频直接手机对手机传输，不经过信令服务器。
2. **纯 STUN 服务器**（端口 `3478 UDP/TCP`）：使用 Coturn 运行在 `stun-only` 模式下，仅提供 NAT 打洞探测，**严禁中转任何语音音频**。

---

## 方式一：Docker Compose 一键部署（推荐）

将 `server/` 文件夹复制到您的硅谷服务器上（例如放置于 `/opt/p2p-server`）：

```bash
cd /opt/p2p-server
docker compose up -d --build
```

查看运行状态：
```bash
docker compose ps
docker compose logs -f
```

---

## 方式二：直接在 Linux 主机上运行

### 1. 运行信令服务 (Node.js)
```bash
cd server
npm install
node signaling.js
# 或使用 pm2 后台守护
npm install -g pm2
pm2 start signaling.js --name p2p-signaling
```

### 2. 运行 STUN 服务 (Coturn)
Ubuntu/Debian 安装：
```bash
sudo apt-get update
sudo apt-get install -y coturn
sudo cp turnserver.conf /etc/turnserver.conf
sudo systemctl restart coturn
```

---

## 防火墙与安全组设置

请确保硅谷服务器的云服务商控制台（AWS / GCP / 阿里云 / 腾讯云等）开放以下端口：
* **8080 TCP**：WebSocket 信令端口（或前面挂 Nginx 配置 SSL/WSS）
* **3478 UDP & TCP**：STUN NAT 打洞探测端口
