import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agy_mobile/core/transport/ffi_p2p_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hasAgy = File('/home/dat/.local/bin/agy').existsSync();

  test(
    'Real agy acp E2E over Circuit Relay v2: host/info, session/list, session/load, workspace RPCs, and /tmp upload',
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

      final tmp = Directory.systemTemp.createTempSync('agy_real_e2e_');
      Process? relayProc;
      Process? agydProc;
      FfiP2PTransport? transport;

      try {
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
        final relayAddr =
            await relayAddrCompleter.future.timeout(const Duration(seconds: 8));

        final agydCfgDir = '${tmp.path}/agyd-cfg';
        agydProc = await Process.start(agydBin, [
          'run',
          '--config-dir',
          agydCfgDir,
          '--agy',
          '/home/dat/.local/bin/agy',
          '--listen',
          '/ip4/127.0.0.1/tcp/0',
          '--relay',
          relayAddr,
          '--force-private',
          '--mdns=false',
          '--workspace',
          repoRoot,
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
        await agydReady.future.timeout(const Duration(seconds: 15));
        await Future<void>.delayed(const Duration(milliseconds: 350));

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
        final relayOnlyParams =
            Map<String, List<String>>.from(fullUri.queryParametersAll)
              ..remove('addr');
        final relayOnlyUri = Uri(
          scheme: 'agy',
          host: 'pair',
          queryParameters: relayOnlyParams,
        ).toString();

        transport = FfiP2PTransport(customLibPath: libPath);
        final node = await transport.startNode(
          identityPath: '${tmp.path}/mobile.key',
          staticRelays: [relayAddr],
          enableMdns: false,
          forcePrivate: true,
        );
        expect(node.peerId, startsWith('12D3KooW'));

        final chal = await transport.pairStart(
          uri: relayOnlyUri,
          deviceName: 'Real AGY E2E Client',
        );
        final pairRes = await transport.pairConfirm(chal.sessionId, true);
        expect(pairRes.paired, isTrue);

        // 1. Real host/info telemetry (/proc/meminfo & /proc/stat)
        final infoRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'host/info',
          {},
        ) as Map<String, dynamic>;
        expect((infoRes['ramPercent'] as num).toInt(), greaterThan(0));

        // 2. Real session/list from agy acp
        final listRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'session/list',
          {},
        ) as Map<String, dynamic>;
        final sessions = listRes['sessions'] as List;
        expect(sessions, isNotEmpty);

        // 3. Subscribe to events + load real read-only session 690253e4-...
        final receivedUpdateTypes = <String>{};
        final sub = transport.events.listen((ev) {
          if (ev.type == 'acp_event') {
            final inner = ev.raw['event'] as Map<String, dynamic>? ?? const {};
            final payload = inner['payload'];
            if (payload is Map<String, dynamic>) {
              final upd = payload['update'];
              if (upd is Map<String, dynamic>) {
                final t = (upd['sessionUpdate'] ?? '').toString();
                if (t.isNotEmpty) receivedUpdateTypes.add(t);
              }
            }
          }
        });

        await transport.subscribeEvents(pairRes.hostPeerId, 0);
        final loadRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'session/load',
          {
            'sessionId': '690253e4-2e47-4c2d-930d-6285cbe16fa6',
            'cwd': '/home/dat',
            'mcpServers': const [],
          },
        ) as Map<String, dynamic>;
        expect((loadRes['models'] as Map)['availableModels'], isNotEmpty);
        expect((loadRes['modes'] as Map)['availableModes'], isNotEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(receivedUpdateTypes, contains('agent_message_chunk'));
        expect(receivedUpdateTypes, contains('tool_call'));
        await sub.cancel();

        // 4. Workspace & Peers RPCs
        final treeRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'workspace/tree',
          {'root': repoRoot, 'path': '.'},
        ) as Map<String, dynamic>;
        expect(treeRes['entries'], isNotEmpty);

        final peersRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'peers/list',
          {},
        ) as Map<String, dynamic>;
        expect(peersRes['peers'], isNotEmpty);

        // 5. Real /tmp upload & delete
        final upFile = File('${tmp.path}/real_e2e_note.txt')
          ..writeAsStringSync('real agy e2e upload payload\n');
        final upRes = await transport.uploadFileToTmp(
          peerId: pairRes.hostPeerId,
          sessionId: '690253e4-2e47-4c2d-930d-6285cbe16fa6',
          localPath: upFile.path,
          filename: 'real_e2e_note.txt',
          mimeType: 'text/plain',
        );
        expect(
          File(upRes.remotePath).readAsStringSync(),
          'real agy e2e upload payload\n',
        );
        final delRes = await transport.rpcCall(
          pairRes.hostPeerId,
          'workspace/delete_tmp_file',
          {
            'sessionId': '690253e4-2e47-4c2d-930d-6285cbe16fa6',
            'uploadId': upRes.uploadId,
          },
        ) as Map<String, dynamic>;
        expect(delRes['deleted'], isTrue);
        expect(File(upRes.remotePath).existsSync(), isFalse);
      } finally {
        transport?.dispose();
        agydProc?.kill();
        relayProc?.kill();
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    },
    skip: !hasAgy ? 'Local agy binary not installed' : false,
  );
}
