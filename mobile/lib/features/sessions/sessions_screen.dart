import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../chat/active_chat_screen.dart';
import '../hosts/diagnostics_sheet.dart';
import '../pairing/pair_sheet.dart';
import 'new_session_sheet.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  String _query = '';
  String _filter = 'all'; // "all" | "active" | "approval"

  void _openChatScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ActiveChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context, ) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final activeHost = state.activeHost;

    final filtered = state.sessions.where((s) {
      if (activeHost == null) return false;
      if (s.hostId != activeHost.id) return false;
      if (_filter == 'active' && s.status == 'idle') return false;
      if (_filter == 'approval' && s.status != 'approval') return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return s.title.toLowerCase().contains(q) ||
            s.cwd.toLowerCase().contains(q) ||
            s.branch.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: activeHost == null
          ? null
          : GradientPillButton(
              label: 'New Session',
              icon: Icons.add,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              fontSize: 13,
              shadowOpacity: 0.34,
              onPressed: () async {
                final created = await showNewSessionSheet(context);
                if (created && context.mounted) {
                  _openChatScreen(context);
                }
              },
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Material(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: state.hosts.length > 1
                        ? () {
                            final idx = state.hosts.indexWhere((h) => h.id == state.activeHostId);
                            final next = state.hosts[(idx + 1) % state.hosts.length];
                            unawaited(controller.selectHost(next.id));
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: activeHost?.diagnostics.connected == true ? c.success : c.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            activeHost?.name ?? 'Select Host',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (activeHost != null)
                  ConnectionPill(
                    diagnostics: activeHost.diagnostics,
                    onTap: () => showDiagnosticsSheet(context, activeHost),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search sessions, paths, branches...',
                    prefixIcon: const Icon(Icons.search, size: 19),
                    isDense: true,
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final entry in const [
                      ('all', 'All'),
                      ('active', 'Active'),
                      ('approval', 'Needs Approval'),
                    ]) ...[
                      AgyFilterChip(
                        label: entry.$2,
                        selected: _filter == entry.$1,
                        onTap: () => setState(() => _filter = entry.$1),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshActiveHost,
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 260,
                          child: Center(
                            child: activeHost == null
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.dns_outlined, size: 42, color: c.textMuted),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'No Paired Host',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Pair a remote machine to start or resume agent sessions.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: c.textSecondary, fontSize: 13),
                                        ),
                                        const SizedBox(height: 14),
                                        GradientPillButton(
                                          label: 'Pair Machine',
                                          icon: Icons.add,
                                          onPressed: () => showPairMachineSheet(context),
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    'No sessions match your filter.',
                                    style: TextStyle(color: c.textSecondary),
                                  ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 88),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final s = filtered[idx];
                      final isApproval = s.status == 'approval' && state.pendingApprovalCount > 0;
                      return SurfaceCard(
                        borderColor: isApproval ? c.warning.withValues(alpha: 0.6) : c.border,
                        onTap: () {
                          unawaited(controller.openSession(s.id));
                          _openChatScreen(context);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isApproval)
                                  StatusBadge(
                                    label: 'Approval Needed',
                                    fg: c.warning,
                                    bg: c.warningSoft,
                                  )
                                else if (s.status == 'active')
                                  StatusBadge(
                                    label: 'Active',
                                    fg: c.accent,
                                    bg: c.accentSoft,
                                  )
                                else
                                  StatusBadge(
                                    label: 'Idle',
                                    fg: c.textSecondary,
                                    bg: c.surfaceRaised,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.cwd} · ${s.branch}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: c.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${activeHost?.name ?? s.hostId} · ${s.model}',
                                  style: TextStyle(color: c.textMuted, fontSize: 11),
                                ),
                                Text(
                                  '${s.diffs > 0 ? '${s.diffs} diffs · ' : ''}${s.updatedAt}',
                                  style: TextStyle(color: c.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
