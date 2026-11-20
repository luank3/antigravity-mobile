import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../platform/android_runtime.dart';
import '../transport/ffi_p2p_transport.dart';
import '../transport/p2p_transport.dart';

final supportDirProvider = Provider<String?>((ref) => null);

final androidRuntimeProvider = Provider<AndroidRuntime>((ref) {
  return MethodChannelAndroidRuntime();
});

final p2pTransportProvider = Provider<P2PTransport>((ref) {
  final t = FfiP2PTransport();
  ref.onDispose(t.dispose);
  return t;
});

class AppState {
  final bool initialized;
  final String mobilePeerId;
  final String? nodeError;
  final bool isDarkTheme;
  final bool showDemoHost;
  final int navTabIndex; // 0=Hosts, 1=Sessions, 2=Workspace, 3=Settings
  final String activeHostId;
  final String activeSessionId;
  final String? handoffBanner;
  final bool handoffSuccess;
  final bool isStreaming;
  final int lastEventSeq;
  final bool loadingSession;
  final bool loadingWorkspace;
  final int contextUsedTokens;
  final int contextMaxTokens;
  final Set<String> loadedRealSessions;

  // Preferences
  final bool preferMdns;
  final bool enableDcutr;
  final bool enableAutoRelay;
  final bool enablePublicRelayFallback;
  final bool enableForegroundService;
  final bool notifPermissions;
  final bool notifCompletion;
  final bool keepAwake;
  final bool isAppBackgrounded;
  final bool probingRelays;

  // Data
  final List<PairedHost> hosts;
  final List<AgentSession> sessions;
  final Map<String, List<ChatMessage>> messagesBySession;
  final Map<String, int> historyNextCursor;
  final Map<String, bool> historyHasMore;
  final bool loadingOlderHistory;
  final List<String> attachedWorkspaceFiles;
  final List<UploadedAttachment> stagedUploads;
  final String currentWorkspacePath;
  final List<WorkspaceEntry> workspaceFiles;
  final List<GitChange> workspaceChanges;
  final List<ArtifactSummary> workspaceArtifacts;
  final List<RelayEndpoint> relays;
  final List<ModelOption> availableModels;
  final List<ModeOption> availableModes;
  final List<SlashCommandInfo> availableCommands;
  final List<AuthorizedPeerInfo> authorizedPeers;

  const AppState({
    this.initialized = false,
    this.mobilePeerId = '',
    this.nodeError,
    this.isDarkTheme = true,
    this.showDemoHost = kDebugMode,
    this.navTabIndex = 1,
    this.activeHostId = kDebugMode ? 'demo-home-workstation' : '',
    this.activeSessionId = kDebugMode ? 'sess-nat-relay' : '',
    this.handoffBanner,
    this.handoffSuccess = false,
    this.isStreaming = false,
    this.lastEventSeq = 0,
    this.loadingSession = false,
    this.loadingWorkspace = false,
    this.contextUsedTokens = 0,
    this.contextMaxTokens = 0,
    this.loadedRealSessions = const {},
    this.preferMdns = true,
    this.enableDcutr = true,
    this.enableAutoRelay = true,
    this.enablePublicRelayFallback = false,
    this.enableForegroundService = true,
    this.notifPermissions = true,
    this.notifCompletion = true,
    this.keepAwake = false,
    this.isAppBackgrounded = false,
    this.probingRelays = false,
    this.hosts = const [],
    this.sessions = const [],
    this.messagesBySession = const {},
    this.historyNextCursor = const {},
    this.historyHasMore = const {},
    this.loadingOlderHistory = false,
    this.attachedWorkspaceFiles = const [],
    this.stagedUploads = const [],
    this.currentWorkspacePath = '.',
    this.workspaceFiles = const [],
    this.workspaceChanges = const [],
    this.workspaceArtifacts = const [],
    this.relays = const [],
    this.availableModels = const [],
    this.availableModes = const [],
    this.availableCommands = const [],
    this.authorizedPeers = const [],
  });

  PairedHost? get activeHost {
    for (final h in hosts) {
      if (h.id == activeHostId) return h;
    }
    return hosts.isNotEmpty ? hosts.first : null;
  }

  AgentSession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.isNotEmpty ? sessions.first : null;
  }

  List<ChatMessage> get activeMessages =>
      messagesBySession[activeSessionId] ?? const [];

  int get pendingApprovalCount {
    var count = 0;
    for (final list in messagesBySession.values) {
      for (final m in list) {
        if (m.kind == ChatMessageKind.permission &&
            m.permStatus == PermissionStatus.pending) {
          count++;
        }
      }
    }
    return count;
  }

  AppState copyWith({
    bool? initialized,
    String? mobilePeerId,
    String? nodeError,
    bool? isDarkTheme,
    bool? showDemoHost,
    int? navTabIndex,
    String? activeHostId,
    String? activeSessionId,
    String? handoffBanner,
    bool clearHandoffBanner = false,
    bool? handoffSuccess,
    bool? isStreaming,
    int? lastEventSeq,
    bool? loadingSession,
    bool? loadingWorkspace,
    int? contextUsedTokens,
    int? contextMaxTokens,
    Set<String>? loadedRealSessions,
    bool? preferMdns,
    bool? enableDcutr,
    bool? enableAutoRelay,
    bool? enablePublicRelayFallback,
    bool? enableForegroundService,
    bool? notifPermissions,
    bool? notifCompletion,
    bool? keepAwake,
    bool? isAppBackgrounded,
    bool? probingRelays,
    List<PairedHost>? hosts,
    List<AgentSession>? sessions,
    Map<String, List<ChatMessage>>? messagesBySession,
    Map<String, int>? historyNextCursor,
    Map<String, bool>? historyHasMore,
    bool? loadingOlderHistory,
    List<String>? attachedWorkspaceFiles,
    List<UploadedAttachment>? stagedUploads,
    String? currentWorkspacePath,
    List<WorkspaceEntry>? workspaceFiles,
    List<GitChange>? workspaceChanges,
    List<ArtifactSummary>? workspaceArtifacts,
    List<RelayEndpoint>? relays,
    List<ModelOption>? availableModels,
    List<ModeOption>? availableModes,
    List<SlashCommandInfo>? availableCommands,
    List<AuthorizedPeerInfo>? authorizedPeers,
  }) {
    return AppState(
      initialized: initialized ?? this.initialized,
      mobilePeerId: mobilePeerId ?? this.mobilePeerId,
      nodeError: nodeError,
      isDarkTheme: isDarkTheme ?? this.isDarkTheme,
      showDemoHost: showDemoHost ?? this.showDemoHost,
      navTabIndex: navTabIndex ?? this.navTabIndex,
      activeHostId: activeHostId ?? this.activeHostId,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      handoffBanner:
          clearHandoffBanner ? null : (handoffBanner ?? this.handoffBanner),
      handoffSuccess: handoffSuccess ?? this.handoffSuccess,
      isStreaming: isStreaming ?? this.isStreaming,
      lastEventSeq: lastEventSeq ?? this.lastEventSeq,
      loadingSession: loadingSession ?? this.loadingSession,
      loadingWorkspace: loadingWorkspace ?? this.loadingWorkspace,
      contextUsedTokens: contextUsedTokens ?? this.contextUsedTokens,
      contextMaxTokens: contextMaxTokens ?? this.contextMaxTokens,
      loadedRealSessions: loadedRealSessions ?? this.loadedRealSessions,
      preferMdns: preferMdns ?? this.preferMdns,
      enableDcutr: enableDcutr ?? this.enableDcutr,
      enableAutoRelay: enableAutoRelay ?? this.enableAutoRelay,
      enablePublicRelayFallback:
          enablePublicRelayFallback ?? this.enablePublicRelayFallback,
      enableForegroundService:
          enableForegroundService ?? this.enableForegroundService,
      notifPermissions: notifPermissions ?? this.notifPermissions,
      notifCompletion: notifCompletion ?? this.notifCompletion,
      keepAwake: keepAwake ?? this.keepAwake,
      isAppBackgrounded: isAppBackgrounded ?? this.isAppBackgrounded,
      probingRelays: probingRelays ?? this.probingRelays,
      hosts: hosts ?? this.hosts,
      sessions: sessions ?? this.sessions,
      messagesBySession: messagesBySession ?? this.messagesBySession,
      historyNextCursor: historyNextCursor ?? this.historyNextCursor,
      historyHasMore: historyHasMore ?? this.historyHasMore,
      loadingOlderHistory: loadingOlderHistory ?? this.loadingOlderHistory,
      attachedWorkspaceFiles:
          attachedWorkspaceFiles ?? this.attachedWorkspaceFiles,
      stagedUploads: stagedUploads ?? this.stagedUploads,
      currentWorkspacePath: currentWorkspacePath ?? this.currentWorkspacePath,
      workspaceFiles: workspaceFiles ?? this.workspaceFiles,
      workspaceChanges: workspaceChanges ?? this.workspaceChanges,
      workspaceArtifacts: workspaceArtifacts ?? this.workspaceArtifacts,
      relays: relays ?? this.relays,
      availableModels: availableModels ?? this.availableModels,
      availableModes: availableModes ?? this.availableModes,
      availableCommands: availableCommands ?? this.availableCommands,
      authorizedPeers: authorizedPeers ?? this.authorizedPeers,
    );
  }
}

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  final transport = ref.watch(p2pTransportProvider);
  final supportDir = ref.watch(supportDirProvider);
  final androidRuntime = ref.watch(androidRuntimeProvider);
  return AppController(
    transport,
    supportDirOverride: supportDir,
    androidRuntime: androidRuntime,
  );
});

class AppController extends StateNotifier<AppState> {
  static const _prefsHostsKey = 'agy_paired_hosts_v1';
  static const _prefsActiveHostKey = 'agy_active_host_v1';
  static const _prefsRelaysKey = 'agy_relays_v1';
  static const _prefsThemeKey = 'agy_dark_theme_v1';
  static const _prefsSettingsKey = 'agy_settings_v1';
  static const _prefsShowDemoKey = 'agy_show_demo_v1';

