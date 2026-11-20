import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../models/models.dart';
import 'p2p_transport.dart';

typedef _Str1C = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Str0C = Pointer<Utf8> Function();
typedef _Int1C = Pointer<Utf8> Function(Int32);
typedef _Int1Dart = Pointer<Utf8> Function(int);
typedef _StrIntC = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _StrIntDart = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _StrU64C = Pointer<Utf8> Function(Pointer<Utf8>, Uint64);
typedef _StrU64Dart = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _Str3C = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Str5C = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

DynamicLibrary _openAgyLib(String? customPath) {
  if (customPath != null && customPath.isNotEmpty) {
    return DynamicLibrary.open(customPath);
  }
  final envPath = Platform.environment['AGYP2P_LIB_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    return DynamicLibrary.open(envPath);
  }
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libagyp2p.so');
  }
  final candidates = [
    'native/linux-arm64/libagyp2p.so',
    '../mobile/native/linux-arm64/libagyp2p.so',
    'build/native/linux-arm64/libagyp2p.so',
    'libagyp2p.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return DynamicLibrary.open(path);
    }
  }
  return DynamicLibrary.open('libagyp2p.so');
}

String _consumeCString(DynamicLibrary lib, Pointer<Utf8> ptr) {
  if (ptr == nullptr) return '';
  final freeFn = lib.lookupFunction<_FreeC, _FreeDart>('AgyFreeString');
  try {
    return ptr.toDartString();
  } finally {
    freeFn(ptr);
  }
}

Map<String, dynamic> _decodeResponse(String raw) {
  if (raw.isEmpty) {
    throw StateError('Empty response from native libagyp2p bridge');
  }
  final map = jsonDecode(raw) as Map<String, dynamic>;
  if (map['ok'] != true) {
    throw StateError((map['error'] ?? 'Unknown native bridge error').toString());
  }
  return map;
}

class _PollerInit {
  final SendPort sendPort;
  final String? libPath;
  const _PollerInit(this.sendPort, this.libPath);
}

void _pollIsolateMain(_PollerInit init) {
  final lib = _openAgyLib(init.libPath);
  final pollFn = lib.lookupFunction<_Int1C, _Int1Dart>('AgyPollEvent');
  final controlPort = ReceivePort();
  init.sendPort.send(controlPort.sendPort);

  var running = true;
  controlPort.listen((msg) {
    if (msg == 'stop') {
      running = false;
      controlPort.close();
    }
  });

  // Cooperative loop scheduled cleanly via Timer.run so control messages can be processed.
  void tick() {
    if (!running) return;
    final ptr = pollFn(300);
    final raw = _consumeCString(lib, ptr);
    if (raw.isNotEmpty) {
      init.sendPort.send(raw);
    }
    if (running) {
      Timer.run(tick);
    }
  }

  Timer.run(tick);
}

/// FFI-backed P2PTransport running go-libp2p inside libagyp2p.so.
class FfiP2PTransport implements P2PTransport {
  final String? customLibPath;
  final StreamController<BridgeEvent> _eventsController =
      StreamController<BridgeEvent>.broadcast();

  ReceivePort? _receivePort;
  SendPort? _pollerControlPort;
  Isolate? _pollerIsolate;
  bool _disposed = false;

  FfiP2PTransport({this.customLibPath});

  @override
  Stream<BridgeEvent> get events => _eventsController.stream;

  Future<void> _startPoller() async {
    if (_pollerIsolate != null) return;
    final rp = ReceivePort();
    _receivePort = rp;
    final completer = Completer<void>();

    rp.listen((message) {
      if (message is SendPort) {
        _pollerControlPort = message;
        if (!completer.isCompleted) completer.complete();
      } else if (message is String && message.isNotEmpty && !_disposed) {
        try {
          _eventsController.add(BridgeEvent.parse(message));
        } catch (_) {}
      }
    });

    _pollerIsolate = await Isolate.spawn(
      _pollIsolateMain,
      _PollerInit(rp.sendPort, customLibPath),
    );
    await completer.future;
  }

  Future<void> _stopPoller() async {
    _pollerControlPort?.send('stop');
    _pollerControlPort = null;
    _pollerIsolate?.kill(priority: Isolate.immediate);
    _pollerIsolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

  @override
  Future<NodeStartResult> startNode({
    required String identityPath,
    required List<String> staticRelays,
    bool enableMdns = true,
    bool forcePrivate = false,
    bool enableHolePunching = true,
  }) async {
    final libPath = customLibPath;
    final cfgJson = jsonEncode({
      'identityPath': identityPath,
      'staticRelays': staticRelays,
      'enableMdns': enableMdns,
      'forcePrivate': forcePrivate,
      'enableHolePunching': enableHolePunching,
    });

    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyNodeStart');
      final arg = cfgJson.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });

