enum CallStatus {
  idle,
  calling,
  incoming,
  connected,
  ended,
}

enum SignalingStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class P2PCallInfo {
  final String peerId;
  final bool isCaller;
  final DateTime startTime;

  P2PCallInfo({
    required this.peerId,
    required this.isCaller,
    required this.startTime,
  });
}