  final P2PTransport transport;
  final String? supportDirOverride;
  final AndroidRuntime androidRuntime;
  final Map<String, String> _pendingUserEchoes = {};
  final Map<String, DateTime> _thinkingStartTimes = {};
  final Set<String> _subscribedPeers = {};
  final Set<String> _cancelledUploadPaths = {};
  StreamSubscription<BridgeEvent>? _eventSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _bannerTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;

  AppController(
    this.transport, {
    this.supportDirOverride,
    AndroidRuntime? androidRuntime,
  })  : androidRuntime = androidRuntime ?? NoopAndroidRuntime(),
        super(_buildInitialState()) {
    unawaited(_init());
  }

  static AppState _buildInitialState() {
    if (!kDebugMode) {
      return const AppState(
        showDemoHost: false,
        activeHostId: '',
        activeSessionId: '',
        hosts: [],
        sessions: [],
        messagesBySession: {},
        workspaceChanges: [],
        workspaceFiles: [],
        workspaceArtifacts: [],
        relays: [],
      );
    }
    const demoHostId = 'demo-home-workstation';
    const demoHost = PairedHost(
      id: demoHostId,
      peerId: '12D3KooWDemoHomeWorkstation7xQp9Lm2NrT5vKc8Wz4',
      name: 'home-workstation',
      os: 'Ubuntu 24.04 · arm64',
      agyVersion: 'agy v1.5.13',
      workspaceRoots: ['~/dev/antigravity-mobile'],
      cpuPercent: 34,
      ramPercent: 58,
      runningCount: 1,
      isDemo: true,
      diagnostics: ConnDiagnostics(
        peerId: '12D3KooWDemoHomeWorkstation7xQp9Lm2NrT5vKc8Wz4',
        connected: true,
        pathType: 'relay',
        transport: 'Circuit Relay v2 · QUIC + Noise',
        remoteAddr:
            '/dns4/sg-relay-1.myhome.dev/udp/4001/quic-v1/p2p/12D3KooWRelaySg1/p2p-circuit',
        relayPeerId: '12D3KooWRelaySg1',
        rttMs: 64,
        isRelayed: true,
      ),
    );

    const demoSessions = [
      AgentSession(
        id: 'sess-nat-relay',
        hostId: demoHostId,
        title: 'libp2p NAT Traversal & Relay',
        cwd: '~/dev/antigravity-mobile',
        branch: 'main',
        diffs: 3,
        model: 'Neon High',
        mode: 'Auto',
        status: 'approval',
        updatedAt: 'Just now',
      ),
      AgentSession(
        id: 'sess-ffi-decoder',
        hostId: demoHostId,
        title: 'Flutter FFI Stream Decoder',
        cwd: '~/dev/antigravity-mobile',
        branch: 'feat/ffi-bridge',
        diffs: 1,
        model: 'Orch Neon',
        mode: 'Plan',
        status: 'active',
        updatedAt: '18m ago',
      ),
    ];

    final demoMessages = <String, List<ChatMessage>>{
      'sess-nat-relay': const [
        ChatMessage(
          id: 'm1',
          kind: ChatMessageKind.user,
          text:
              'Configure Circuit Relay v2 fallback when both peers are behind symmetric NAT, and verify the dialer tests pass.',
          chips: ['@pkg/p2p/host.go'],
        ),
        ChatMessage(
          id: 'm2',
          kind: ChatMessageKind.thinking,
          duration: '5.2s · 3 steps',
          thinkingSteps: [
            'Inspected go-libp2p Circuit Relay v2 client behavior under dual symmetric NAT.',
            'Confirmed relayed connections carry the Limited flag; streams require network.WithAllowLimitedConn.',
            'Prepared edit to pkg/p2p/dialer.go and race test verification.',
          ],
        ),
        ChatMessage(
          id: 'm3',
          kind: ChatMessageKind.plan,
          planCurrent: 2,
          planTotal: 4,
          text: 'Circuit Relay v2 dialer & stream upgrade',
        ),
        ChatMessage(
          id: 'm4',
          kind: ChatMessageKind.toolRead,
          filePath: 'pkg/p2p/host.go',
          detail: '142 lines',
        ),
        ChatMessage(
          id: 'm5',
          kind: ChatMessageKind.toolEdit,
          filePath: 'pkg/p2p/dialer.go',
          additions: 18,
          deletions: 4,
          diffLines: [
            '  // Allow streams over Circuit Relay v2',
            '- s, err := h.NewStream(ctx, p, ProtocolRPC)',
            '+ streamCtx := network.WithAllowLimitedConn(ctx, ProtocolRPC)',
            '+ s, err := h.NewStream(streamCtx, p, ProtocolRPC)',
          ],
        ),
        ChatMessage(
          id: 'm6',
          kind: ChatMessageKind.assistant,
          text:
              'I updated `OpenStream` so relayed connections pass `network.WithAllowLimitedConn(ctx, protoID)`. Without that flag, `go-libp2p` rejects streams with `ErrLimitedConn` whenever DCUtR cannot punch through symmetric NATs.',
          codeTitle: 'pkg/p2p/dialer.go',
          code:
              'func OpenStream(ctx context.Context, h host.Host, target peer.ID, protoID string) (network.Stream, error) {\n'
              '    streamCtx := network.WithAllowLimitedConn(ctx, protoID)\n'
              '    return h.NewStream(streamCtx, target, libp2pproto.ID(protoID))\n'
              '}',
        ),
        ChatMessage(
          id: 'm7',
          kind: ChatMessageKind.permission,
          permId: 'demo-perm-1',
          command: 'go test ./pkg/p2p/... -v -race',
          cwd: '~/dev/antigravity-mobile',
          sandbox: 'Off',
          permStatus: PermissionStatus.pending,
        ),
      ],
    };

    const demoChanges = [
      GitChange(
        path: 'pkg/p2p/dialer.go',
        status: 'M',
        additions: 18,
        deletions: 4,
        summary: 'Pass network.WithAllowLimitedConn for relayed streams',
        diffLines: [
          '@@ -18,5 +18,8 @@ func OpenStream(ctx context.Context, h host.Host, target peer.ID, protoID string) (network.Stream, error) {',
          '- return h.NewStream(ctx, target, libp2pproto.ID(protoID))',
          '+ streamCtx := network.WithAllowLimitedConn(ctx, protoID)',
          '+ return h.NewStream(streamCtx, target, libp2pproto.ID(protoID))',
          ' }',
        ],
      ),
      GitChange(
        path: 'pkg/workspace/uploads.go',
        status: 'A',
        additions: 184,
        deletions: 0,
        summary: 'Stage mobile file uploads in isolated /tmp/agyd-uploads/',
        diffLines: [
          '@@ -0,0 +1,5 @@',
          '+// UploadManager stages mobile-uploaded files into an isolated /tmp directory per session.',
          '+func (u *UploadManager) SaveStream(...) (*protocol.BlobUploadResult, error)',
        ],
      ),
    ];

    const demoFiles = [
      WorkspaceEntry(name: 'pkg/p2p/host.go', path: 'pkg/p2p/host.go', isDir: false, size: 5120),
      WorkspaceEntry(name: 'pkg/p2p/dialer.go', path: 'pkg/p2p/dialer.go', isDir: false, size: 4210),
      WorkspaceEntry(name: 'pkg/acp/bridge.go', path: 'pkg/acp/bridge.go', isDir: false, size: 9640),
      WorkspaceEntry(name: 'pkg/workspace/uploads.go', path: 'pkg/workspace/uploads.go', isDir: false, size: 5900),
    ];

    const demoArtifacts = [
      ArtifactSummary(
        name: 'DESIGN_PLAN.md',
        sessionId: 'sess-nat-relay',
        size: 23400,
        updatedAt: 'Just now',
        previewContent:
            '# Antigravity Mobile Architecture\n\n• Go daemon (agyd) + self-hosted agy-relay\n• Flutter Android arm64 client using go-libp2p via Dart FFI\n• Mobile /tmp upload staging via /agy/blob/1.0.0',
      ),
    ];

    const defaultRelays = <RelayEndpoint>[];

    return AppState(
      hosts: const [demoHost],
      sessions: demoSessions,
      messagesBySession: demoMessages,
      workspaceChanges: demoChanges,
      workspaceFiles: demoFiles,
      workspaceArtifacts: demoArtifacts,
      relays: defaultRelays,
    );
  }

