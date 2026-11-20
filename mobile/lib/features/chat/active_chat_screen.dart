import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../hosts/diagnostics_sheet.dart';
import 'chat_items.dart';
import 'composer_dock.dart';

class ActiveChatScreen extends ConsumerStatefulWidget {
  const ActiveChatScreen({super.key});

  @override
  ConsumerState<ActiveChatScreen> createState() => _ActiveChatScreenState();
}

class _ActiveChatScreenState extends ConsumerState<ActiveChatScreen> {
  final _scrollCtrl = ScrollController();
  bool _showJumpLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // In a reversed ListView, 0.0 is the bottom (latest) and maxScrollExtent is the top (oldest).
    final away = pos.pixels > 140;
    if (away != _showJumpLatest) {
      setState(() => _showJumpLatest = away);
    }
    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 160) {
      _maybeLoadOlderHistory();
    }
  }

  void _maybeLoadOlderHistory() {
    final state = ref.read(appControllerProvider);
    final sid = state.activeSessionId;
    if (sid.isEmpty ||
        state.loadingOlderHistory ||
        state.historyHasMore[sid] != true) {
      return;
    }
    ref.read(appControllerProvider.notifier).loadOlderHistory(sid);
  }

  void _jumpToBottom({bool animate = true}) {
    if (!mounted || !_scrollCtrl.hasClients) return;
    if (animate) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(0);
    }
  }

  String _formatTranscript(
    AgentSession? session,
    List<ChatMessage> messages,
  ) {
    final buf = StringBuffer()
      ..writeln('# ${session?.title ?? 'Agent Session'}')
      ..writeln('_${session?.cwd ?? '~'} · ${session?.branch ?? 'main'}_')
      ..writeln();
    for (final m in messages) {
      switch (m.kind) {
        case ChatMessageKind.user:
          buf.writeln('## User\n${m.text}');
          if (m.chips.isNotEmpty) {
            buf.writeln('Attachments: ${m.chips.join(', ')}');
          }
          buf.writeln();
        case ChatMessageKind.assistant:
          buf.writeln('## Assistant\n${m.text}');
          if (m.code.isNotEmpty) {
            buf.writeln('\n```${m.codeTitle}\n${m.code}\n```');
          }
          buf.writeln();
        case ChatMessageKind.terminal:
          buf.writeln('### Command: `${m.command}` (${m.detail})');
          if (m.text.isNotEmpty) {
            buf.writeln('```\n${m.text}\n```');
          }
          buf.writeln();
        case ChatMessageKind.toolEdit:
          buf.writeln('### Edited `${m.filePath}` (+${m.additions}/-${m.deletions})');
          if (m.diffLines.isNotEmpty) {
            buf.writeln('```diff\n${m.diffLines.join('\n')}\n```');
          }
          buf.writeln();
        case ChatMessageKind.toolRead:
          buf.writeln('- Read `${m.filePath}` (${m.detail})');
        case ChatMessageKind.plan:
          buf.writeln('- Plan (${m.planCurrent}/${m.planTotal}): ${m.text}');
        case ChatMessageKind.thinking:
        case ChatMessageKind.permission:
          break;
      }
    }
    return buf.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final host = state.activeHost;
    final session = state.activeSession;
    final messages = state.activeMessages;
    final hasMoreHistory = session != null && (state.historyHasMore[session.id] == true);

    final tokenLabel = state.contextMaxTokens > 0
        ? ' · ${(state.contextUsedTokens / 1000).toStringAsFixed(1)}k/${(state.contextMaxTokens / 1000).round()}k'
        : '';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leadingWidth: 42,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session?.title ?? 'Agent Session',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${session?.cwd ?? '~'} · ${session?.branch ?? 'main'}$tokenLabel',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: c.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 19),
              tooltip: 'Copy transcript',
              onPressed: () {
                final md = _formatTranscript(session, messages);
                Clipboard.setData(ClipboardData(text: md));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transcript copied as Markdown')),
                );
              },
            ),
          if (host != null && !host.isDemo && session != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 19),
              tooltip: 'Reload session history',
              onPressed: () => controller.openSession(session.id, forceReload: true),
            ),
          if (host != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: ConnectionPill(
                  diagnostics: host.diagnostics,
                  onTap: () => showDiagnosticsSheet(context, host),
                ),
              ),
            ),
          if ((session?.diffs ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: Material(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      controller.setNavTab(2);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${session!.diffs} diffs',
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(state.loadingSession ? 3 : 1),
          child: state.loadingSession
              ? const LinearProgressIndicator(minHeight: 2.5)
              : Divider(height: 1, color: c.border),
        ),
      ),
      body: Column(
        children: [
          if (state.handoffBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: state.handoffSuccess ? c.successSoft : c.warningSoft,
              child: Text(
                state.handoffBanner!,
                style: TextStyle(
                  color: state.handoffSuccess ? c.success : c.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Session ready on ${host?.name ?? 'host'}.\nSend a prompt below to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.separated(
                        key: const Key('chat-list'),
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: messages.length + (hasMoreHistory ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 11),
                        itemBuilder: (ctx, idx) {
                          if (hasMoreHistory && idx == messages.length) {
                            return Center(
                              child: state.loadingOlderHistory
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 6),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _maybeLoadOlderHistory,
                                      child: Text(
                                        'Load earlier messages',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                                      ),
                                    ),
                            );
                          }
                          final m = messages[messages.length - 1 - idx];
                          return ChatMessageTile(
                            msg: m,
                            onToggleThink: () => controller.toggleThinkingExpanded(m.id),
                            onViewDiff: (file, lines) => showUnifiedDiffSheet(
                              context,
                              title: file,
                              subtitle: '+${m.additions} additions · -${m.deletions} deletions',
                              lines: lines,
                            ),
                            onResolvePermission: (decision, {optionId}) => controller
                                .resolvePermission(m.id, m.permId, decision, customOptionId: optionId),
                          );
                        },
                      ),
                      if (_showJumpLatest)
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: GradientPillButton(
                            label: 'Latest',
                            icon: Icons.arrow_downward,
                            onPressed: () => _jumpToBottom(animate: true),
                          ),
                        ),
                    ],
                  ),
          ),
          const ComposerDock(),
        ],
      ),
    );
  }
}
