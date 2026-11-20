import 'dart:convert';

class ConnDiagnostics {
  final String peerId;
  final bool connected;
  final String pathType; // "lan" | "direct" | "relay" | "disconnected"
  final String transport;
  final String remoteAddr;
  final String relayPeerId;
  final int rttMs;
  final bool isRelayed;

  const ConnDiagnostics({
    required this.peerId,
    required this.connected,
    required this.pathType,
    required this.transport,
    required this.remoteAddr,
    this.relayPeerId = '',
    this.rttMs = 0,
    this.isRelayed = false,
  });

  factory ConnDiagnostics.fromJson(Map<String, dynamic> j) => ConnDiagnostics(
        peerId: (j['peerId'] ?? '').toString(),
        connected: j['connected'] == true,
        pathType: (j['pathType'] ?? 'disconnected').toString(),
        transport: (j['transport'] ?? '').toString(),
        remoteAddr: (j['remoteAddr'] ?? '').toString(),
        relayPeerId: (j['relayPeerId'] ?? '').toString(),
        rttMs: (j['rttMs'] as num?)?.toInt() ?? 0,
        isRelayed: j['isRelayed'] == true,
      );

  String get pillLabel {
    if (!connected) return 'Offline';
    final prefix = switch (pathType) {
      'lan' => 'LAN',
      'direct' => 'Direct',
      'relay' => 'Relay',
      _ => 'Connected',
    };
    return rttMs > 0 ? '$prefix · ${rttMs}ms' : prefix;
  }
}

class PairedHost {
  final String id;
  final String peerId;
  final String name;
  final String os;
  final String agyVersion;
  final List<String> directAddrs;
  final List<String> relayAddrs;
  final List<String> workspaceRoots;
  final int cpuPercent;
  final int ramPercent;
  final int runningCount;
  final bool isDemo;
  final ConnDiagnostics diagnostics;

  const PairedHost({
    required this.id,
    required this.peerId,
    required this.name,
    required this.os,
    required this.agyVersion,
    this.directAddrs = const [],
    this.relayAddrs = const [],
    this.workspaceRoots = const [],
    this.cpuPercent = 18,
    this.ramPercent = 44,
    this.runningCount = 0,
    this.isDemo = false,
    required this.diagnostics,
  });

