# P2P 语音通话客户端 (Flutter)

基于 WebRTC 的点对点加密语音通话客户端，支持 Android 与 iOS。

## 功能

- 端到端加密（DTLS-SRTP）P2P 语音通话，优先 STUN 直连，TURN 兜底
- 自定义头像、用户 ID、深色/浅色主题
- 自定义背景图片（从相册选择）
- 多语言（中文 / English / Français），自动跟随设备语言并支持手动切换
- 断线自动重连、呼叫状态机（占线、超时、离线路由）
- Android 前台服务保活（通话期间）

## 运行

```bash
cd client
flutter pub get
flutter run
```

首次运行时在「设置」中填写信令服务器地址（默认 `ws://170.106.195.109:8080`）、
STUN 地址，以及（可选）与服务端一致的访问令牌。

## 构建

```bash
flutter build apk --release      # Android
flutter build ios --release      # iOS（需 macOS + Xcode）
```

> iOS 当前通过 `NSAppTransportSecurity` 允许明文 `ws://` 以兼容自建服务器；
> 生产环境请改用 `wss://` 并移除该例外。

## 国际化

- 支持语言：中文（`zh`）、英文（`en`）、法语（`fr`）。
- 默认「跟随系统」，可在设置中手动切换，选择会持久化到本地。
- 文案位于 `lib/l10n/app_localizations.dart`，新增语言时在该文件中补充对应 map 即可。

## 项目结构

```
lib/
  l10n/                本地化（AppLocalizations）
  models/              AvatarItem / CallStatus / SignalingStatus
  services/            SignalingService / WebRTCService / ForegroundServiceManager
  theme/               主题与语义色令牌
  ui/                  页面与可复用组件（AvatarCircle 等）
  main.dart            应用入口（异步初始化、多语言/主题装配）
```
