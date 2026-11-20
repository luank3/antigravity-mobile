import 'dart:convert';
import 'dart:io';

import 'package:agy_mobile/core/models/models.dart';
import 'package:agy_mobile/core/platform/android_runtime.dart';
import 'package:agy_mobile/core/state/app_state.dart';
import 'package:agy_mobile/core/theme/app_theme.dart';
import 'package:agy_mobile/core/transport/mock_p2p_transport.dart';
import 'package:agy_mobile/features/chat/chat_items.dart';
import 'package:agy_mobile/features/chat/markdown_body.dart';
import 'package:agy_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App navigation, permission approval, and /tmp upload chip work',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final mock = MockP2PTransport();
    addTearDown(mock.dispose);

    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_support_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(mock),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Sessions tab is default and shows demo session.
    expect(find.text('libp2p NAT Traversal & Relay'), findsOneWidget);

    // Navigate to Hosts tab.
    await tester.tap(find.text('Hosts'));
    await tester.pumpAndSettle();
    expect(find.text('Paired Machines'), findsOneWidget);

    // Navigate to Workspace tab.
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('pkg/p2p/dialer.go'), findsOneWidget);

    // Navigate to Settings tab.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12D3KooWMob9x'), findsOneWidget);

    // Return to Sessions and open Active Chat.
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('libp2p NAT Traversal & Relay'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Allow Once'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('chat-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow Once'), findsOneWidget);

    // Resolve permission card.
    await tester.tap(find.text('Allow Once'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Allowed Once'), findsOneWidget);

    // Upload a local temp file and verify staged /tmp chip renders in composer.
    final tmpDir = Directory.systemTemp.createTempSync('agy_widget_upload_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final sampleFile = File('${tmpDir.path}/sample.log')..writeAsStringSync('log line\n');

    final uploadFuture = container.read(appControllerProvider.notifier).uploadLocalFile(
          localPath: sampleFile.path,
          filename: 'sample.log',
          mimeType: 'text/plain',
        );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await uploadFuture;
    await tester.pumpAndSettle();
    expect(find.text('sample.log (/tmp)'), findsOneWidget);
  });

  testWidgets('Handles real agy acp thought, tool_call upsert, and usage updates',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final mock = MockP2PTransport();
    addTearDown(mock.dispose);

    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_acp_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(mock),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('libp2p NAT Traversal & Relay'));
    await tester.pumpAndSettle();

    mock.emitTestEvent(const BridgeEvent(type: 'acp_event', raw: {
      'type': 'acp_event',
      'event': {
        'seq': 100,
        'sessionId': 'sess-nat-relay',
        'kind': 'session_update',
        'payload': {
          'sessionId': 'sess-nat-relay',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': {'type': 'text', 'text': 'Checking real ACP stream...'}
          }
        }
      }
    }));

    mock.emitTestEvent(const BridgeEvent(type: 'acp_event', raw: {
      'type': 'acp_event',
      'event': {
        'seq': 101,
        'sessionId': 'sess-nat-relay',
        'kind': 'session_update',
        'payload': {
          'sessionId': 'sess-nat-relay',
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tc-live-1',
            'name': 'run_command',
            'kind': 'execute',
            'status': 'completed',
            'title': 'echo hello',
            'rawInput': {'CommandLine': 'echo hello'},
            'rawOutput': {'output': 'hello', 'exit_code': 0}
          }
        }
      }
    }));

    mock.emitTestEvent(const BridgeEvent(type: 'acp_event', raw: {
      'type': 'acp_event',
      'event': {
        'seq': 102,
        'sessionId': 'sess-nat-relay',
        'kind': 'session_update',
        'payload': {
          'sessionId': 'sess-nat-relay',
          'update': {
            'sessionUpdate': 'usage_update',
            'used': 15900,
            'size': 1048576,
          }
        }
      }
    }));

    await tester.pumpAndSettle();
    expect(find.textContaining('15.9k/1049k'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('echo hello'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('chat-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('echo hello'), findsOneWidget);
  });

  testWidgets(
      'Background foreground service, alert notifications, event reconnect, and resume sync',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final spyTransport = _SpyP2PTransport();
    final spyRuntime = _SpyAndroidRuntime();
    addTearDown(spyTransport.dispose);

    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_bg_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(spyTransport),
        androidRuntimeProvider.overrideWithValue(spyRuntime),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    final controller = container.read(appControllerProvider.notifier);

    // Pair and select a real host so foreground keepalive service activates.
    final chal = await controller.startPairing(hostPeerId: '12D3KooWRealHostBgTest');
    final paired = await controller.confirmPairing(chal, true);
    expect(paired, isNotNull);
    await tester.pumpAndSettle();
    expect(spyRuntime.fgStartCount, greaterThanOrEqualTo(1));

    // Background the app following Flutter's lifecycle state machine and emit events.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(container.read(appControllerProvider).isAppBackgrounded, isTrue);

    spyTransport.emitTestEvent(const BridgeEvent(type: 'acp_event', raw: {
      'type': 'acp_event',
      'event': {
        'seq': 41,
        'sessionId': 'sess-nat-relay',
        'kind': 'permission_request',
        'payload': {
          'permId': 'perm-bg-1',
          'toolCall': {
            'title': 'Run background test',
            'rawInput': {'CommandLine': 'flutter test'}
          },
          'options': [
            {'optionId': 'allow-once', 'name': 'Allow Once', 'kind': 'allow_once'}
          ]
        }
      }
    }));

    spyTransport.emitTestEvent(const BridgeEvent(type: 'acp_event', raw: {
      'type': 'acp_event',
      'event': {
        'seq': 42,
        'sessionId': 'sess-nat-relay',
        'kind': 'turn_complete',
        'payload': {'stopReason': 'end_turn'}
      }
    }));

    await tester.pump();
    expect(spyRuntime.alerts.length, 2);
    expect(spyRuntime.alerts[0].$1, contains('Approval Needed'));
    expect(spyRuntime.alerts[0].$2, 'flutter test');
    expect(spyRuntime.alerts[1].$1, 'Agent Turn Complete');

    // Simulate stream drop while connected and verify backoff reconnect from seq 42.
    final connectBeforeDrop = spyTransport.connectCalls;
    final subsBeforeDrop = spyTransport.subscribeSeqs.length;
    spyTransport.emitTestEvent(BridgeEvent(type: 'events_disconnected', raw: {
      'type': 'events_disconnected',
      'peerId': paired!.peerId,
      'error': 'EOF',
    }));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(spyTransport.connectCalls, greaterThan(connectBeforeDrop));
    expect(spyTransport.subscribeSeqs.length, greaterThan(subsBeforeDrop));
    expect(spyTransport.subscribeSeqs.last, 42);

    // Clear the 3s transient banner timer before testing resume.
    await tester.pump(const Duration(seconds: 4));

    // Resume from background and verify network refresh + reconnect + resubscribe.
    final netBeforeResume = spyTransport.networkChangedCalls;
    final connectBeforeResume = spyTransport.connectCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(appControllerProvider).isAppBackgrounded, isFalse);
    expect(spyTransport.networkChangedCalls, greaterThan(netBeforeResume));
    expect(spyTransport.connectCalls, greaterThan(connectBeforeResume));

    // Advance past the 3s banner clear timer so no pending timers remain.
    await tester.pump(const Duration(seconds: 4));
    expect(container.read(appControllerProvider).handoffBanner, isNull);
  });

  testWidgets('AgyMarkdownView and user image thumbnail preview work',
      (WidgetTester tester) async {
    final tmpImgDir = Directory.systemTemp.createTempSync('agy_img_widget_');
    addTearDown(() => tmpImgDir.deleteSync(recursive: true));
    final imgFile = File('${tmpImgDir.path}/shot.png')
      ..writeAsBytesSync(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChatMessageTile(
                  msg: ChatMessage(
                    id: 'u-img-1',
                    kind: ChatMessageKind.user,
                    text: 'Inspect screenshot',
                    imagePaths: [imgFile.path],
                  ),
                  onToggleThink: () {},
                  onViewDiff: (_, _) {},
                  onResolvePermission: (_, {optionId}) {},
                ),
                const SizedBox(height: 12),
                const AgyMarkdownView(
                  data: '## Summary\n- Checked **QUIC** & `relay`\n\n```dart\nfinal ok = true;\n```',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.textContaining('final ok = true', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.text('Code copied'), findsOneWidget);

    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('Startup auto-connects persisted host and probes configured relays',
      (WidgetTester tester) async {
    const persistedPeerId = '12D3KooWPersistedHostAutoConnect';
    const relayAddr = '/dns4/relay.example.com/tcp/4001/p2p/12D3KooWRelayProbePeer';

    SharedPreferences.setMockInitialValues({
      'agy_paired_hosts_v1': jsonEncode([
        const PairedHost(
          id: persistedPeerId,
          peerId: persistedPeerId,
          name: 'persisted-vps',
          os: 'linux · arm64',
          agyVersion: 'agy v1.5.13',
          relayAddrs: ['$relayAddr/p2p-circuit/p2p/$persistedPeerId'],
          diagnostics: ConnDiagnostics(
            peerId: persistedPeerId,
            connected: false,
            pathType: 'disconnected',
            transport: '',
            remoteAddr: '',
          ),
        ).toJson(),
      ]),
      'agy_active_host_v1': persistedPeerId,
      'agy_relays_v1': jsonEncode([
        const RelayEndpoint(
          name: 'relay.example.com',
          multiaddr: relayAddr,
          status: 'Configured',
          online: true,
        ).toJson(),
      ]),
    });

    final spyTransport = _SpyP2PTransport();
    final spyRuntime = _SpyAndroidRuntime();
    addTearDown(spyTransport.dispose);

    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_auto_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(spyTransport),
        androidRuntimeProvider.overrideWithValue(spyRuntime),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    final stateAfterBoot = container.read(appControllerProvider);
    expect(stateAfterBoot.activeHostId, persistedPeerId);
    expect(spyTransport.connectCalls, greaterThanOrEqualTo(1));
    expect(
      stateAfterBoot.hosts.firstWhere((h) => h.id == persistedPeerId).diagnostics.connected,
      isTrue,
    );

    await container.read(appControllerProvider.notifier).probeRelays();
    final relays = container.read(appControllerProvider).relays;
    expect(relays, hasLength(1));
    expect(relays.first.online, isTrue);
    expect(relays.first.status, 'Online · 64ms');
  });

  testWidgets('NewSessionSheet displays workspaceRoots chips and updates cwd',
      (WidgetTester tester) async {
    const hostPeerId = '12D3KooWWorkspaceRootsHost';
    SharedPreferences.setMockInitialValues({
      'agy_paired_hosts_v1': jsonEncode([
        const PairedHost(
          id: hostPeerId,
          peerId: hostPeerId,
          name: 'dev-box',
          os: 'linux · arm64',
          agyVersion: 'agy v1.5.13',
          workspaceRoots: ['/srv/api', '/srv/web'],
          diagnostics: ConnDiagnostics(
            peerId: hostPeerId,
            connected: true,
            pathType: 'lan',
            transport: 'QUIC',
            remoteAddr: '',
          ),
        ).toJson(),
      ]),
      'agy_active_host_v1': hostPeerId,
    });

    final mock = MockP2PTransport();
    addTearDown(mock.dispose);
    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_roots_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(mock),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();

    expect(find.text('ALLOWED WORKSPACE ROOTS'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '/srv/api'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '/srv/web'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '/srv/web'));
    await tester.pumpAndSettle();

    final cwdField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Remote Workspace Folder (cwd)'),
    );
    expect(cwdField.controller?.text, '/srv/web');
  });

  testWidgets(
      'Copy transcript exports Markdown, Test Alert notifies, and in-flight /tmp upload cancels cleanly',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text']?.toString();
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final mock = MockP2PTransport();
    final spyRuntime = _SpyAndroidRuntime();
    addTearDown(mock.dispose);
    final tmpSupport = Directory.systemTemp.createTempSync('agy_widget_qol_');
    addTearDown(() => tmpSupport.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(mock),
        androidRuntimeProvider.overrideWithValue(spyRuntime),
        supportDirProvider.overrideWithValue(tmpSupport.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open demo session chat and test Copy Transcript.
    await tester.tap(find.text('libp2p NAT Traversal & Relay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy transcript'));
    await tester.pump();
    expect(find.text('Transcript copied as Markdown'), findsOneWidget);
    expect(copiedText, contains('# libp2p NAT Traversal & Relay'));
    expect(copiedText, contains('## User'));
    expect(copiedText, contains('## Assistant'));

    // Start an in-flight /tmp upload, cancel it immediately, and verify it stays gone.
    final tmpUpload = Directory.systemTemp.createTempSync('agy_cancel_up_');
    addTearDown(() => tmpUpload.deleteSync(recursive: true));
    final sample = File('${tmpUpload.path}/cancel.log')..writeAsStringSync('data');
    final controller = container.read(appControllerProvider.notifier);

    final uploadFuture = controller.uploadLocalFile(
      localPath: sample.path,
      filename: 'cancel.log',
      mimeType: 'text/plain',
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(container.read(appControllerProvider).stagedUploads, hasLength(1));
    await controller.removeStagedUpload(container.read(appControllerProvider).stagedUploads.first);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await uploadFuture;
    expect(container.read(appControllerProvider).stagedUploads, isEmpty);

    // Return to Settings and tap Send Test Alert.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send Test Alert'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(find.text('Test notification sent'), findsOneWidget);
    expect(spyRuntime.alerts, isNotEmpty);
    expect(spyRuntime.alerts.last.$1, 'Antigravity Test Alert');
  });

  testWidgets('Cannot create session when no host is paired', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = Directory.systemTemp.createTempSync('agy_no_host_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final transport = MockP2PTransport();
    addTearDown(transport.dispose);

    final container = ProviderContainer(
      overrides: [
        p2pTransportProvider.overrideWithValue(transport),
        supportDirProvider.overrideWithValue(tmpDir.path),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AntigravityMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(appControllerProvider.notifier).toggleDemoHost(false);
    await tester.pumpAndSettle();

    expect(find.text('New Session'), findsNothing);
    expect(find.text('No Paired Host'), findsOneWidget);
    expect(find.text('Pair Machine'), findsOneWidget);

    expect(
      () => container.read(appControllerProvider.notifier).createNewSession(
            cwd: '/tmp',
            title: 'Should Fail',
            mode: 'Auto',
            model: 'Neon High',
          ),
      throwsStateError,
    );
  });
}

class _SpyAndroidRuntime implements AndroidRuntime {
  int fgStartCount = 0;
  int fgStopCount = 0;
  bool keepScreenOn = false;
  final List<(String, String)> alerts = [];

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<bool> requestCameraPermission() async => true;

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    keepScreenOn = enabled;
  }

  @override
  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    alerts.add((title, body));
  }

  @override
  Future<void> startForegroundService({
    required String title,
    required String body,
    bool holdWakeLock = false,
  }) async {
    fgStartCount++;
  }

  @override
  Future<void> stopForegroundService() async {
    fgStopCount++;
  }
}

class _SpyP2PTransport extends MockP2PTransport {
  int connectCalls = 0;
  int networkChangedCalls = 0;
  final List<int> subscribeSeqs = [];

  @override
  Future<ConnDiagnostics> connectHost({
    required String peerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
  }) {
    connectCalls++;
    return super.connectHost(
      peerId: peerId,
      directAddrs: directAddrs,
      relayAddrs: relayAddrs,
    );
  }

  @override
  Future<void> subscribeEvents(String peerId, int sinceSeq) {
    subscribeSeqs.add(sinceSeq);
    return super.subscribeEvents(peerId, sinceSeq);
  }

  @override
  Future<void> notifyNetworkChanged() {
    networkChangedCalls++;
    return super.notifyNetworkChanged();
  }
}
