import 'dart:async';
import 'dart:io';

import '../models/models.dart';
import 'p2p_transport.dart';

/// In-memory P2PTransport used in widget tests and optional Demo Preview mode.
class MockP2PTransport implements P2PTransport {
  final StreamController<BridgeEvent> _events = StreamController<BridgeEvent>.broadcast();
  int _seq = 10;

  @override
  Stream<BridgeEvent> get events => _events.stream;

  void emitTestEvent(BridgeEvent ev) => _events.add(ev);

  @override
  Future<NodeStartResult> startNode({
    required String identityPath,
    required List<String> staticRelays,
    bool enableMdns = true,
    bool forcePrivate = false,
    bool enableHolePunching = true,
  }) async {
    return const NodeStartResult(
      peerId: '12D3KooWMob9xR7vKpQ4tLn2YwE8sUa6ZcH5dFg1jB3mN9',
      addrs: ['/ip4/192.168.1.21/tcp/4001/p2p/12D3KooWMob9xR7vKpQ4tLn2YwE8sUa6ZcH5dFg1jB3mN9'],
    );
  }

  @override
  Future<void> stopNode() async {}

  @override
  Future<ConnDiagnostics> connectHost({
    required String peerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
  }) async {
    return ConnDiagnostics(
      peerId: peerId,
      connected: true,
      pathType: 'relay',
      transport: 'Circuit Relay v2 · QUIC + Noise',
      remoteAddr: '/dns4/sg-relay-1.myhome.dev/udp/4001/quic-v1/p2p/12D3KooWRelaySg1/p2p-circuit',
      relayPeerId: '12D3KooWRelaySg1',
      rttMs: 64,
      isRelayed: true,
    );
  }

  @override
  Future<void> disconnectHost(String peerId) async {}

  @override
  Future<ConnDiagnostics> diagnostics(String peerId) => connectHost(peerId: peerId);

  @override
  Future<HolePunchResult> retryHolePunch(String peerId) async {
    final d = await connectHost(peerId: peerId);
    return HolePunchResult(
      diagnostics: d,
      message: 'Both peers behind Symmetric NAT — maintaining Circuit Relay v2 (64 ms).',
    );
  }

  @override
  Future<List<LANDiscoveredPeer>> discoverLAN({int timeoutMs = 400}) async {
    return const [
      LANDiscoveredPeer(
        peerId: '12D3KooWDevBox4xKp9Lm2NrT5vKc8Wz4',
        addrs: ['/ip4/192.168.1.48/tcp/4001'],
      ),
    ];
  }

  @override
  Future<PairChallengeInfo> pairStart({
    String? uri,
    String? hostPeerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
    String? token,
    String? pin,
    String deviceName = 'Android Device',
  }) async {
    return PairChallengeInfo(
      sessionId: 'pair-mock-1',
      hostPeerId: hostPeerId?.isNotEmpty == true ? hostPeerId! : '12D3KooWLabNode9xK2mPq',
      hostName: 'homelab-node',
      sasDigits: '742-918',
      sasEmojis: '🛰️ 🔐 ⚡',
    );
  }

  @override
  Future<PairResultInfo> pairConfirm(String pairSessionId, bool accept) async {
    return PairResultInfo(
      paired: accept,
      hostPeerId: '12D3KooWLabNode9xK2mPq',
      hostName: 'homelab-node',
      hostOs: 'linux · arm64',
      agyVersion: 'agy v1.5.13',
      relayAddrs: const ['/dns4/sg-relay-1.myhome.dev/udp/4001/quic-v1/p2p/12D3KooWRelaySg1'],
    );
  }

  @override
  Future<dynamic> rpcCall(String peerId, String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'host/info':
        return {
          'hostPeerId': peerId,
          'hostname': 'home-workstation',
          'os': 'linux',
          'arch': 'arm64',
          'agyVersion': 'agy v1.5.13',
          'cpuPercent': 28,
          'ramPercent': 54,
          'authReady': true,
        };
      case 'session/list':
        return {'sessions': []};
      case 'session/prompt':
        final sid = (params['sessionId'] ?? '').toString();
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          _seq++;
          _events.add(BridgeEvent(type: 'acp_event', raw: {
            'type': 'acp_event',
            'peerId': peerId,
            'event': {
              'seq': _seq,
              'sessionId': sid,
              'kind': 'session_update',
              'payload': {
                'sessionId': sid,
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': 'Processed prompt & staged /tmp files.'}
                }
              }
            }
          }));
        });
        return {'accepted': true, 'turnId': 'mock-turn'};
      default:
        return {'ok': true};
    }
  }

  @override
  Future<void> subscribeEvents(String peerId, int sinceSeq) async {}

  @override
  Future<UploadedAttachment> uploadFileToTmp({
    required String peerId,
    required String sessionId,
    required String localPath,
    required String filename,
    String mimeType = '',
  }) async {
    final size = File(localPath).existsSync() ? File(localPath).lengthSync() : 1024;
    _events.add(BridgeEvent(type: 'upload_progress', raw: {
      'type': 'upload_progress',
      'sessionId': sessionId,
      'filename': filename,
      'sentBytes': size,
      'totalBytes': size,
    }));
    final isImg = filename.endsWith('.png') || filename.endsWith('.jpg') || filename.endsWith('.jpeg');
    return UploadedAttachment(
      uploadId: 'up_${DateTime.now().millisecondsSinceEpoch}',
      localPath: localPath,
      remotePath: '/tmp/agyd-uploads/$sessionId/$filename',
      filename: filename,
      mimeType: mimeType.isNotEmpty ? mimeType : (isImg ? 'image/png' : 'text/plain'),
      sizeBytes: size,
      isImage: isImg,
      progress: 1.0,
      uploading: false,
    );
  }

  @override
  Future<void> notifyNetworkChanged() async {}

  @override
  void dispose() {
    _events.close();
  }
}