  PairedHost copyWith({
    String? name,
    String? os,
    String? agyVersion,
    List<String>? directAddrs,
    List<String>? relayAddrs,
    List<String>? workspaceRoots,
    int? cpuPercent,
    int? ramPercent,
    int? runningCount,
    ConnDiagnostics? diagnostics,
  }) {
    return PairedHost(
      id: id,
      peerId: peerId,
      name: name ?? this.name,
      os: os ?? this.os,
      agyVersion: agyVersion ?? this.agyVersion,
      directAddrs: directAddrs ?? this.directAddrs,
      relayAddrs: relayAddrs ?? this.relayAddrs,
      workspaceRoots: workspaceRoots ?? this.workspaceRoots,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      ramPercent: ramPercent ?? this.ramPercent,
      runningCount: runningCount ?? this.runningCount,
      isDemo: isDemo,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'name': name,
        'os': os,
        'agyVersion': agyVersion,
        'directAddrs': directAddrs,
        'relayAddrs': relayAddrs,
        'workspaceRoots': workspaceRoots,
        'isDemo': isDemo,
      };

  factory PairedHost.fromJson(Map<String, dynamic> j) {
    final pid = (j['peerId'] ?? '').toString();
    return PairedHost(
      id: (j['id'] ?? pid).toString(),
      peerId: pid,
      name: (j['name'] ?? 'Remote Host').toString(),
      os: (j['os'] ?? 'Linux').toString(),
      agyVersion: (j['agyVersion'] ?? 'agy v1.5.13').toString(),
      directAddrs: (j['directAddrs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      relayAddrs: (j['relayAddrs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      workspaceRoots: (j['workspaceRoots'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isDemo: j['isDemo'] == true,
      diagnostics: ConnDiagnostics(
        peerId: pid,
        connected: false,
        pathType: 'disconnected',
        transport: '',
        remoteAddr: '',
      ),
    );
  }
}

class AgentSession {
  final String id;
  final String hostId;
  final String title;
  final String cwd;
  final String branch;
  final int diffs;
  final String model;
  final String mode;
  final String status; // "active" | "approval" | "idle"
  final String updatedAt;

  const AgentSession({
    required this.id,
    required this.hostId,
    required this.title,
    required this.cwd,
    this.branch = 'main',
    this.diffs = 0,
    this.model = 'Neon High',
    this.mode = 'Auto',
    this.status = 'idle',
    this.updatedAt = 'Just now',
  });

  AgentSession copyWith({
    String? title,
    String? model,
    String? mode,
    String? status,
    int? diffs,
    String? updatedAt,
  }) {
    return AgentSession(
      id: id,
      hostId: hostId,
      title: title ?? this.title,
      cwd: cwd,
      branch: branch,
      diffs: diffs ?? this.diffs,
      model: model ?? this.model,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ChatMessageKind {
  user,
  thinking,
  plan,
  toolRead,
  toolEdit,
  terminal,
  assistant,
  permission,
}

enum PermissionStatus { pending, allowedOnce, allowedAlways, denied }

class ChatMessage {
  final String id;
  final ChatMessageKind kind;
  final String text;
  final List<String> chips;
  final List<String> imagePaths;
  final List<String> thinkingSteps;
  final String duration;
  final bool expanded;
  final bool streaming;
  final int planCurrent;
  final int planTotal;
  final String filePath;
  final String detail;
  final int additions;
  final int deletions;
  final List<String> diffLines;
  final String toolCallId;
  final String toolStatus;
  final String codeTitle;
  final String code;
  final String permId;
  final String command;
  final String cwd;
  final String sandbox;
  final PermissionStatus permStatus;
  final List<Map<String, String>> permOptions;

  const ChatMessage({
    required this.id,
    required this.kind,
    this.text = '',
    this.chips = const [],
    this.imagePaths = const [],
    this.thinkingSteps = const [],
    this.duration = '',
    this.expanded = false,
    this.streaming = false,
    this.planCurrent = 0,
    this.planTotal = 0,
    this.filePath = '',
    this.detail = '',
    this.additions = 0,
    this.deletions = 0,
    this.diffLines = const [],
    this.toolCallId = '',
    this.toolStatus = '',
    this.codeTitle = '',
    this.code = '',
    this.permId = '',
    this.command = '',
    this.cwd = '',
    this.sandbox = 'Off',
    this.permStatus = PermissionStatus.pending,
    this.permOptions = const [],
  });

  ChatMessage copyWith({
    String? text,
    List<String>? thinkingSteps,
    String? duration,
    bool? expanded,
    bool? streaming,
    int? planCurrent,
    int? planTotal,
    String? filePath,
    String? detail,
    int? additions,
    int? deletions,
    List<String>? diffLines,
    String? toolStatus,
    String? command,
    PermissionStatus? permStatus,
  }) {
    return ChatMessage(
      id: id,
      kind: kind,
      text: text ?? this.text,
      chips: chips,
      imagePaths: imagePaths,
      thinkingSteps: thinkingSteps ?? this.thinkingSteps,
      duration: duration ?? this.duration,
      expanded: expanded ?? this.expanded,
      streaming: streaming ?? this.streaming,
      planCurrent: planCurrent ?? this.planCurrent,
      planTotal: planTotal ?? this.planTotal,
      filePath: filePath ?? this.filePath,
      detail: detail ?? this.detail,
      additions: additions ?? this.additions,
      deletions: deletions ?? this.deletions,
      diffLines: diffLines ?? this.diffLines,
      toolCallId: toolCallId,
      toolStatus: toolStatus ?? this.toolStatus,
      codeTitle: codeTitle,
      code: code,
      permId: permId,
      command: command ?? this.command,
      cwd: cwd,
      sandbox: sandbox,
      permStatus: permStatus ?? this.permStatus,
      permOptions: permOptions,
    );
  }
}

class UploadedAttachment {
  final String uploadId;
  final String localPath;
  final String remotePath;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final bool isImage;
  final double progress; // 0.0..1.0
  final bool uploading;
  final String? error;

  const UploadedAttachment({
    this.uploadId = '',
    required this.localPath,
    this.remotePath = '',
    required this.filename,
    this.mimeType = 'application/octet-stream',
    this.sizeBytes = 0,
    this.isImage = false,
    this.progress = 0,
    this.uploading = true,
    this.error,
  });

  factory UploadedAttachment.fromResultJson(String localPath, Map<String, dynamic> j) =>
      UploadedAttachment(
        uploadId: (j['uploadId'] ?? '').toString(),
        localPath: localPath,
        remotePath: (j['remotePath'] ?? '').toString(),
        filename: (j['filename'] ?? '').toString(),
        mimeType: (j['mimeType'] ?? 'application/octet-stream').toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        isImage: j['isImage'] == true,
        progress: 1.0,
        uploading: false,
      );

  UploadedAttachment copyWith({
    double? progress,
    bool? uploading,
    String? error,
  }) =>
      UploadedAttachment(
        uploadId: uploadId,
        localPath: localPath,
        remotePath: remotePath,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        isImage: isImage,
        progress: progress ?? this.progress,
        uploading: uploading ?? this.uploading,
        error: error,
      );
}

class WorkspaceEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;

  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
  });

  factory WorkspaceEntry.fromJson(Map<String, dynamic> j) => WorkspaceEntry(
        name: (j['name'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        isDir: j['isDir'] == true,
        size: (j['size'] as num?)?.toInt() ?? 0,
      );
}

class GitChange {
  final String path;
  final String status;
  final int additions;
  final int deletions;
  final String summary;
  final List<String> diffLines;

  const GitChange({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.summary = '',
    this.diffLines = const [],
  });

  factory GitChange.fromJson(Map<String, dynamic> j) => GitChange(
        path: (j['path'] ?? '').toString(),
        status: (j['status'] ?? 'M').toString(),
        additions: (j['additions'] as num?)?.toInt() ?? 0,
        deletions: (j['deletions'] as num?)?.toInt() ?? 0,
      );
}

class ArtifactSummary {
  final String name;
  final String sessionId;
  final int size;
  final String updatedAt;
  final String previewContent;

  const ArtifactSummary({
    required this.name,
    required this.sessionId,
    required this.size,
    required this.updatedAt,
    this.previewContent = '',
  });

  factory ArtifactSummary.fromJson(Map<String, dynamic> j) => ArtifactSummary(
        name: (j['name'] ?? '').toString(),
        sessionId: (j['sessionId'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] ?? '').toString(),
      );
}

class RelayEndpoint {
  final String name;
  final String multiaddr;
  final String status;
  final bool online;

  const RelayEndpoint({
    required this.name,
    required this.multiaddr,
    required this.status,
    this.online = true,
  });

  RelayEndpoint copyWith({
    String? name,
    String? multiaddr,
    String? status,
    bool? online,
  }) =>
      RelayEndpoint(
        name: name ?? this.name,
        multiaddr: multiaddr ?? this.multiaddr,
        status: status ?? this.status,
        online: online ?? this.online,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'multiaddr': multiaddr,
        'status': status,
        'online': online,
      };

  factory RelayEndpoint.fromJson(Map<String, dynamic> j) => RelayEndpoint(
        name: (j['name'] ?? '').toString(),
        multiaddr: (j['multiaddr'] ?? '').toString(),
        status: (j['status'] ?? 'Configured').toString(),
        online: j['online'] != false,
      );
}

class LANDiscoveredPeer {
  final String peerId;
  final List<String> addrs;

  const LANDiscoveredPeer({required this.peerId, required this.addrs});

  factory LANDiscoveredPeer.fromJson(Map<String, dynamic> j) => LANDiscoveredPeer(
        peerId: (j['peerId'] ?? '').toString(),
        addrs: (j['addrs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class PairChallengeInfo {
  final String sessionId;
  final String hostPeerId;
  final String hostName;
  final String sasDigits;
  final String sasEmojis;

  const PairChallengeInfo({
    required this.sessionId,
    required this.hostPeerId,
    required this.hostName,
    required this.sasDigits,
    required this.sasEmojis,
  });

  factory PairChallengeInfo.fromJson(Map<String, dynamic> j) => PairChallengeInfo(
        sessionId: (j['sessionId'] ?? '').toString(),
        hostPeerId: (j['hostPeerId'] ?? '').toString(),
        hostName: (j['hostName'] ?? '').toString(),
        sasDigits: (j['sasDigits'] ?? '').toString(),
        sasEmojis: (j['sasEmojis'] ?? '').toString(),
      );
}

class PairResultInfo {
  final bool paired;
  final String hostPeerId;
  final String hostName;
  final String hostOs;
  final String agyVersion;
  final List<String> relayAddrs;

  const PairResultInfo({
    required this.paired,
    required this.hostPeerId,
    required this.hostName,
    required this.hostOs,
    required this.agyVersion,
    required this.relayAddrs,
  });

  factory PairResultInfo.fromJson(Map<String, dynamic> j) => PairResultInfo(
        paired: j['paired'] == true,
        hostPeerId: (j['hostPeerId'] ?? '').toString(),
        hostName: (j['hostName'] ?? '').toString(),
        hostOs: (j['hostOs'] ?? 'Linux').toString(),
        agyVersion: (j['agyVersion'] ?? 'agy v1.5.13').toString(),
        relayAddrs: (j['relayAddrs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class BridgeEvent {
  final String type;
  final Map<String, dynamic> raw;

  const BridgeEvent({required this.type, required this.raw});

  factory BridgeEvent.parse(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return BridgeEvent(type: (map['type'] ?? '').toString(), raw: map);
  }
}

class SlashCommandInfo {
  final String name;
  final String description;

  const SlashCommandInfo({required this.name, required this.description});

  factory SlashCommandInfo.fromJson(Map<String, dynamic> j) => SlashCommandInfo(
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
      );
}

class ModelOption {
  final String id;
  final String name;

  const ModelOption({required this.id, required this.name});

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        id: (j['modelId'] ?? j['id'] ?? '').toString(),
        name: (j['name'] ?? j['modelId'] ?? '').toString(),
      );
}

class ModeOption {
  final String id;
  final String name;
  final String description;

  const ModeOption({
    required this.id,
    required this.name,
    this.description = '',
  });

  factory ModeOption.fromJson(Map<String, dynamic> j) => ModeOption(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? j['id'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
      );
}

class AuthorizedPeerInfo {
  final String peerId;
  final String deviceName;
  final String pairedAt;
  final String lastSeenAt;

  const AuthorizedPeerInfo({
    required this.peerId,
    required this.deviceName,
    required this.pairedAt,
    required this.lastSeenAt,
  });

  factory AuthorizedPeerInfo.fromJson(Map<String, dynamic> j) => AuthorizedPeerInfo(
        peerId: (j['peerId'] ?? '').toString(),
        deviceName: (j['deviceName'] ?? 'Device').toString(),
        pairedAt: (j['pairedAt'] ?? '').toString(),
        lastSeenAt: (j['lastSeenAt'] ?? '').toString(),
      );
}
