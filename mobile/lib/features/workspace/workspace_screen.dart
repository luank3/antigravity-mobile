import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../chat/active_chat_screen.dart';
import '../hosts/diagnostics_sheet.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  int _tab = 0; // 0=Changes, 1=Files, 2=Artifacts

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final host = state.activeHost;
    final session = state.activeSession;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workspace',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                    ),
                    if (session != null)
                      Text(
                        '${session.cwd} · ${session.branch}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: c.textSecondary,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (host != null && !host.isDemo)
                IconButton(
                  icon: state.loadingWorkspace
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: state.loadingWorkspace ? null : controller.refreshWorkspaceData,
                ),
              if (host != null)
                ConnectionPill(
                  diagnostics: host.diagnostics,
                  onTap: () => showDiagnosticsSheet(context, host),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: AgySegmentedControl<int>(
            items: [
              (0, 'Changes (${state.workspaceChanges.length})'),
              (1, 'Files'),
              (2, 'Artifacts (${state.workspaceArtifacts.length})'),
            ],
            selected: _tab,
            onChanged: (next) => setState(() => _tab = next),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refreshWorkspaceData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
            children: [
              if (_tab == 0)
                for (final ch in state.workspaceChanges) ...[
                  SurfaceCard(
                    onTap: () async {
                      final lines = await controller.fetchGitDiff(ch.path);
                      if (!context.mounted) return;
                      await showUnifiedDiffSheet(
                        context,
                        title: ch.path,
                        subtitle: '+${ch.additions} additions · -${ch.deletions} deletions',
                        lines: lines,
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: c.surfaceRaised,
                          child: Text('Δ', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ch.path,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (ch.summary.isNotEmpty)
                                Text(ch.summary, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Text(
                          '+${ch.additions} ',
                          style: TextStyle(fontFamily: 'monospace', color: c.success, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '-${ch.deletions}',
                          style: TextStyle(fontFamily: 'monospace', color: c.danger, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              if (_tab == 1)
                for (final f in state.workspaceFiles) ...[
                  SurfaceCard(
                    onTap: () {
                      controller.attachWorkspaceFile(f.path);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ActiveChatScreen()),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, color: c.accent),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            f.path,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        StatusBadge(label: '@ Attach', fg: c.accent, bg: c.accentSoft),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              if (_tab == 2)
                for (final art in state.workspaceArtifacts) ...[
                  SurfaceCard(
                    onTap: () async {
                      final lines = await controller.fetchArtifactContent(art.sessionId, art.name);
                      if (!context.mounted) return;
                      await showUnifiedDiffSheet(
                        context,
                        title: art.name,
                        subtitle: '${art.sessionId} · ${art.updatedAt}',
                        lines: lines,
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.article_outlined, color: c.accentIndigo),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(art.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              Text('${art.sessionId} · ${art.updatedAt}', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        StatusBadge(label: 'Preview', fg: c.textSecondary, bg: c.surfaceRaised),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
            ),
          ),
        ),
      ],
    );
  }
}