    final map = _decodeResponse(raw);
    await _startPoller();
    return NodeStartResult(
      peerId: (map['peerId'] ?? '').toString(),
      addrs: (map['addrs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  @override
  Future<void> stopNode() async {
    await _stopPoller();
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str0C, _Str0C>('AgyNodeStop');
      return _consumeCString(lib, fn());
    });
    _decodeResponse(raw);
  }

  @override
  Future<ConnDiagnostics> connectHost({
    required String peerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
  }) async {
    final libPath = customLibPath;
    final payload = jsonEncode({
      'peerId': peerId,
      'directAddrs': directAddrs,
      'relayAddrs': relayAddrs,
    });
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyConnectHost');
      final arg = payload.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });
    final map = _decodeResponse(raw);
    return ConnDiagnostics.fromJson(map['diagnostics'] as Map<String, dynamic>);
  }

  @override
  Future<void> disconnectHost(String peerId) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyDisconnectHost');
      final arg = peerId.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });
    _decodeResponse(raw);
  }

  @override
  Future<ConnDiagnostics> diagnostics(String peerId) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyDiagnostics');
      final arg = peerId.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });
    final map = _decodeResponse(raw);
    return ConnDiagnostics.fromJson(map['diagnostics'] as Map<String, dynamic>);
  }

  @override
  Future<HolePunchResult> retryHolePunch(String peerId) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyRetryHolePunch');
      final arg = peerId.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });
    final map = _decodeResponse(raw);
    return HolePunchResult(
      diagnostics: ConnDiagnostics.fromJson(map['diagnostics'] as Map<String, dynamic>),
      message: (map['message'] ?? '').toString(),
    );
  }

  @override
  Future<List<LANDiscoveredPeer>> discoverLAN({int timeoutMs = 400}) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Int1C, _Int1Dart>('AgyDiscoverLAN');
      return _consumeCString(lib, fn(timeoutMs));
    });
    final map = _decodeResponse(raw);
    final list = map['peers'] as List? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(LANDiscoveredPeer.fromJson)
        .toList();
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
    final libPath = customLibPath;
    final payload = jsonEncode({
      'uri': uri ?? '',
      'hostPeerId': hostPeerId ?? '',
      'directAddrs': directAddrs,
      'relayAddrs': relayAddrs,
      'token': token ?? '',
      'pin': pin ?? '',
      'deviceName': deviceName,
    });
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str1C, _Str1C>('AgyPairStart');
      final arg = payload.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg));
      } finally {
        calloc.free(arg);
      }
    });
    final map = _decodeResponse(raw);
    return PairChallengeInfo.fromJson(map['challenge'] as Map<String, dynamic>);
  }

  @override
  Future<PairResultInfo> pairConfirm(String pairSessionId, bool accept) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_StrIntC, _StrIntDart>('AgyPairConfirm');
      final arg = pairSessionId.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(arg, accept ? 1 : 0));
      } finally {
        calloc.free(arg);
      }
    });
    final map = _decodeResponse(raw);
    return PairResultInfo.fromJson(map['result'] as Map<String, dynamic>);
  }

  @override
  Future<dynamic> rpcCall(String peerId, String method, Map<String, dynamic> params) async {
    final libPath = customLibPath;
    final paramsJson = jsonEncode(params);
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str3C, _Str3C>('AgyRPCCall');
      final pArg = peerId.toNativeUtf8();
      final mArg = method.toNativeUtf8();
      final jArg = paramsJson.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(pArg, mArg, jArg));
      } finally {
        calloc.free(pArg);
        calloc.free(mArg);
        calloc.free(jArg);
      }
    });
    final map = _decodeResponse(raw);
    return map['result'];
  }

  @override
  Future<void> subscribeEvents(String peerId, int sinceSeq) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_StrU64C, _StrU64Dart>('AgySubscribeEvents');
      final pArg = peerId.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(pArg, sinceSeq));
      } finally {
        calloc.free(pArg);
      }
    });
    _decodeResponse(raw);
  }

  @override
  Future<UploadedAttachment> uploadFileToTmp({
    required String peerId,
    required String sessionId,
    required String localPath,
    required String filename,
    String mimeType = '',
  }) async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str5C, _Str5C>('AgyUploadFile');
      final pArg = peerId.toNativeUtf8();
      final sArg = sessionId.toNativeUtf8();
      final lArg = localPath.toNativeUtf8();
      final fArg = filename.toNativeUtf8();
      final mArg = mimeType.toNativeUtf8();
      try {
        return _consumeCString(lib, fn(pArg, sArg, lArg, fArg, mArg));
      } finally {
        calloc.free(pArg);
        calloc.free(sArg);
        calloc.free(lArg);
        calloc.free(fArg);
        calloc.free(mArg);
      }
    });
    final map = _decodeResponse(raw);
    return UploadedAttachment.fromResultJson(
      localPath,
      map['result'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> notifyNetworkChanged() async {
    final libPath = customLibPath;
    final raw = await Isolate.run(() {
      final lib = _openAgyLib(libPath);
      final fn = lib.lookupFunction<_Str0C, _Str0C>('AgyNetworkChanged');
      return _consumeCString(lib, fn());
    });
    _decodeResponse(raw);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stopNode());
    _eventsController.close();
  }
}
