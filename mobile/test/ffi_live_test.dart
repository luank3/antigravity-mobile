import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agy_mobile/core/transport/ffi_p2p_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart FFI loads libagyp2p.so, pairs through agy-relay, runs ACP RPC, and uploads file to /tmp',
      () async {
    final repoRoot = Directory.current.path.endsWith('/mobile')
        ? Directory.current.parent.path
        : Directory.current.path;
    final libPath = '$repoRoot/mobile/native/linux-arm64/libagyp2p.so';
    final relayBin = '$repoRoot/server/bin/agy-relay';
    final agydBin = '$repoRoot/server/bin/agyd';

    if (!File(libPath).existsSync() ||
        !File(relayBin).existsSync() ||
        !File(agydBin).existsSync()) {
      // Integration binaries not pre-compiled in this workspace; skip.
      return;
    }

    final tmp = Directory.systemTemp.createTempSync('agy_ffi_live_');
    Process? relayProc;
    Process? agydProc;
    FfiP2PTransport? transport;

    try {
      // 1. Write minimal mock ACP script for agyd.
      final mockAcp = File('${tmp.path}/mock_acp.py')
        ..writeAsStringSync('''#!/usr/bin/env python3
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    m = json.loads(line)
    mid = m.get("id")
    meth = m.get("method")
    if meth == "initialize":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":True}}}), flush=True)
    elif meth == "session/list":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"sessions":[{"sessionId":"sess-ffi","cwd":"${tmp.path}","title":"FFI Live Session"}]}}), flush=True)
''');
      await Process.run('chmod', ['+x', mockAcp.path]);

      // 2. Start agy-relay on ephemeral localhost TCP port.
      relayProc = await Process.start(relayBin, [
        '--identity',
        '${tmp.path}/relay.key',
        '--listen',
        '/ip4/127.0.0.1/tcp/0',
      ]);

      final relayAddrCompleter = Completer<String>();
      relayProc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.contains('listen:') && !relayAddrCompleter.isCompleted) {
          relayAddrCompleter.complete(line.split('listen:').last.trim());
        }
      });
      final relayAddr = await relayAddrCompleter.future.timeout(const Duration(seconds: 8));

      // 3. Start agyd pointing at agy-relay with --force-private.
      final agydCfgDir = '${tmp.path}/agyd-cfg';
      agydProc = await Process.start(agydBin, [
        'run',
        '--config-dir',
        agydCfgDir,
        '--agy',
        mockAcp.path,
        '--listen',
        '/ip4/127.0.0.1/tcp/0',
        '--relay',
        relayAddr,
        '--force-private',
        '--mdns=false',
        '--workspace',
        tmp.path,
      ]);

      final agydReady = Completer<String>();
      agydProc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.contains('Relay:') && !agydReady.isCompleted) {
          agydReady.complete(line.split('Relay:').last.trim());
        }
      });
      await agydReady.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 4. Generate single-use pairing URI via `agyd pair`, strip direct `&addr=` params to force Relay!
      final pairOut = await Process.run(agydBin, [
        'pair',
        '--config-dir',
        agydCfgDir,
        '--trust-next=true',
      ]);
      expect(pairOut.exitCode, 0, reason: pairOut.stderr.toString());
      final uriLine = pairOut.stdout
          .toString()
          .split('\n')
          .firstWhere((l) => l.startsWith('agy://pair?'));
      final fullUri = Uri.parse(uriLine.trim());
      final relayOnlyParams = Map<String, List<String>>.from(fullUri.queryParametersAll)
        ..remove('addr');
      final relayOnlyUri = Uri(
        scheme: 'agy',
        host: 'pair',
        queryParameters: relayOnlyParams,
      ).toString();

      // 5. Start real go-libp2p node from Dart via FFI.
      transport = FfiP2PTransport(customLibPath: libPath);
      final node = await transport.startNode(
        identityPath: '${tmp.path}/mobile.key',
        staticRelays: [relayAddr],
        enableMdns: false,
        forcePrivate: true,
      );
      expect(node.peerId, startsWith('12D3KooW'));

      // 6. Pair over Circuit Relay v2 and verify SAS.
      final chal = await transport.pairStart(uri: relayOnlyUri, deviceName: 'Dart FFI Test');
      expect(chal.sasDigits, matches(RegExp(r'^\d{3}-\d{3}$')));
      final pairRes = await transport.pairConfirm(chal.sessionId, true);
      expect(pairRes.paired, isTrue);

      final diag = await transport.diagnostics(pairRes.hostPeerId);
      expect(diag.connected, isTrue);
      expect(diag.isRelayed, isTrue);

      // 7. Call RPCs through relay.
      final listRes = await transport.rpcCall(pairRes.hostPeerId, 'session/list', {});
      expect(jsonEncode(listRes), contains('sess-ffi'));

      // 8. Stream file upload over /agy/blob/1.0.0 through relay into remote /tmp.
      final localUpload = File('${tmp.path}/hello_from_dart.txt')
        ..writeAsStringSync('hello remote tmp via circuit relay v2\n');
      final upRes = await transport.uploadFileToTmp(
        peerId: pairRes.hostPeerId,
        sessionId: 'sess-ffi',
        localPath: localUpload.path,
        filename: 'hello_from_dart.txt',
        mimeType: 'text/plain',
      );
      expect(upRes.uploadId, isNotEmpty);
      expect(File(upRes.remotePath).readAsStringSync(), 'hello remote tmp via circuit relay v2\n');
    } finally {
      transport?.dispose();
      agydProc?.kill();
      relayProc?.kill();
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    }
  });
}
