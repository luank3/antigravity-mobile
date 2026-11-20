import '../models/models.dart';

class NodeStartResult {
  final String peerId;
  final List<String> addrs;

  const NodeStartResult({required this.peerId, required this.addrs});
}

class HolePunchResult {
  final ConnDiagnostics diagnostics;
  final String message;

  const HolePunchResult({required this.diagnostics, required this.message});
}

/// Clean transport abstraction decoupling Flutter UI/Riverpod from go-libp2p FFI internals.
abstract class P2PTransport {
  Stream<BridgeEvent> get events;

  Future<NodeStartResult> startNode({
    required String identityPath,
    required List<String> staticRelays,
    bool enableMdns = true,
    bool forcePrivate = false,
    bool enableHolePunching = true,
  });

  Future<void> stopNode();

  Future<ConnDiagnostics> connectHost({
    required String peerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
  });

  Future<void> disconnectHost(String peerId);

  Future<ConnDiagnostics> diagnostics(String peerId);

  Future<HolePunchResult> retryHolePunch(String peerId);

  Future<List<LANDiscoveredPeer>> discoverLAN({int timeoutMs = 400});

  Future<PairChallengeInfo> pairStart({
    String? uri,
    String? hostPeerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
    String? token,
    String? pin,
    String deviceName = 'Android Device',
  });

  Future<PairResultInfo> pairConfirm(String pairSessionId, bool accept);

  Future<dynamic> rpcCall(String peerId, String method, Map<String, dynamic> params);

  Future<void> subscribeEvents(String peerId, int sinceSeq);

  Future<UploadedAttachment> uploadFileToTmp({
    required String peerId,
    required String sessionId,
    required String localPath,
    required String filename,
    String mimeType = '',
  });

  Future<void> notifyNetworkChanged();

  void dispose();
}
