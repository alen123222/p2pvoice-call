/// Shared validation for editable identity and connection settings.
abstract final class InputValidation {
  static bool userId(String value) => RegExp(r'^[\w.-]{1,64}$').hasMatch(value);

  static bool signalingUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'ws' || uri.scheme == 'wss') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  static bool stunServer(String value) {
    final address = value.trim().replaceFirst(RegExp(r'^stun:'), '');
    final uri = Uri.tryParse('stun://$address');
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.path.isEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}