  Future<void> _init() async {
    SharedPreferences? prefs;
    var loadedHosts = <PairedHost>[];
    var loadedRelays = state.relays;
    var darkTheme = true;
    var preferMdns = state.preferMdns;
    var enableDcutr = state.enableDcutr;
    var enableAutoRelay = state.enableAutoRelay;
    var enablePublicRelayFallback = state.enablePublicRelayFallback;
    var enableForegroundService = state.enableForegroundService;
    var notifPermissions = state.notifPermissions;
    var notifCompletion = state.notifCompletion;
    var keepAwake = state.keepAwake;
    var savedActiveHostId = '';

    try {
      prefs = await SharedPreferences.getInstance();
      darkTheme = prefs.getBool(_prefsThemeKey) ?? true;
      savedActiveHostId = prefs.getString(_prefsActiveHostKey) ?? '';
      final settingsRaw = prefs.getString(_prefsSettingsKey);
      if (settingsRaw != null && settingsRaw.isNotEmpty) {
        final s = jsonDecode(settingsRaw);
        if (s is Map<String, dynamic>) {
          preferMdns = s['preferMdns'] as bool? ?? preferMdns;
          enableDcutr = s['enableDcutr'] as bool? ?? enableDcutr;
          enableAutoRelay = s['enableAutoRelay'] as bool? ?? enableAutoRelay;
          enablePublicRelayFallback =
              s['enablePublicRelayFallback'] as bool? ?? enablePublicRelayFallback;
          enableForegroundService =
              s['enableForegroundService'] as bool? ?? enableForegroundService;
          notifPermissions = s['notifPermissions'] as bool? ?? notifPermissions;
          notifCompletion = s['notifCompletion'] as bool? ?? notifCompletion;
          keepAwake = s['keepAwake'] as bool? ?? keepAwake;
        }
      }
      final hostsRaw = prefs.getString(_prefsHostsKey);
      if (hostsRaw != null && hostsRaw.isNotEmpty) {
        final decoded = jsonDecode(hostsRaw) as List;
        loadedHosts = decoded
            .whereType<Map<String, dynamic>>()
            .map(PairedHost.fromJson)
            .toList();
      }
      final relaysRaw = prefs.getString(_prefsRelaysKey);
      if (relaysRaw != null && relaysRaw.isNotEmpty) {
        final decoded = jsonDecode(relaysRaw) as List;
        loadedRelays = decoded
            .whereType<Map<String, dynamic>>()
            .map(RelayEndpoint.fromJson)
            .toList();
      }
    } catch (_) {}

    final showDemo = kDebugMode && (prefs?.getBool(_prefsShowDemoKey) ?? true);
    final mergedHosts = <PairedHost>[
      ...loadedHosts,
      if (showDemo) ...state.hosts.where((h) => h.isDemo),
    ];

    var identityPath = '';
    if (supportDirOverride != null && supportDirOverride!.isNotEmpty) {
      identityPath = '$supportDirOverride/identity.key';
    } else {
      try {
        final dir = await getApplicationSupportDirectory();
        identityPath = '${dir.path}/identity.key';
      } catch (_) {
        identityPath = '${Directory.systemTemp.path}/agy_mobile_identity.key';
      }
    }

    _eventSub = transport.events.listen(_onBridgeEvent);

    try {
      final node = await transport.startNode(
        identityPath: identityPath,
        staticRelays: loadedRelays.map((r) => r.multiaddr).toList(),
        enableMdns: preferMdns,
        forcePrivate: false,
        enableHolePunching: enableDcutr,
      );
      debugPrint('[agyp2p] Node started PeerID=${node.peerId}');
      final resolvedActiveHostId =
          savedActiveHostId.isNotEmpty && mergedHosts.any((h) => h.id == savedActiveHostId)
              ? savedActiveHostId
              : (mergedHosts.isNotEmpty ? mergedHosts.first.id : state.activeHostId);
      state = state.copyWith(
        initialized: true,
        mobilePeerId: node.peerId,
        isDarkTheme: darkTheme,
        preferMdns: preferMdns,
        enableDcutr: enableDcutr,
        enableAutoRelay: enableAutoRelay,
        enablePublicRelayFallback: enablePublicRelayFallback,
        enableForegroundService: enableForegroundService,
        notifPermissions: notifPermissions,
        notifCompletion: notifCompletion,
        keepAwake: keepAwake,
        hosts: mergedHosts,
        activeHostId: resolvedActiveHostId,
        relays: loadedRelays,
      );
      final initialHost = state.activeHost;
      if (initialHost != null && !initialHost.isDemo) {
        unawaited(selectHost(initialHost.id));
      }
    } catch (e) {
      debugPrint('[agyp2p] Node start error: $e');
      state = state.copyWith(
        initialized: true,
        nodeError: e.toString(),
        isDarkTheme: darkTheme,
        preferMdns: preferMdns,
        enableDcutr: enableDcutr,
        enableAutoRelay: enableAutoRelay,
        enablePublicRelayFallback: enablePublicRelayFallback,
        enableForegroundService: enableForegroundService,
        notifPermissions: notifPermissions,
        notifCompletion: notifCompletion,
        keepAwake: keepAwake,
        hosts: mergedHosts,
        relays: loadedRelays,
      );
    }

    if (supportDirOverride == null) {
      try {
        _connSub = Connectivity().onConnectivityChanged.listen((_) {
          unawaited(_handleConnectivityChange());
        });
      } catch (_) {}
    }
  }

  void _setTransientBanner(
    String msg, {
    required bool success,
    Duration duration = const Duration(seconds: 3),
  }) {
    _bannerTimer?.cancel();
    state = state.copyWith(handoffBanner: msg, handoffSuccess: success);
    _bannerTimer = Timer(duration, () {
      if (mounted) state = state.copyWith(clearHandoffBanner: true);
    });
  }

  void _syncAndroidRuntime() {
    final host = state.activeHost;
    final shouldKeepAwake = state.isStreaming && state.keepAwake;
    unawaited(androidRuntime.setKeepScreenOn(shouldKeepAwake));
    if (host != null &&
        !host.isDemo &&
        host.diagnostics.connected &&
        state.enableForegroundService) {
      unawaited(androidRuntime.startForegroundService(
        title: 'Antigravity · ${host.name}',
        body: '${host.diagnostics.pillLabel} · ${state.isStreaming ? "Streaming response" : "Connected"}',
        holdWakeLock: shouldKeepAwake,
      ));
    } else {
      unawaited(androidRuntime.stopForegroundService());
    }
  }

