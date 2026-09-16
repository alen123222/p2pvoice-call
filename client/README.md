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

- `controllers/call_controller.dart`：身份、偏好、在线设备、计时和通知协调。
- `services/webrtc_service.dart`：通话状态转换、SDP/ICE、媒体生命周期与音频控制。
- `services/signaling_service.dart`：WebSocket 注册、心跳、重连与消息路由。
- `ui/home_page.dart`：响应式身份卡、拨号和在线设备。
- `ui/call_view.dart`：来电与通话界面。
- `ui/settings_page.dart`、`ui/profile_sheet.dart`：网络、外观和个人资料编辑。
- `theme/app_theme.dart`：Material 3 明暗主题和四种配色。
- `models/input_validation.dart`：与服务端一致的身份校验及网络地址校验。

## 验证

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

服务端运行 `node server/test_signaling.js`（在仓库根目录）。
测试使用本地临时信令服务器，不连接部署服务器。

设置 `SAVE_UI_PREVIEWS=1` 后运行布局测试，可将真实 Flutter widget 的渲染截图
输出到仓库 `artifacts/`。测试状态由替身服务提供，截图不代表真实通话验证；
Windows 截图优先加载系统中文和 emoji 字体。

## 平台边界

Android 保留前台服务和来电通知；麦克风权限仅在通话协商时请求。
iOS 的后台来电推送 / CallKit 未实现，不能承诺应用被系统挂起或杀死后仍可收到来电。
Android 长期后台在线同样受系统限制，详见根目录 `REFACTOR_NOTES.md`。
