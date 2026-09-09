# P2P 语音通话服务器部署指南（信令 + STUN/TURN）

本项目包含两个服务：

1. **WebSocket 信令服务**（端口 `8080`）：负责在呼叫开始前交换双方的连接元数据（SDP 和 ICE 候选），并签发临时 TURN 凭据。**接通后音频手机对手机直连，不经过信令服务器。**
2. **Coturn STUN/TURN 服务**（端口 `3478 UDP/TCP`）：优先通过 STUN 做 NAT 打洞实现**纯直连**；仅当双方网络（如对称 NAT）无法直连时，才回退到私有 TURN 中继。**中继的媒体始终由 DTLS-SRTP 端到端加密，服务器无法解密内容。**

> 说明：TURN 中继是"打洞失败时的兜底"，并非默认路径。绝大多数通话会走 STUN 直连。

---

## 方式一：Docker Compose 一键部署（推荐）

将 `server/` 文件夹复制到服务器（例如 `/opt/p2p-server`）：

```bash
cd /opt/p2p-server
# 可选：配置共享令牌与 TURN 密钥（二者需保持一致）
export SIGNALING_TOKEN=your-shared-token      # 可选，客户端需填入相同令牌
export TURN_SECRET=your-turn-secret           # 必须与 turnserver.conf 中 static-auth-secret 一致
export TURN_SERVER=你的服务器IP:3478
docker compose up -d --build
```

查看状态：

```bash
docker compose ps
docker compose logs -f
```

> `TURN_SECRET` 用于 TURN REST API 临时凭据签发，**必须**与 `turnserver.conf` 里的
> `static-auth-secret` 保持一致（若修改 `turnserver.conf`，请同步 `TURN_SECRET`）。

---

## 方式二：直接在 Linux 主机上运行

### 1. 运行信令服务 (Node.js)

```bash
cd server
npm install
# 可选环境变量
export SIGNALING_TOKEN=your-shared-token
export TURN_SERVER=你的服务器IP:3478
export TURN_SECRET=your-turn-secret
node signaling.js
# 或使用 pm2 后台守护
npm install -g pm2
pm2 start signaling.js --name p2p-signaling
```

### 2. 运行 STUN/TURN 服务 (Coturn)

Ubuntu/Debian：

```bash
sudo apt-get update
sudo apt-get install -y coturn
sudo cp turnserver.conf /etc/turnserver.conf
# 编辑 /etc/turnserver.conf，将 static-auth-secret 改为你的密钥（与 TURN_SECRET 一致）
sudo systemctl restart coturn
```

---

## 安全说明

- **信令鉴权**：设置 `SIGNALING_TOKEN` 后，客户端注册时必须携带相同 `token`，否则被拒绝。
- **来源校验**：可通过 `ALLOWED_ORIGINS=origin1,origin2` 限制浏览器客户端的来源。
- **TLS**：生产环境强烈建议在信令服务前挂 Nginx 配置 `wss://`，并将客户端地址改为 `wss://`。
- **TURN 凭据**：凭据由信令服务按 TURN REST API 动态签发（时效 `TURN_TTL` 秒），客户端二进制中不再硬编码任何密钥。

---

## 防火墙与安全组设置

请确保云服务商控制台（AWS / GCP / 阿里云 / 腾讯云等）开放：

- **8080 TCP**：WebSocket 信令端口（或挂 Nginx 后仅开放 443）
- **3478 UDP & TCP**：STUN/TURN 探测与中继端口
- **49152–49200 UDP**：TURN 中继数据端口范围（`turnserver.conf` 中配置）