  void onAppLifecycleChanged(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      if (!state.isAppBackgrounded) {
        state = state.copyWith(isAppBackgrounded: true);
      }
    } else if (lifecycle == AppLifecycleState.resumed) {
      final wasBackgrounded = state.isAppBackgrounded;
      if (wasBackgrounded) {
        state = state.copyWith(isAppBackgrounded: false);
        unawaited(_reconnectActiveHost(reason: 'App resumed'));
      }
    }
  }

  Future<void> _reconnectActiveHost({required String reason}) async {
    final host = state.activeHost;
    if (host == null || host.isDemo || _reconnecting) return;
    _reconnecting = true;
    try {
      await transport.notifyNetworkChanged();
      final diag = await transport.connectHost(
        peerId: host.peerId,
        directAddrs: host.directAddrs,
        relayAddrs: host.relayAddrs,
      );
      if (!mounted) return;
      _updateHostDiagnostics(host.id, diag);
      await _ensureEventSubscription(host.peerId, force: true);
      if (!mounted) return;
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _syncAndroidRuntime();
      _setTransientBanner('$reason · ${diag.pillLabel} synced', success: true);
    } catch (_) {
      if (mounted) _syncAndroidRuntime();
    } finally {
      _reconnecting = false;
    }
  }

  void _scheduleEventReconnect() {
    const delaysSec = [1, 2, 4, 8];
    if (_reconnectAttempts >= delaysSec.length) return;
    final delaySec = delaysSec[_reconnectAttempts];
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!mounted) return;
      _reconnectAttempts++;
      unawaited(_runScheduledReconnect());
    });
  }

  Future<void> _runScheduledReconnect() async {
    final host = state.activeHost;
    if (host == null || host.isDemo || _reconnecting) return;
    _reconnecting = true;
    var succeeded = false;
    try {
      await transport.notifyNetworkChanged();
      final diag = await transport.connectHost(
        peerId: host.peerId,
        directAddrs: host.directAddrs,
        relayAddrs: host.relayAddrs,
      );
      if (!mounted) return;
      _updateHostDiagnostics(host.id, diag);
      await _ensureEventSubscription(host.peerId, force: true);
      if (!mounted) return;
      succeeded = diag.connected;
      if (succeeded) {
        _reconnectAttempts = 0;
        _setTransientBanner('Stream recovered · ${diag.pillLabel}', success: true);
      }
      _syncAndroidRuntime();
    } catch (_) {
      succeeded = false;
    } finally {
      _reconnecting = false;
    }
    if (!succeeded && mounted) {
      _scheduleEventReconnect();
    }
  }

  Future<void> _handleConnectivityChange() async {
    final host = state.activeHost;
    if (host != null && !host.isDemo && host.diagnostics.connected) {
      state = state.copyWith(
        handoffBanner: 'Network changed · Reconnecting libp2p...',
        handoffSuccess: false,
      );
      await _reconnectActiveHost(reason: 'Connected via network handoff');
    } else {
      try {
        await transport.notifyNetworkChanged();
      } catch (_) {}
    }
  }

  Future<void> _ensureEventSubscription(String peerId, {bool force = false, int? sinceSeq}) async {
    if (!force && _subscribedPeers.contains(peerId)) return;
    await transport.subscribeEvents(peerId, sinceSeq ?? state.lastEventSeq);
    _subscribedPeers.add(peerId);
  }

  void _onBridgeEvent(BridgeEvent ev) {
    if (ev.type == 'events_disconnected') {
      final evPeerId = (ev.raw['peerId'] ?? '').toString();
      if (evPeerId.isNotEmpty) {
        _subscribedPeers.remove(evPeerId);
      }
      final host = state.activeHost;
      if (host != null &&
          !host.isDemo &&
          (evPeerId.isEmpty || evPeerId == host.peerId)) {
        _scheduleEventReconnect();
      }
      return;
    }

    if (ev.type == 'upload_progress') {
      final fname = (ev.raw['filename'] ?? '').toString();
      final sent = (ev.raw['sentBytes'] as num?)?.toDouble() ?? 0;
      final total = (ev.raw['totalBytes'] as num?)?.toDouble() ?? 1;
      final ratio = total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0;
      state = state.copyWith(
        stagedUploads: state.stagedUploads.map((u) {
          if (u.uploading && u.filename == fname) {
            return u.copyWith(progress: ratio);
          }
          return u;
        }).toList(),
      );
      return;
    }

    if (ev.type == 'acp_event') {
      final inner = ev.raw['event'] as Map<String, dynamic>? ?? const {};
      final seq = (inner['seq'] as num?)?.toInt() ?? 0;
      final sid = (inner['sessionId'] ?? '').toString();
      final kind = (inner['kind'] ?? '').toString();
      final payload = inner['payload'];

      if (seq > state.lastEventSeq) {
        state = state.copyWith(lastEventSeq: seq);
      }
      final targetSid = sid.isNotEmpty ? sid : state.activeSessionId;

      if (kind == 'session_update' && payload is Map<String, dynamic>) {
        final upd = payload['update'] as Map<String, dynamic>? ?? const {};
        _handleSessionUpdate(targetSid, upd);
      } else if (kind == 'permission_request' && payload is Map<String, dynamic>) {
        _finalizeStreaming(targetSid);
        final permId = (payload['permId'] ?? '').toString();
        final toolCall = payload['toolCall'] as Map<String, dynamic>? ?? const {};
        final rawInput = toolCall['rawInput'] as Map<String, dynamic>? ?? const {};
        final title = (rawInput['CommandLine'] ?? toolCall['title'] ?? 'Tool permission').toString();
        final optsRaw = payload['options'] as List? ?? const [];
        final opts = optsRaw
            .whereType<Map<String, dynamic>>()
            .map((o) => {
                  'optionId': (o['optionId'] ?? '').toString(),
                  'name': (o['name'] ?? '').toString(),
                  'kind': (o['kind'] ?? '').toString(),
                })
            .toList();
        final exists = (state.messagesBySession[targetSid] ?? const [])
            .any((m) => m.permId == permId && permId.isNotEmpty);
        if (!exists) {
          _appendMessage(
            targetSid,
            ChatMessage(
              id: 'perm-$permId',
              kind: ChatMessageKind.permission,
              permId: permId,
              command: title,
              cwd: state.activeSession?.cwd ?? '~',
              permOptions: opts,
            ),
          );
          if (state.isAppBackgrounded && state.notifPermissions) {
            unawaited(androidRuntime.showAlertNotification(
              id: 2000 + (permId.hashCode.abs() % 900),
              title: 'Approval Needed · ${state.activeHost?.name ?? 'Antigravity'}',
              body: title,
            ));
          }
        }
      } else if (kind == 'permission_resolved' && payload is Map<String, dynamic>) {
        final permId = (payload['permId'] ?? '').toString();
        final optionId = (payload['optionId'] ?? '').toString();
        final cancelled = payload['cancelled'] == true;
        final status = cancelled
            ? PermissionStatus.denied
            : (optionId.contains('always')
                ? PermissionStatus.allowedAlways
                : PermissionStatus.allowedOnce);
        final updated = (state.messagesBySession[targetSid] ?? const []).map((m) {
          if (m.permId == permId && m.permStatus == PermissionStatus.pending) {
            return m.copyWith(permStatus: status);
          }
          return m;
        }).toList();
        state = state.copyWith(
          messagesBySession: {...state.messagesBySession, targetSid: updated},
        );
      } else if (kind == 'turn_complete' || kind == 'turn_error') {
        _finalizeStreaming(targetSid);
        if (kind == 'turn_error' && payload is Map<String, dynamic>) {
          final errMsg = (payload['error'] ?? 'Turn error').toString();
          _appendMessage(
            targetSid,
            ChatMessage(
              id: 'err-${DateTime.now().microsecondsSinceEpoch}',
              kind: ChatMessageKind.assistant,
              text: 'Agent turn error: $errMsg',
            ),
          );
        }
        state = state.copyWith(isStreaming: false);
        _syncAndroidRuntime();
        if (state.isAppBackgrounded && state.notifCompletion) {
          unawaited(androidRuntime.showAlertNotification(
            id: 3001,
            title: kind == 'turn_error' ? 'Agent Turn Error' : 'Agent Turn Complete',
            body: state.activeSession?.title ?? 'Session update ready',
          ));
        }
        if (targetSid == state.activeSessionId) {
          unawaited(refreshWorkspaceData());
        }
      }
    }
  }

  void _handleSessionUpdate(String targetSid, Map<String, dynamic> upd) {
    final updType = (upd['sessionUpdate'] ?? '').toString();
    switch (updType) {
      case 'user_message_chunk':
        final content = upd['content'] as Map<String, dynamic>? ?? const {};
        final chunk = (content['text'] ?? '').toString();
        if (chunk.isNotEmpty) {
          _appendUserChunk(targetSid, chunk);
        }
      case 'agent_thought_chunk':
        final content = upd['content'] as Map<String, dynamic>? ?? const {};
        final chunk = (content['text'] ?? '').toString();
        if (chunk.isNotEmpty) {
          _appendThoughtChunk(targetSid, chunk);
        }
      case 'agent_message_chunk':
        final content = upd['content'] as Map<String, dynamic>? ?? const {};
        final chunk = (content['text'] ?? '').toString();
        if (chunk.isNotEmpty) {
          _appendAssistantChunk(targetSid, chunk);
        }
      case 'tool_call':
      case 'tool_call_update':
        _finalizeStreaming(targetSid);
        _upsertToolCall(targetSid, upd);
      case 'plan':
        _upsertPlan(targetSid, upd);
      case 'available_commands_update':
        final raw = upd['availableCommands'] as List? ?? const [];
        final cmds = raw
            .whereType<Map<String, dynamic>>()
            .map(SlashCommandInfo.fromJson)
            .where((c) => c.name.isNotEmpty)
            .toList();
        if (cmds.isNotEmpty) {
          state = state.copyWith(availableCommands: cmds);
        }
      case 'session_info_update':
        final title = (upd['title'] ?? '').toString();
        if (title.isNotEmpty) {
          state = state.copyWith(
            sessions: state.sessions
                .map((s) => s.id == targetSid ? s.copyWith(title: title) : s)
                .toList(),
          );
        }
      case 'usage_update':
        final used = (upd['used'] as num?)?.toInt() ?? state.contextUsedTokens;
        final size = (upd['size'] as num?)?.toInt() ?? state.contextMaxTokens;
        state = state.copyWith(contextUsedTokens: used, contextMaxTokens: size);
      case 'current_mode_update':
        final modeId = (upd['currentModeId'] ?? '').toString();
        if (modeId.isNotEmpty) {
          state = state.copyWith(
            sessions: state.sessions
                .map((s) => s.id == targetSid ? s.copyWith(mode: modeId) : s)
                .toList(),
          );
        }
    }
  }

  String _formatElapsedThinking(String msgId) {
    final started = _thinkingStartTimes.remove(msgId);
    if (started == null) return '';
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (ms < 200) {
      return '';
    }
    if (ms < 10000) {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
    return '${(ms / 1000).round()}s';
  }

  void _finalizeStreaming(String sessionId) {
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    var changed = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].streaming) {
        String? nextDuration;
        if (current[i].kind == ChatMessageKind.thinking && current[i].duration.isEmpty) {
          nextDuration = _formatElapsedThinking(current[i].id);
        }
        current[i] = current[i].copyWith(
          streaming: false,
          duration: nextDuration,
        );
        changed = true;
      }
    }
    if (changed) {
      state = state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: current},
      );
    }
  }

  void _appendUserChunk(String sessionId, String chunk) {
    final pending = _pendingUserEchoes[sessionId];
    if (pending != null) {
      if (pending == chunk.trim() || pending.startsWith(chunk.trim())) {
        _pendingUserEchoes.remove(sessionId);
        return;
      }
    }
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    if (current.isNotEmpty && current.last.kind == ChatMessageKind.user && current.last.streaming) {
      current[current.length - 1] = current.last.copyWith(text: current.last.text + chunk);
    } else {
      _finalizeStreaming(sessionId);
      final afterFinalize = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
      afterFinalize.add(ChatMessage(
        id: 'usr-${DateTime.now().microsecondsSinceEpoch}',
        kind: ChatMessageKind.user,
        text: chunk,
        streaming: true,
      ));
      state = state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: afterFinalize},
      );
      return;
    }
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  void _appendThoughtChunk(String sessionId, String chunk) {
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    if (current.isNotEmpty && current.last.kind == ChatMessageKind.thinking && current.last.streaming) {
      current[current.length - 1] = current.last.copyWith(text: current.last.text + chunk);
    } else {
      _finalizeStreaming(sessionId);
      final afterFinalize = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
      final msgId = 'th-${DateTime.now().microsecondsSinceEpoch}';
      if (!state.loadingSession) {
        _thinkingStartTimes[msgId] = DateTime.now();
      }
      afterFinalize.add(ChatMessage(
        id: msgId,
        kind: ChatMessageKind.thinking,
        text: chunk,
        duration: '',
        streaming: true,
      ));
      state = state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: afterFinalize},
      );
      return;
    }
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  void _appendAssistantChunk(String sessionId, String chunk) {
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    if (current.isNotEmpty && current.last.kind == ChatMessageKind.assistant && current.last.streaming) {
      current[current.length - 1] = current.last.copyWith(text: current.last.text + chunk);
    } else {
      _finalizeStreaming(sessionId);
      final afterFinalize = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
      afterFinalize.add(ChatMessage(
        id: 'asst-${DateTime.now().microsecondsSinceEpoch}',
        kind: ChatMessageKind.assistant,
        text: chunk,
        streaming: true,
      ));
      state = state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: afterFinalize},
      );
      return;
    }
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  ChatMessage _buildToolCallMessage(Map<String, dynamic> upd, {String? existingId}) {
    final toolCallId = (upd['toolCallId'] ?? '').toString();
    final name = (upd['name'] ?? '').toString();
    final toolKind = (upd['kind'] ?? 'other').toString();
    final status = (upd['status'] ?? 'completed').toString();
    final title = (upd['title'] ?? '').toString();
    final rawInput = upd['rawInput'] as Map<String, dynamic>? ?? const {};
    final rawOutput = upd['rawOutput'] as Map<String, dynamic>? ?? const {};
    final locations = upd['locations'] as List? ?? const [];
    final contentList = upd['content'] as List? ?? const [];

    String firstPath = '';
    if (locations.isNotEmpty && locations.first is Map<String, dynamic>) {
      firstPath = ((locations.first as Map<String, dynamic>)['path'] ?? '').toString();
    }
    if (firstPath.isEmpty) {
      firstPath = (rawInput['Path'] ?? rawInput['path'] ?? '').toString();
    }

    final msgId = existingId ?? 'tc-${DateTime.now().microsecondsSinceEpoch}';
    if (toolKind == 'execute' || name == 'run_command') {
      final cmd = (rawInput['CommandLine'] ?? (title.isNotEmpty ? title : name)).toString();
      var output = (rawOutput['output'] ?? '').toString();
      if (output.isEmpty) {
        output = _extractContentText(contentList);
      }
      final exitCode = rawOutput['exit_code'];
      final exitLabel = exitCode != null ? 'exit $exitCode' : status;
      return ChatMessage(
        id: msgId,
        kind: ChatMessageKind.terminal,
        toolCallId: toolCallId,
        toolStatus: status,
        command: cmd,
        detail: exitLabel,
        text: output,
      );
    } else if (toolKind == 'edit') {
      final diffData = _extractDiffLines(contentList);
      final targetPath = firstPath.isNotEmpty ? firstPath : (title.isNotEmpty ? title : name);
      return ChatMessage(
        id: msgId,
        kind: ChatMessageKind.toolEdit,
        toolCallId: toolCallId,
        toolStatus: status,
        filePath: targetPath,
        additions: diffData.$2,
        deletions: diffData.$3,
        diffLines: diffData.$1,
      );
    } else {
      final displayTitle = title.isNotEmpty ? title : (firstPath.isNotEmpty ? firstPath : name);
      return ChatMessage(
        id: msgId,
        kind: ChatMessageKind.toolRead,
        toolCallId: toolCallId,
        toolStatus: status,
        filePath: displayTitle,
        detail: status,
      );
    }
  }

  void _upsertToolCall(String sessionId, Map<String, dynamic> upd) {
    final toolCallId = (upd['toolCallId'] ?? '').toString();
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    final existingIdx = toolCallId.isNotEmpty
        ? current.indexWhere((m) => m.toolCallId == toolCallId)
        : -1;

    final built = _buildToolCallMessage(
      upd,
      existingId: existingIdx >= 0 ? current[existingIdx].id : null,
    );

    if (existingIdx >= 0) {
      current[existingIdx] = built;
    } else {
      current.add(built);
    }
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  List<ChatMessage> _parseHistoryItems(String sessionId, List<dynamic> rawItems, {int idOffset = 0}) {
    final out = <ChatMessage>[];
    var seq = idOffset;
    for (final item in rawItems.whereType<Map<String, dynamic>>()) {
      seq++;
      final updType = (item['sessionUpdate'] ?? '').toString();
      switch (updType) {
        case 'user_message_chunk':
          final content = item['content'] as Map<String, dynamic>? ?? const {};
          final txt = (content['text'] ?? '').toString();
          if (txt.isNotEmpty) {
            out.add(ChatMessage(
              id: 'hist-usr-$sessionId-$seq',
              kind: ChatMessageKind.user,
              text: txt,
            ));
          }
        case 'agent_thought_chunk':
          final content = item['content'] as Map<String, dynamic>? ?? const {};
          final txt = (content['text'] ?? '').toString();
          if (txt.isNotEmpty) {
            out.add(ChatMessage(
              id: 'hist-th-$sessionId-$seq',
              kind: ChatMessageKind.thinking,
              text: txt,
            ));
          }
        case 'agent_message_chunk':
          final content = item['content'] as Map<String, dynamic>? ?? const {};
          final txt = (content['text'] ?? '').toString();
          if (txt.isNotEmpty) {
            out.add(ChatMessage(
              id: 'hist-asst-$sessionId-$seq',
              kind: ChatMessageKind.assistant,
              text: txt,
            ));
          }
        case 'tool_call':
        case 'tool_call_update':
          out.add(_buildToolCallMessage(item, existingId: 'hist-tc-$sessionId-$seq'));
        case 'plan':
          final entries = item['entries'] as List? ?? const [];
          if (entries.isNotEmpty) {
            var done = 0;
            var activeText = '';
            for (final e in entries.whereType<Map<String, dynamic>>()) {
              final st = (e['status'] ?? '').toString();
              if (st == 'completed') done++;
              if (activeText.isEmpty && (st == 'in_progress' || st == 'pending')) {
                activeText = (e['content'] ?? '').toString();
              }
            }
            if (activeText.isEmpty && entries.last is Map<String, dynamic>) {
              activeText = ((entries.last as Map<String, dynamic>)['content'] ?? 'Plan').toString();
            }
            out.add(ChatMessage(
              id: 'hist-plan-$sessionId-$seq',
              kind: ChatMessageKind.plan,
              text: activeText,
              planCurrent: done,
              planTotal: entries.length,
            ));
          }
      }
    }
    return out;
  }

  void _upsertPlan(String sessionId, Map<String, dynamic> upd) {
    final entries = upd['entries'] as List? ?? const [];
    if (entries.isEmpty) return;
    var done = 0;
    var activeText = '';
    for (final item in entries.whereType<Map<String, dynamic>>()) {
      final st = (item['status'] ?? '').toString();
      if (st == 'completed') done++;
      if (activeText.isEmpty && (st == 'in_progress' || st == 'pending')) {
        activeText = (item['content'] ?? '').toString();
      }
    }
    if (activeText.isEmpty && entries.last is Map<String, dynamic>) {
      activeText = ((entries.last as Map<String, dynamic>)['content'] ?? 'Plan').toString();
    }

    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    final planId = 'plan-$sessionId';
    final idx = current.indexWhere((m) => m.id == planId);
    final msg = ChatMessage(
      id: planId,
      kind: ChatMessageKind.plan,
      planCurrent: done,
      planTotal: entries.length,
      text: activeText,
    );
    if (idx >= 0) {
      current[idx] = msg;
    } else {
      current.add(msg);
    }
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  String _extractContentText(List<dynamic> contentList) {
    final parts = <String>[];
    for (final item in contentList.whereType<Map<String, dynamic>>()) {
      final inner = item['content'];
      if (inner is Map<String, dynamic> && inner['text'] != null) {
        parts.add(inner['text'].toString());
      } else if (item['text'] != null) {
        parts.add(item['text'].toString());
      }
    }
    return parts.join('\n');
  }

  (List<String>, int, int) _extractDiffLines(List<dynamic> contentList) {
    final lines = <String>[];
    var adds = 0;
    var dels = 0;
    for (final item in contentList.whereType<Map<String, dynamic>>()) {
      if (item['type'] == 'diff') {
        final oldText = (item['oldText'] ?? '').toString();
        final newText = (item['newText'] ?? '').toString();
        if (oldText.isNotEmpty) {
          for (final l in oldText.split('\n').take(12)) {
            lines.add('- $l');
            dels++;
          }
        }
        if (newText.isNotEmpty) {
          for (final l in newText.split('\n').take(12)) {
            lines.add('+ $l');
            adds++;
          }
        }
      }
    }
    return (lines, adds, dels);
  }

  void _appendMessage(String sessionId, ChatMessage msg) {
    final current = List<ChatMessage>.from(state.messagesBySession[sessionId] ?? const []);
    current.add(msg);
    state = state.copyWith(
      messagesBySession: {...state.messagesBySession, sessionId: current},
    );
  }

  void setNavTab(int index) {
    state = state.copyWith(navTabIndex: index);
    if (index == 2) {
      unawaited(refreshWorkspaceData());
    } else if (index == 3) {
      unawaited(refreshAuthorizedPeers());
    }
  }

  Future<void> toggleTheme() async {
    final next = !state.isDarkTheme;
    state = state.copyWith(isDarkTheme: next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsThemeKey, next);
    } catch (_) {}
  }

  Future<bool> requestNotificationPermission() {
    return androidRuntime.requestNotificationPermission();
  }

  Future<bool> sendTestNotification() async {
    final granted = await requestNotificationPermission();
    await androidRuntime.showAlertNotification(
      id: 3999,
      title: 'Antigravity Test Alert',
      body: 'Background alerts are active for ${state.activeHost?.name ?? 'Antigravity'}.',
    );
    return granted;
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsSettingsKey,
        jsonEncode({
          'preferMdns': state.preferMdns,
          'enableDcutr': state.enableDcutr,
          'enableAutoRelay': state.enableAutoRelay,
          'enablePublicRelayFallback': state.enablePublicRelayFallback,
          'enableForegroundService': state.enableForegroundService,
          'notifPermissions': state.notifPermissions,
          'notifCompletion': state.notifCompletion,
          'keepAwake': state.keepAwake,
        }),
      );
    } catch (_) {}
  }

  void setPreference({
    bool? preferMdns,
    bool? enableDcutr,
    bool? enableAutoRelay,
    bool? enablePublicRelayFallback,
    bool? enableForegroundService,
    bool? notifPermissions,
    bool? notifCompletion,
    bool? keepAwake,
  }) {
    state = state.copyWith(
      preferMdns: preferMdns,
      enableDcutr: enableDcutr,
      enableAutoRelay: enableAutoRelay,
      enablePublicRelayFallback: enablePublicRelayFallback,
      enableForegroundService: enableForegroundService,
      notifPermissions: notifPermissions,
      notifCompletion: notifCompletion,
      keepAwake: keepAwake,
    );
    unawaited(_saveSettings());
    _syncAndroidRuntime();
  }

  Future<void> addRelay(String multiaddr) async {
    final trimmed = multiaddr.trim();
    if (trimmed.isEmpty) return;
    final baseAddr = trimmed.split('/p2p-circuit').first;
    if (state.relays.any((r) => r.multiaddr == baseAddr)) return;
    final match = RegExp(r'/(?:dns4|ip4)/([^/]+)').firstMatch(baseAddr);
    final name = match?.group(1) ?? 'custom-agy-relay';
    final next = [
      ...state.relays,
      RelayEndpoint(name: name, multiaddr: baseAddr, status: 'Configured', online: true),
    ];
    state = state.copyWith(relays: next);
    await _saveRelays(next);
  }

  Future<void> removeRelay(String multiaddr) async {
    final next = state.relays.where((r) => r.multiaddr != multiaddr).toList();
    state = state.copyWith(relays: next);
    await _saveRelays(next);
  }

  Future<void> probeRelays() async {
    if (state.relays.isEmpty || state.probingRelays) return;
    state = state.copyWith(probingRelays: true);
    final updated = <RelayEndpoint>[];
    for (final relay in state.relays) {
      final baseAddr = relay.multiaddr.split('/p2p-circuit').first;
      final peerMatch = RegExp(r'/p2p/([^/]+)$').firstMatch(baseAddr);
      final relayPeerId = peerMatch?.group(1) ?? '';
      if (relayPeerId.isEmpty) {
        updated.add(relay.copyWith(status: 'Invalid URI', online: false));
        continue;
      }
      try {
        final diag = await transport.connectHost(
          peerId: relayPeerId,
          directAddrs: [baseAddr],
        );
        if (diag.connected) {
          final rttLabel = diag.rttMs > 0 ? '${diag.rttMs}ms' : 'OK';
          updated.add(relay.copyWith(status: 'Online · $rttLabel', online: true));
        } else {
          updated.add(relay.copyWith(status: 'Offline', online: false));
        }
      } catch (_) {
        updated.add(relay.copyWith(status: 'Offline', online: false));
      }
    }
    if (!mounted) return;
    state = state.copyWith(relays: updated, probingRelays: false);
    await _saveRelays(updated);
  }

  Future<void> _saveRelays(List<RelayEndpoint> relays) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsRelaysKey,
        jsonEncode(relays.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveRealHosts(List<PairedHost> hosts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final real = hosts.where((h) => !h.isDemo).map((h) => h.toJson()).toList();
      await prefs.setString(_prefsHostsKey, jsonEncode(real));
    } catch (_) {}
  }

  Future<void> _saveActiveHostId(String hostId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsActiveHostKey, hostId);
    } catch (_) {}
  }

  void toggleDemoHost(bool show) {
    if (!kDebugMode) return;
    if (show == state.showDemoHost) return;
    SharedPreferences.getInstance().then((p) => p.setBool(_prefsShowDemoKey, show)).catchError((_) => false);
    if (show) {
      final demo = _buildInitialState().hosts.first;
      final list = [...state.hosts.where((h) => !h.isDemo), demo];
      state = state.copyWith(showDemoHost: true, hosts: list);
    } else {
      final list = state.hosts.where((h) => !h.isDemo).toList();
      state = state.copyWith(
        showDemoHost: false,
        hosts: list,
        activeHostId: list.isNotEmpty ? list.first.id : '',
      );
    }
  }

  Future<void> refreshActiveHost() async {
    final host = state.activeHost;
    if (host == null || host.isDemo) return;
    await selectHost(host.id);
  }

  Future<void> selectHost(String hostId) async {
    state = state.copyWith(activeHostId: hostId);
    unawaited(_saveActiveHostId(hostId));
    final host = state.activeHost;
    if (host == null || host.isDemo) {
      _syncAndroidRuntime();
      return;
    }

    try {
      final diag = await transport.connectHost(
        peerId: host.peerId,
        directAddrs: host.directAddrs,
        relayAddrs: host.relayAddrs,
      );
      _updateHostDiagnostics(host.id, diag);
      await _ensureEventSubscription(host.peerId, force: true);
      _syncAndroidRuntime();
      await refreshHostData(state.activeHost ?? host);
    } catch (e) {
      _syncAndroidRuntime();
      state = state.copyWith(handoffBanner: 'Connect error: $e', handoffSuccess: false);
    }
  }

  void _updateHostDiagnostics(String hostId, ConnDiagnostics diag) {
    state = state.copyWith(
      hosts: state.hosts.map((h) => h.id == hostId ? h.copyWith(diagnostics: diag) : h).toList(),
    );
  }

  Future<void> refreshHostData(PairedHost host) async {
    if (host.isDemo) return;
    try {
      final infoRaw = await transport.rpcCall(host.peerId, 'host/info', {});
      if (infoRaw is Map<String, dynamic>) {
        final roots = (infoRaw['workspaceRoots'] as List? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        state = state.copyWith(
          hosts: state.hosts.map((h) {
            if (h.id != host.id) return h;
            return h.copyWith(
              name: (infoRaw['hostname'] ?? h.name).toString(),
              os: '${infoRaw['os'] ?? 'linux'} · ${infoRaw['arch'] ?? 'arm64'}',
              agyVersion: (infoRaw['agyVersion'] ?? h.agyVersion).toString(),
              workspaceRoots: roots.isNotEmpty ? roots : h.workspaceRoots,
              cpuPercent: (infoRaw['cpuPercent'] as num?)?.toInt() ?? h.cpuPercent,
              ramPercent: (infoRaw['ramPercent'] as num?)?.toInt() ?? h.ramPercent,
            );
          }).toList(),
        );
        unawaited(_saveRealHosts(state.hosts));
      }

      final sessRaw = await transport.rpcCall(host.peerId, 'session/list', {});
      if (sessRaw is Map<String, dynamic>) {
        final items = sessRaw['sessions'] as List? ?? const [];
        final parsed = items.whereType<Map<String, dynamic>>().map((s) {
          return AgentSession(
            id: (s['sessionId'] ?? '').toString(),
            hostId: host.id,
            title: (s['title'] ?? 'Untitled Session').toString(),
            cwd: (s['cwd'] ?? '~').toString(),
            updatedAt: (s['updatedAt'] ?? '').toString(),
            status: 'idle',
          );
        }).toList();
        final other = state.sessions.where((s) => s.hostId != host.id).toList();
        final nextActive = parsed.any((s) => s.id == state.activeSessionId)
            ? state.activeSessionId
            : (parsed.isNotEmpty ? parsed.first.id : state.activeSessionId);
        state = state.copyWith(
          sessions: [...parsed, ...other],
          activeSessionId: nextActive,
        );
      }

      await refreshAuthorizedPeers();
      await refreshWorkspaceData();
    } catch (_) {}
  }

  Future<PairChallengeInfo> startPairing({
    String? uri,
    String? hostPeerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
    String? token,
    String? pin,
  }) {
    return transport.pairStart(
      uri: uri,
      hostPeerId: hostPeerId,
      directAddrs: directAddrs,
      relayAddrs: relayAddrs,
      token: token,
      pin: pin,
      deviceName: Platform.isAndroid ? 'Android Device' : 'Antigravity Mobile',
    );
  }

  Future<PairedHost?> confirmPairing(
    PairChallengeInfo challenge,
    bool accept, {
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
  }) async {
    final res = await transport.pairConfirm(challenge.sessionId, accept);
    if (!res.paired) return null;

    final diag = await transport.diagnostics(res.hostPeerId);
    final newHost = PairedHost(
      id: res.hostPeerId,
      peerId: res.hostPeerId,
      name: res.hostName.isNotEmpty ? res.hostName : challenge.hostName,
      os: res.hostOs,
      agyVersion: res.agyVersion,
      directAddrs: directAddrs,
      relayAddrs: res.relayAddrs.isNotEmpty ? res.relayAddrs : relayAddrs,
      diagnostics: diag,
    );

    final updated = [newHost, ...state.hosts.where((h) => h.peerId != newHost.peerId)];
    state = state.copyWith(
      hosts: updated,
      activeHostId: newHost.id,
    );
    await _saveRealHosts(updated);
    await _saveActiveHostId(newHost.id);
    for (final relayAddr in newHost.relayAddrs) {
      await addRelay(relayAddr);
    }
    await _ensureEventSubscription(newHost.peerId, force: true, sinceSeq: 0);
    _syncAndroidRuntime();
    await refreshHostData(newHost);
    return newHost;
  }

  Future<void> removeHost(String hostId) async {
    final host = state.hosts.where((h) => h.id == hostId).isNotEmpty
        ? state.hosts.firstWhere((h) => h.id == hostId)
        : null;
    if (host != null && !host.isDemo) {
      await transport.disconnectHost(host.peerId);
    }
    final next = state.hosts.where((h) => h.id != hostId).toList();
    final nextActive = next.isNotEmpty ? next.first.id : '';
    state = state.copyWith(
      hosts: next,
      activeHostId: nextActive,
    );
    _syncAndroidRuntime();
    await _saveRealHosts(next);
    await _saveActiveHostId(nextActive);
  }

  Future<HolePunchResult> retryHolePunch(String hostId) async {
    final matches = state.hosts.where((h) => h.id == hostId);
    final host = matches.isNotEmpty ? matches.first : null;
    if (host == null || host.isDemo) {
      final d = host?.diagnostics ??
          const ConnDiagnostics(
            peerId: '',
            connected: true,
            pathType: 'relay',
            transport: 'Circuit Relay v2 · QUIC + Noise',
            remoteAddr: '',
            rttMs: 64,
            isRelayed: true,
          );
      return HolePunchResult(
        diagnostics: d,
        message: 'Both peers behind Symmetric NAT — maintaining Circuit Relay v2 (64 ms).',
      );
    }
    final res = await transport.retryHolePunch(host.peerId);
    _updateHostDiagnostics(hostId, res.diagnostics);
    return res;
  }

  Future<void> openSession(String sessionId, {bool forceReload = false}) async {
    final matches = state.sessions.where((s) => s.id == sessionId);
    final sess = matches.isNotEmpty ? matches.first : null;
    state = state.copyWith(
      activeSessionId: sessionId,
      activeHostId: sess?.hostId ?? state.activeHostId,
    );

    final host = state.activeHost;
    if (host == null || host.isDemo || sess == null) return;
    if (state.loadingSession && state.activeSessionId == sessionId) return;
    if (!forceReload && state.loadedRealSessions.contains(sessionId)) {
      unawaited(refreshWorkspaceData());
      return;
    }

    final previousMessages = state.messagesBySession[sessionId] ?? const <ChatMessage>[];
    state = state.copyWith(
      loadingSession: true,
      contextUsedTokens: 0,
      messagesBySession: {...state.messagesBySession, sessionId: const []},
    );

    try {
      await _ensureEventSubscription(host.peerId);
      final res = await transport.rpcCall(host.peerId, 'session/load', {
        'sessionId': sessionId,
        'cwd': sess.cwd,
        'mcpServers': const [],
        'historyLimit': 15,
      });

      if (res is Map<String, dynamic>) {
        final modelsObj = res['models'] as Map<String, dynamic>? ?? const {};
        final availModels = (modelsObj['availableModels'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModelOption.fromJson)
            .where((m) => m.id.isNotEmpty)
            .toList();
        final currentModelId = (modelsObj['currentModelId'] ?? '').toString();

        final modesObj = res['modes'] as Map<String, dynamic>? ?? const {};
        final availModes = (modesObj['availableModes'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModeOption.fromJson)
            .where((m) => m.id.isNotEmpty)
            .toList();
        final currentModeId = (modesObj['currentModeId'] ?? '').toString();

        var nextMessages = state.messagesBySession;
        var nextCursors = state.historyNextCursor;
        var nextHasMore = state.historyHasMore;
        final historyObj = res['history'];
        if (historyObj is Map<String, dynamic>) {
          final rawItems = historyObj['items'] as List? ?? const [];
          final cursor = (historyObj['nextCursor'] as num?)?.toInt() ?? 0;
          final hasMore = historyObj['hasMore'] == true;
          final parsed = _parseHistoryItems(sessionId, rawItems, idOffset: cursor);
          nextMessages = {...state.messagesBySession, sessionId: parsed};
          nextCursors = {...state.historyNextCursor, sessionId: cursor};
          nextHasMore = {...state.historyHasMore, sessionId: hasMore};
        }

        state = state.copyWith(
          availableModels: availModels.isNotEmpty ? availModels : state.availableModels,
          availableModes: availModes.isNotEmpty ? availModes : state.availableModes,
          loadedRealSessions: {...state.loadedRealSessions, sessionId},
          messagesBySession: nextMessages,
          historyNextCursor: nextCursors,
          historyHasMore: nextHasMore,
          sessions: state.sessions.map((s) {
            if (s.id != sessionId) return s;
            return s.copyWith(
              model: currentModelId.isNotEmpty ? currentModelId : s.model,
              mode: currentModeId.isNotEmpty ? currentModeId : s.mode,
            );
          }).toList(),
        );
      }
    } catch (e) {
      if (previousMessages.isNotEmpty &&
          (state.messagesBySession[sessionId]?.isEmpty ?? true)) {
        state = state.copyWith(
          messagesBySession: {...state.messagesBySession, sessionId: previousMessages},
        );
      }
      _appendMessage(
        sessionId,
        ChatMessage(
          id: 'load-err-${DateTime.now().microsecondsSinceEpoch}',
          kind: ChatMessageKind.assistant,
          text: 'Could not load session history: $e',
        ),
      );
    } finally {
      if (mounted) {
        _finalizeStreaming(sessionId);
        state = state.copyWith(loadingSession: false);
        unawaited(refreshWorkspaceData());
      }
    }
  }

  Future<bool> loadOlderHistory(String sessionId) async {
    final host = state.activeHost;
    if (host == null || host.isDemo) return false;
    if (state.loadingOlderHistory || state.historyHasMore[sessionId] != true) {
      return false;
    }
    final before = state.historyNextCursor[sessionId] ?? 0;
    if (before <= 0) return false;

    state = state.copyWith(loadingOlderHistory: true);
    try {
      final res = await transport.rpcCall(host.peerId, 'session/history', {
        'sessionId': sessionId,
        'before': before,
        'limit': 15,
      });
      if (!mounted) return false;
      if (res is Map<String, dynamic>) {
        final rawItems = res['items'] as List? ?? const [];
        final cursor = (res['nextCursor'] as num?)?.toInt() ?? 0;
        final hasMore = res['hasMore'] == true;
        final older = _parseHistoryItems(sessionId, rawItems, idOffset: cursor);
        final existing = state.messagesBySession[sessionId] ?? const <ChatMessage>[];
        state = state.copyWith(
          loadingOlderHistory: false,
          messagesBySession: {
            ...state.messagesBySession,
            sessionId: [...older, ...existing],
          },
          historyNextCursor: {...state.historyNextCursor, sessionId: cursor},
          historyHasMore: {...state.historyHasMore, sessionId: hasMore},
        );
        return older.isNotEmpty;
      }
    } catch (_) {}
    if (mounted) {
      state = state.copyWith(loadingOlderHistory: false);
    }
    return false;
  }

  Future<void> browseWorkspaceDir(String path) async {
    await refreshWorkspaceData(treePath: path.isEmpty ? '.' : path);
  }

  Future<void> refreshWorkspaceData({String? treePath}) async {
    final host = state.activeHost;
    final sess = state.activeSession;
    if (host == null || host.isDemo || sess == null) return;

    final targetPath = treePath ?? state.currentWorkspacePath;
    state = state.copyWith(loadingWorkspace: true);
    try {
      final results = await Future.wait([
        transport.rpcCall(host.peerId, 'workspace/git_status', {'cwd': sess.cwd}),
        transport.rpcCall(host.peerId, 'workspace/tree', {'root': sess.cwd, 'path': targetPath}),
        transport.rpcCall(host.peerId, 'artifacts/list', {'sessionId': sess.id}),
      ]);

      var changes = state.workspaceChanges;
      if (results[0] is Map<String, dynamic>) {
        final rawChanges = (results[0] as Map<String, dynamic>)['changes'] as List? ?? const [];
        changes = rawChanges.whereType<Map<String, dynamic>>().map(GitChange.fromJson).toList();
      }

      var files = state.workspaceFiles;
      if (results[1] is Map<String, dynamic>) {
        final rawEntries = (results[1] as Map<String, dynamic>)['entries'] as List? ?? const [];
        files = rawEntries.whereType<Map<String, dynamic>>().map(WorkspaceEntry.fromJson).toList();
      }

      var artifacts = state.workspaceArtifacts;
      if (results[2] is Map<String, dynamic>) {
        final rawArts = (results[2] as Map<String, dynamic>)['artifacts'] as List? ?? const [];
        artifacts = rawArts.whereType<Map<String, dynamic>>().map(ArtifactSummary.fromJson).toList();
      }

      if (mounted) {
        state = state.copyWith(
          loadingWorkspace: false,
          currentWorkspacePath: targetPath,
          workspaceChanges: changes,
          workspaceFiles: files,
          workspaceArtifacts: artifacts,
          sessions: state.sessions
              .map((s) => s.id == sess.id ? s.copyWith(diffs: changes.length) : s)
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(loadingWorkspace: false);
    }
  }

  Future<List<String>> fetchWorkspaceFileContent(String relPath) async {
    final host = state.activeHost;
    final sess = state.activeSession;
    if (host == null || host.isDemo || sess == null) {
      return ['(Preview unavailable for demo file $relPath)'];
    }
    try {
      final res = await transport.rpcCall(host.peerId, 'workspace/read_file', {
        'root': sess.cwd,
        'path': relPath,
        'maxBytes': 65536,
      });
      if (res is Map<String, dynamic>) {
        final content = (res['content'] ?? '').toString();
        final truncated = res['truncated'] == true;
        final lines = content.split('\n');
        if (truncated) {
          lines.add('... (truncated)');
        }
        return lines;
      }
    } catch (e) {
      return ['Error reading file: $e'];
    }
    return ['(Empty file)'];
  }

  Future<List<String>> fetchGitDiff(String relPath) async {
    final host = state.activeHost;
    final sess = state.activeSession;
    if (host == null || host.isDemo || sess == null) {
      final cached = state.workspaceChanges.where((c) => c.path == relPath);
      return cached.isNotEmpty ? cached.first.diffLines : ['No diff preview available'];
    }
    try {
      final res = await transport.rpcCall(host.peerId, 'workspace/git_diff', {
        'cwd': sess.cwd,
        'path': relPath,
      });
      if (res is Map<String, dynamic>) {
        final diff = (res['diff'] ?? '').toString();
        if (diff.trim().isNotEmpty) {
          return diff.split('\n');
        }
      }
    } catch (e) {
      return ['Error loading diff: $e'];
    }
    return ['(No unstaged diff for $relPath)'];
  }

  Future<List<String>> fetchArtifactContent(String sessionId, String name) async {
    final host = state.activeHost;
    if (host == null || host.isDemo) {
      final cached = state.workspaceArtifacts.where((a) => a.name == name);
      return cached.isNotEmpty ? cached.first.previewContent.split('\n') : [''];
    }
    try {
      final res = await transport.rpcCall(host.peerId, 'artifacts/read', {
        'sessionId': sessionId,
        'name': name,
      });
      if (res is Map<String, dynamic>) {
        return (res['content'] ?? '').toString().split('\n');
      }
    } catch (e) {
      return ['Error reading artifact: $e'];
    }
    return [''];
  }

  Future<void> refreshAuthorizedPeers() async {
    final host = state.activeHost;
    if (host == null || host.isDemo) return;
    try {
      final res = await transport.rpcCall(host.peerId, 'peers/list', {});
      if (res is Map<String, dynamic>) {
        final raw = res['peers'] as List? ?? const [];
        final peers = raw.whereType<Map<String, dynamic>>().map(AuthorizedPeerInfo.fromJson).toList();
        if (mounted) {
          state = state.copyWith(authorizedPeers: peers);
        }
      }
    } catch (_) {}
  }

  Future<void> revokeAuthorizedPeer(String peerId) async {
    final host = state.activeHost;
    if (host == null || host.isDemo) return;
    try {
      await transport.rpcCall(host.peerId, 'peers/revoke', {'peerId': peerId});
      await refreshAuthorizedPeers();
    } catch (_) {}
  }

  Future<String> createNewSession({
    required String cwd,
    required String title,
    required String mode,
    required String model,
    bool sandbox = true,
  }) async {
    final host = state.activeHost;
    if (host == null) {
      throw StateError('No host paired or selected. Pair a machine first.');
    }
    var sid = 'sess-${DateTime.now().millisecondsSinceEpoch}';

    if (!host.isDemo) {
      final res = await transport.rpcCall(host.peerId, 'session/new', {
        'cwd': cwd,
        'mode': mode.toLowerCase(),
        'model': model,
        'sandbox': sandbox,
      });
      if (res is Map<String, dynamic> && res['sessionId'] != null) {
        sid = res['sessionId'].toString();
      }
    }

    final sess = AgentSession(
      id: sid,
      hostId: host.id,
      title: title.trim().isEmpty ? 'Session in ${cwd.split('/').last}' : title.trim(),
      cwd: cwd,
      model: model,
      mode: mode,
      status: 'active',
      updatedAt: 'Just now',
    );
    state = state.copyWith(
      sessions: [sess, ...state.sessions],
      activeSessionId: sid,
      loadedRealSessions: {...state.loadedRealSessions, sid},
    );
    return sid;
  }

  void toggleThinkingExpanded(String msgId) {
    final sid = state.activeSessionId;
    final list = (state.messagesBySession[sid] ?? const []).map((m) {
      return m.id == msgId ? m.copyWith(expanded: !m.expanded) : m;
    }).toList();
    state = state.copyWith(messagesBySession: {...state.messagesBySession, sid: list});
  }

  void attachWorkspaceFile(String path) {
    if (!state.attachedWorkspaceFiles.contains(path)) {
      state = state.copyWith(
        attachedWorkspaceFiles: [...state.attachedWorkspaceFiles, path],
      );
    }
  }

  void removeWorkspaceFile(String path) {
    state = state.copyWith(
      attachedWorkspaceFiles:
          state.attachedWorkspaceFiles.where((f) => f != path).toList(),
    );
  }

  /// Streams a picked local mobile file into remote `/tmp/agyd-uploads/<session-id>/`.
  Future<void> uploadLocalFile({
    required String localPath,
    required String filename,
    String mimeType = '',
  }) async {
    _cancelledUploadPaths.remove(localPath);
    final host = state.activeHost;
    final sid = state.activeSessionId;
    final pending = UploadedAttachment(
      localPath: localPath,
      filename: filename,
      mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      progress: 0.05,
      uploading: true,
    );
    state = state.copyWith(stagedUploads: [...state.stagedUploads, pending]);

    if (host == null || host.isDemo) {
      // Simulate smooth chunked upload progress for the Demo preview host.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || _cancelledUploadPaths.contains(localPath)) {
        _cancelledUploadPaths.remove(localPath);
        return;
      }
      state = state.copyWith(
        stagedUploads: state.stagedUploads.map((u) {
          return u.localPath == localPath && u.uploading ? u.copyWith(progress: 0.65) : u;
        }).toList(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || _cancelledUploadPaths.remove(localPath)) {
        return;
      }
      final size = File(localPath).existsSync() ? File(localPath).lengthSync() : 2048;
      final isImg = filename.toLowerCase().endsWith('.png') ||
          filename.toLowerCase().endsWith('.jpg') ||
          filename.toLowerCase().endsWith('.jpeg');
      final done = UploadedAttachment(
        uploadId: 'up_${DateTime.now().millisecondsSinceEpoch}',
        localPath: localPath,
        remotePath: '/tmp/agyd-uploads/$sid/$filename',
        filename: filename,
        mimeType: isImg ? 'image/png' : 'text/plain',
        sizeBytes: size,
        isImage: isImg,
        progress: 1.0,
        uploading: false,
      );
      state = state.copyWith(
        stagedUploads: state.stagedUploads.map((u) {
          return u.localPath == localPath && u.uploading ? done : u;
        }).toList(),
      );
      return;
    }

    try {
      final result = await transport.uploadFileToTmp(
        peerId: host.peerId,
        sessionId: sid,
        localPath: localPath,
        filename: filename,
        mimeType: mimeType,
      );
      if (_cancelledUploadPaths.remove(localPath)) {
        if (result.uploadId.isNotEmpty) {
          try {
            await transport.rpcCall(host.peerId, 'workspace/delete_tmp_file', {
              'sessionId': sid,
              'uploadId': result.uploadId,
            });
          } catch (_) {}
        }
        return;
      }
      state = state.copyWith(
        stagedUploads: state.stagedUploads.map((u) {
          return u.localPath == localPath && u.uploading ? result : u;
        }).toList(),
      );
    } catch (e) {
      if (_cancelledUploadPaths.remove(localPath)) return;
      state = state.copyWith(
        stagedUploads: state.stagedUploads.map((u) {
          return u.localPath == localPath && u.uploading
              ? u.copyWith(uploading: false, error: e.toString())
              : u;
        }).toList(),
      );
    }
  }

  Future<void> removeStagedUpload(UploadedAttachment item) async {
    if (item.uploading && item.localPath.isNotEmpty) {
      _cancelledUploadPaths.add(item.localPath);
    }
    state = state.copyWith(
      stagedUploads: state.stagedUploads.where((u) => u != item).toList(),
    );
    final host = state.activeHost;
    if (host != null && !host.isDemo && item.uploadId.isNotEmpty) {
      try {
        await transport.rpcCall(host.peerId, 'workspace/delete_tmp_file', {
          'sessionId': state.activeSessionId,
          'uploadId': item.uploadId,
        });
      } catch (_) {}
    }
  }

  Future<void> sendPrompt(String text) async {
    final trimmed = text.trim();
    final readyUploads = state.stagedUploads.where((u) => !u.uploading && u.error == null).toList();
    if (trimmed.isEmpty && state.attachedWorkspaceFiles.isEmpty && readyUploads.isEmpty) {
      return;
    }

    final chips = [
      ...state.attachedWorkspaceFiles.map((f) => '@$f'),
      ...readyUploads.map((u) => '📎 ${u.filename} (/tmp)'),
    ];
    final files = List<String>.from(state.attachedWorkspaceFiles);
    final uploadIds = readyUploads.map((u) => u.uploadId).where((id) => id.isNotEmpty).toList();
    final imagePaths = readyUploads
        .where((u) => u.isImage && u.localPath.isNotEmpty)
        .map((u) => u.localPath)
        .toList();
    final sid = state.activeSessionId;

    _appendMessage(
      sid,
      ChatMessage(
        id: 'u-${DateTime.now().microsecondsSinceEpoch}',
        kind: ChatMessageKind.user,
        text: trimmed.isNotEmpty ? trimmed : 'Inspect attached files.',
        chips: chips,
        imagePaths: imagePaths,
      ),
    );

    state = state.copyWith(
      attachedWorkspaceFiles: const [],
      stagedUploads: const [],
      isStreaming: true,
    );
    _syncAndroidRuntime();

    final host = state.activeHost;
    if (host == null || host.isDemo) {
      // Realistic simulated agent turn when viewing the Demo host.
      final thinkId = 'th-${DateTime.now().microsecondsSinceEpoch}';
      _appendMessage(
        sid,
        ChatMessage(
          id: thinkId,
          kind: ChatMessageKind.thinking,
          streaming: true,
          thinkingSteps: [
            'Received prompt over Noise XX encrypted libp2p stream.',
            if (uploadIds.isNotEmpty || readyUploads.isNotEmpty)
              'Reading staged file(s) from /tmp/agyd-uploads/$sid/.',
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted || !state.isStreaming) return;
      final updatedList = (state.messagesBySession[sid] ?? const []).map((m) {
        return m.id == thinkId
            ? m.copyWith(streaming: false, duration: '1.1s · 2 steps')
            : m;
      }).toList();
      state = state.copyWith(messagesBySession: {...state.messagesBySession, sid: updatedList});

      _appendMessage(
        sid,
        ChatMessage(
          id: 'a-${DateTime.now().microsecondsSinceEpoch}',
          kind: ChatMessageKind.assistant,
          text: readyUploads.isNotEmpty
              ? 'Read uploaded file `${readyUploads.first.filename}` staged at `${readyUploads.first.remotePath}`. Ready to continue!'
              : 'Checked remote workspace on `${host?.name ?? 'home-workstation'}`. Relay reservation and ACP event cursor are healthy.',
        ),
      );
      state = state.copyWith(isStreaming: false);
      _syncAndroidRuntime();
      return;
    }

    _pendingUserEchoes[sid] = trimmed;
    try {
      await transport.rpcCall(host.peerId, 'session/prompt', {
        'sessionId': sid,
        'text': trimmed,
        'files': files,
        'uploadIds': uploadIds,
      });
    } catch (e) {
      _pendingUserEchoes.remove(sid);
      state = state.copyWith(isStreaming: false);
      _syncAndroidRuntime();
      _appendMessage(
        sid,
        ChatMessage(
          id: 'err-${DateTime.now().microsecondsSinceEpoch}',
          kind: ChatMessageKind.assistant,
          text: 'Error sending prompt: $e',
        ),
      );
    }
  }

  Future<void> cancelTurn() async {
    state = state.copyWith(isStreaming: false);
    _syncAndroidRuntime();
    final host = state.activeHost;
    if (host != null && !host.isDemo) {
      try {
        await transport.rpcCall(host.peerId, 'session/cancel', {
          'sessionId': state.activeSessionId,
        });
      } catch (_) {}
    }
    _appendMessage(
      state.activeSessionId,
      ChatMessage(
        id: 'cancel-${DateTime.now().microsecondsSinceEpoch}',
        kind: ChatMessageKind.assistant,
        text: '[Turn cancelled via ACP session/cancel.]',
      ),
    );
  }

  Future<void> resolvePermission(
    String msgId,
    String permId,
    PermissionStatus decision, {
    String? customOptionId,
  }) async {
    final sid = state.activeSessionId;
    final nextList = (state.messagesBySession[sid] ?? const []).map((m) {
      return m.id == msgId ? m.copyWith(permStatus: decision) : m;
    }).toList();
    state = state.copyWith(messagesBySession: {...state.messagesBySession, sid: nextList});

    final host = state.activeHost;
    if (host == null || host.isDemo) {
      if (decision == PermissionStatus.denied) {
        _appendMessage(
          sid,
          ChatMessage(
            id: 'pd-${DateTime.now().microsecondsSinceEpoch}',
            kind: ChatMessageKind.assistant,
            text: 'Command execution denied (`reject-once`). Workspace left untouched.',
          ),
        );
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        _appendMessage(
          sid,
          ChatMessage(
            id: 'term-${DateTime.now().microsecondsSinceEpoch}',
            kind: ChatMessageKind.terminal,
            command: 'go test ./pkg/p2p/... -v -race',
            detail: 'PASS · 1.42s',
            text:
                '=== RUN   TestCircuitRelaySymmetricNAT\n--- PASS: TestCircuitRelaySymmetricNAT (0.68s)\nPASS\nok   pkg/p2p   1.421s',
          ),
        );
      }
      return;
    }

    final cancelled = decision == PermissionStatus.denied && (customOptionId == null || customOptionId.isEmpty);
    final optionId = (customOptionId != null && customOptionId.isNotEmpty)
        ? customOptionId
        : (decision == PermissionStatus.allowedAlways ? 'allow-always' : 'allow-once');
    try {
      await transport.rpcCall(host.peerId, 'session/respond_permission', {
        'permId': permId,
        'optionId': cancelled ? '' : optionId,
        'cancelled': cancelled,
      });
    } catch (_) {}
  }

  Future<void> updateSessionModeAndModel({String? mode, String? model}) async {
    final sid = state.activeSessionId;
    state = state.copyWith(
      sessions: state.sessions.map((s) {
        if (s.id != sid) return s;
        return s.copyWith(mode: mode, model: model);
      }).toList(),
    );
    final host = state.activeHost;
    if (host == null || host.isDemo) return;

    if (mode != null) {
      try {
        await transport.rpcCall(host.peerId, 'session/set_mode', {
          'sessionId': sid,
          'modeId': mode.toLowerCase().replaceAll(' ', '-'),
        });
      } catch (_) {}
    }
    if (model != null) {
      try {
        await transport.rpcCall(host.peerId, 'session/set_model', {
          'sessionId': sid,
          'modelId': model,
        });
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _reconnectTimer?.cancel();
    _eventSub?.cancel();
    _connSub?.cancel();
    unawaited(androidRuntime.stopForegroundService());
    unawaited(androidRuntime.setKeepScreenOn(false));
    super.dispose();
  }
}
