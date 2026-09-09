import 'package:flutter/material.dart';

/// Persisted language preference: 'auto', 'en', 'zh' or 'fr'.
/// 'auto' follows the device locale.
final ValueNotifier<String> languageCodeNotifier = ValueNotifier<String>('auto');

/// Resolves the effective [Locale] from the persisted preference and, when
/// 'auto', from the device locale. Falls back to English when the device
/// language is not supported.
Locale resolveLocale(String languageCode) {
  if (languageCode != 'auto' &&
      AppLocalizations.languageCodes.contains(languageCode)) {
    return Locale(languageCode);
  }

  final List<Locale> deviceLocales =
      WidgetsBinding.instance.platformDispatcher.locales;
  if (deviceLocales.isNotEmpty) {
    final code = deviceLocales.first.languageCode;
    if (AppLocalizations.languageCodes.contains(code)) {
      return Locale(code);
    }
  }
  return const Locale('en');
}

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations? of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
    Locale('fr'),
  ];

  static const List<String> languageCodes = ['en', 'zh', 'fr'];

  /// Resolves a translation key, falling back to English then the key itself.
  /// Public so callers (e.g. dynamic notice messages) can translate by key.
  String t(String key) =>
      _translations[locale.languageCode]?[key] ??
      _translations['en']![key] ??
      key;

  // ----- General -----
  String get appTitle => t('appTitle');
  String get headerTitle => t('headerTitle');

  // ----- Connection status -----
  String get statusOnline => t('statusOnline');
  String get statusConnecting => t('statusConnecting');
  String get statusReconnecting => t('statusReconnecting');
  String get statusOffline => t('statusOffline');

  // ----- Tooltips -----
  String get tooltipLightTheme => t('tooltipLightTheme');
  String get tooltipDarkTheme => t('tooltipDarkTheme');
  String get tooltipSettings => t('tooltipSettings');
  String get tooltipCopy => t('tooltipCopy');
  String get tooltipEdit => t('tooltipEdit');

  // ----- Identity -----
  String get myUserIdLabel => t('myUserIdLabel');
  String get loading => t('loading');
  String get toastCopied => t('toastCopied');
  String get unknownUser => t('unknownUser');

  // ----- Notice -----
  String get secureNotice => t('secureNotice');

  // ----- Dial -----
  String get dialTitle => t('dialTitle');
  String get dialHint => t('dialHint');
  String get dialButton => t('dialButton');

  // ----- Online peers -----
  String get onlineDevices => t('onlineDevices');
  String get noPeers => t('noPeers');
  String get noPeersHint => t('noPeersHint');
  String get directCall => t('directCall');

  // ----- Call overlays -----
  String get incomingCall => t('incomingCall');
  String get e2eUdpBadge => t('e2eUdpBadge');
  String get hangup => t('hangup');
  String get answer => t('answer');
  String get secureCalling => t('secureCalling');
  String get p2pCalling => t('p2pCalling');
  String get establishing => t('establishing');
  String get negotiating => t('negotiating');
  String get transportProtocol => t('transportProtocol');
  String get iceStateLabel => t('iceStateLabel');
  String get micLabel => t('micLabel');
  String get mutedLabel => t('mutedLabel');
  String get speakerLabel => t('speakerLabel');
  String get earpieceLabel => t('earpieceLabel');

  // ----- Dialogs -----
  String get avatarPickerTitle => t('avatarPickerTitle');
  String get editIdTitle => t('editIdTitle');
  String get enterNewIdHint => t('enterNewIdHint');
  String get cancel => t('cancel');
  String get save => t('save');
  String get settingsTitle => t('settingsTitle');
  String get serverLabel => t('serverLabel');
  String get stunLabel => t('stunLabel');
  String get applySave => t('applySave');
  String get settingsNote => t('settingsNote');
  String get tokenLabel => t('tokenLabel');

  // ----- Language -----
  String get languageLabel => t('languageLabel');
  String get languageAuto => t('languageAuto');

  // ----- Background -----
  String get backgroundLabel => t('backgroundLabel');
  String get chooseImage => t('chooseImage');
  String get resetBackground => t('resetBackground');
  String get backgroundSaved => t('backgroundSaved');
  String get backgroundReset => t('backgroundReset');
  String get backgroundError => t('backgroundError');

  // ----- Errors / notices -----
  String get errorEmptyTarget => t('errorEmptyTarget');
  String get errorSelfCall => t('errorSelfCall');
  String get errorNotConnected => t('errorNotConnected');
  String get callEnded => t('callEnded');
  String get peerHangup => t('peerHangup');
  String get peerOffline => t('peerOffline');
  String get noAnswer => t('noAnswer');
  String get busy => t('busy');
  String get callRejected => t('callRejected');
  String get callFailed => t('callFailed');
  String get micDenied => t('micDenied');

  /// Localized avatar display name, falling back to the built-in Chinese name.
  String avatarName(String id) {
    final key = 'avatar_$id';
    final translated = t(key);
    return translated == key ? (_avatarFallbackZh[id] ?? id) : translated;
  }

  static const Map<String, String> _avatarFallbackZh = {
    'pilot': '领航员',
    'cyber_fox': '极客狐',
    'cyber_cat': '赛博猫',
    'tiger': '荣耀虎',
    'panda': '功夫熊',
    'lion': '霸气狮',
    'dolphin': '星海豚',
    'eagle': '苍穹鹰',
    'unicorn': '独角兽',
    'robot': '极智机',
    'lightning': '光子速',
    'shield': '圣盾甲',
  };

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'appTitle': 'P2P Voice Call',
      'headerTitle': 'P2P Direct Voice',
      'statusOnline': 'Online',
      'statusConnecting': 'Connecting',
      'statusReconnecting': 'Reconnecting',
      'statusOffline': 'Offline',
      'tooltipLightTheme': 'Switch to light theme',
      'tooltipDarkTheme': 'Switch to dark theme',
      'tooltipSettings': 'Network & server settings',
      'tooltipCopy': 'Copy ID',
      'tooltipEdit': 'Edit ID',
      'myUserIdLabel': 'My User ID',
      'loading': 'Loading...',
      'toastCopied': 'User ID copied to clipboard',
      'unknownUser': 'Unknown device',
      'secureNotice':
          'Secure direct: audio is transmitted peer-to-peer over hardware-encrypted DTLS-SRTP, with zero cloud storage, protected from eavesdropping and tampering.',
      'dialTitle': 'Start P2P Call',
      'dialHint': 'Enter the peer user ID (e.g. user_8888)',
      'dialButton': 'Start HD Direct Call',
      'onlineDevices': 'Online Devices',
      'noPeers': 'No other devices online',
      'noPeersHint': 'Launch this app on another phone to discover it here',
      'directCall': 'Call',
      'incomingCall': 'Incoming P2P Call',
      'e2eUdpBadge': 'End-to-end UDP encrypted direct',
      'hangup': 'Hang up',
      'answer': 'Answer',
      'secureCalling': '🔒 End-to-end encrypted secure call',
      'p2pCalling': '🟢 100% P2P pure direct call',
      'establishing': 'Establishing end-to-end encrypted connection...',
      'negotiating': 'Signaling & NAT traversal...',
      'transportProtocol': 'Transport',
      'iceStateLabel': 'ICE State',
      'micLabel': 'Mic',
      'mutedLabel': 'Muted',
      'speakerLabel': 'Speaker',
      'earpieceLabel': 'Earpiece',
      'avatarPickerTitle': 'Choose your avatar',
      'editIdTitle': 'Edit User ID',
      'enterNewIdHint': 'Enter new ID',
      'cancel': 'Cancel',
      'save': 'Save',
      'settingsTitle': 'Server & Network Settings',
      'serverLabel': 'WebSocket signaling server address',
      'stunLabel': 'STUN server',
      'applySave': 'Apply & Save',
      'settingsNote':
          'Note: changes are saved automatically and the signaling service reconnects.',
      'tokenLabel': 'Access token (optional)',
      'languageLabel': 'Language',
      'languageAuto': 'Follow system',
      'backgroundLabel': 'Custom background',
      'chooseImage': 'Choose image',
      'resetBackground': 'Reset to default',
      'backgroundSaved': 'Background updated',
      'backgroundReset': 'Background reset',
      'backgroundError': 'Failed to update background',
      'errorEmptyTarget': 'Please enter the peer user ID',
      'errorSelfCall': 'Cannot call yourself',
      'errorNotConnected': 'Not connected to the signaling server',
      'callEnded': 'Call ended',
      'peerHangup': 'Peer hung up',
      'peerOffline': 'Peer is offline',
      'noAnswer': 'No answer',
      'busy': 'Line busy',
      'callRejected': 'Call declined',
      'callFailed': 'Failed to establish the call',
      'micDenied': 'Microphone unavailable. Please grant permission.',
      'avatar_pilot': 'Pilot',
      'avatar_cyber_fox': 'Cyber Fox',
      'avatar_cyber_cat': 'Cyber Cat',
      'avatar_tiger': 'Tiger',
      'avatar_panda': 'Panda',
      'avatar_lion': 'Lion',
      'avatar_dolphin': 'Dolphin',
      'avatar_eagle': 'Eagle',
      'avatar_unicorn': 'Unicorn',
      'avatar_robot': 'Robot',
      'avatar_lightning': 'Lightning',
      'avatar_shield': 'Shield',
    },
    'zh': {
      'appTitle': 'P2P 语音通话',
      'headerTitle': 'P2P 语音直通',
      'statusOnline': '在线',
      'statusConnecting': '连接中',
      'statusReconnecting': '自动重连中',
      'statusOffline': '未连信令',
      'tooltipLightTheme': '切换为天蓝浅色主题',
      'tooltipDarkTheme': '切换为深色主题',
      'tooltipSettings': '网络与服务器设置',
      'tooltipCopy': '复制 ID',
      'tooltipEdit': '修改 ID',
      'myUserIdLabel': '我的用户 ID',
      'loading': '加载中...',
      'toastCopied': '已复制用户 ID 到剪贴板',
      'unknownUser': '未知设备',
      'secureNotice':
          '安全直连：音频流在手机间通过硬件级 DTLS-SRTP 密文点对点传输，零云端存储，防窃听防篡改。',
      'dialTitle': '发起 P2P 呼叫',
      'dialHint': '输入对方的用户 ID (例如 user_8888)',
      'dialButton': '开始高清直连通话',
      'onlineDevices': '当前在线设备',
      'noPeers': '暂无其他设备在线',
      'noPeersHint': '在另一台手机上启动本应用即可在此自动感知',
      'directCall': '直拨',
      'incomingCall': '收到 P2P 直连呼叫',
      'e2eUdpBadge': '端到端 UDP 加密直连',
      'hangup': '挂断',
      'answer': '接听',
      'secureCalling': '🔒 端到端加密安全通话中',
      'p2pCalling': '🟢 100% P2P 纯直连通话中',
      'establishing': '正在建立端到端加密直连...',
      'negotiating': '信令协商与 NAT 打洞中...',
      'transportProtocol': '传输协议',
      'iceStateLabel': 'ICE 状态',
      'micLabel': '麦克风',
      'mutedLabel': '已静音',
      'speakerLabel': '扬声器',
      'earpieceLabel': '听筒',
      'avatarPickerTitle': '选择您的专属头像',
      'editIdTitle': '修改用户 ID',
      'enterNewIdHint': '请输入新 ID',
      'cancel': '取消',
      'save': '保存修改',
      'settingsTitle': '服务器与网络设置',
      'serverLabel': 'WebSocket 信令服务器地址',
      'stunLabel': 'STUN 打洞穿透服务器',
      'applySave': '应用并保存',
      'settingsNote': '注：修改后将自动保存并重新连接信令服务。',
      'tokenLabel': '访问令牌（可选）',
      'languageLabel': '语言',
      'languageAuto': '跟随系统',
      'backgroundLabel': '自定义背景',
      'chooseImage': '选择图片',
      'resetBackground': '恢复默认',
      'backgroundSaved': '背景已更新',
      'backgroundReset': '背景已恢复默认',
      'backgroundError': '设置背景失败',
      'errorEmptyTarget': '请输入对方的用户 ID',
      'errorSelfCall': '不能呼叫自己',
      'errorNotConnected': '未连接到信令服务器',
      'callEnded': '通话已结束',
      'peerHangup': '对方已挂断',
      'peerOffline': '对方已离线',
      'noAnswer': '对方未接听',
      'busy': '对方忙线中',
      'callRejected': '对方拒绝了通话',
      'callFailed': '通话建立失败，请检查网络',
      'micDenied': '麦克风不可用，请授予权限。',
      'avatar_pilot': '领航员',
      'avatar_cyber_fox': '极客狐',
      'avatar_cyber_cat': '赛博猫',
      'avatar_tiger': '荣耀虎',
      'avatar_panda': '功夫熊',
      'avatar_lion': '霸气狮',
      'avatar_dolphin': '星海豚',
      'avatar_eagle': '苍穹鹰',
      'avatar_unicorn': '独角兽',
      'avatar_robot': '极智机',
      'avatar_lightning': '光子速',
      'avatar_shield': '圣盾甲',
    },
    'fr': {
      'appTitle': 'Appel vocal P2P',
      'headerTitle': 'Voix directe P2P',
      'statusOnline': 'En ligne',
      'statusConnecting': 'Connexion',
      'statusReconnecting': 'Reconnexion',
      'statusOffline': 'Hors ligne',
      'tooltipLightTheme': 'Passer au thème clair',
      'tooltipDarkTheme': 'Passer au thème sombre',
      'tooltipSettings': 'Paramètres réseau et serveur',
      'tooltipCopy': "Copier l'ID",
      'tooltipEdit': "Modifier l'ID",
      'myUserIdLabel': 'Mon identifiant',
      'loading': 'Chargement...',
      'toastCopied': 'Identifiant copié',
      'unknownUser': 'Appareil inconnu',
      'secureNotice':
          'Connexion directe sécurisée : l’audio est transmis en pair-à-pair via DTLS-SRTP chiffré, sans stockage cloud, protégé contre les écoutes et les altérations.',
      'dialTitle': 'Lancer un appel P2P',
      'dialHint': "Saisir l'ID du correspondant (ex. user_8888)",
      'dialButton': 'Démarrer l’appel HD direct',
      'onlineDevices': 'Appareils en ligne',
      'noPeers': 'Aucun autre appareil en ligne',
      'noPeersHint': 'Lancez l’application sur un autre téléphone',
      'directCall': 'Appeler',
      'incomingCall': 'Appel P2P entrant',
      'e2eUdpBadge': 'Direct UDP chiffré de bout en bout',
      'hangup': 'Raccrocher',
      'answer': 'Répondre',
      'secureCalling': '🔒 Appel sécurisé chiffré de bout en bout',
      'p2pCalling': '🟢 Appel direct 100% P2P',
      'establishing': 'Établissement de la connexion chiffrée...',
      'negotiating': 'Signalisation et traversée NAT...',
      'transportProtocol': 'Transport',
      'iceStateLabel': 'État ICE',
      'micLabel': 'Micro',
      'mutedLabel': 'Muet',
      'speakerLabel': 'Haut-parleur',
      'earpieceLabel': 'Écouteur',
      'avatarPickerTitle': 'Choisissez votre avatar',
      'editIdTitle': "Modifier l'ID",
      'enterNewIdHint': 'Nouvel ID',
      'cancel': 'Annuler',
      'save': 'Enregistrer',
      'settingsTitle': 'Paramètres serveur et réseau',
      'serverLabel': 'Adresse du serveur de signalisation WebSocket',
      'stunLabel': 'Serveur STUN',
      'applySave': 'Appliquer et enregistrer',
      'settingsNote':
          'Remarque : les modifications sont enregistrées et le service de signalisation se reconnecte.',
      'tokenLabel': "Jeton d'accès (optionnel)",
      'languageLabel': 'Langue',
      'languageAuto': 'Suivre le système',
      'backgroundLabel': 'Arrière-plan personnalisé',
      'chooseImage': 'Choisir une image',
      'resetBackground': 'Rétablir par défaut',
      'backgroundSaved': 'Arrière-plan mis à jour',
      'backgroundReset': 'Arrière-plan réinitialisé',
      'backgroundError': "Échec de la mise à jour de l'arrière-plan",
      'errorEmptyTarget': "Saisissez l'ID du correspondant",
      'errorSelfCall': 'Impossible de s’appeler soi-même',
      'errorNotConnected': 'Non connecté au serveur de signalisation',
      'callEnded': 'Appel terminé',
      'peerHangup': 'Le correspondant a raccroché',
      'peerOffline': 'Le correspondant est hors ligne',
      'noAnswer': 'Pas de réponse',
      'busy': 'Ligne occupée',
      'callRejected': 'Appel refusé',
      'callFailed': 'Échec de l’établissement de l’appel',
      'micDenied': 'Microphone indisponible. Veuillez autoriser l’accès.',
      'avatar_pilot': 'Pilote',
      'avatar_cyber_fox': 'Renard cyber',
      'avatar_cyber_cat': 'Chat cyber',
      'avatar_tiger': 'Tigre',
      'avatar_panda': 'Panda',
      'avatar_lion': 'Lion',
      'avatar_dolphin': 'Dauphin',
      'avatar_eagle': 'Aigle',
      'avatar_unicorn': 'Licorne',
      'avatar_robot': 'Robot',
      'avatar_lightning': 'Éclair',
      'avatar_shield': 'Bouclier',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.languageCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
