import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../pairing/pair_sheet.dart';
import 'diagnostics_sheet.dart';

class HostsScreen extends ConsumerWidget {
  const HostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);

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
                      'Paired Machines',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.hosts.length} Host(s)',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => showPairMachineSheet(context),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Pair'),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: state.hosts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dns_outlined, size: 44, color: c.textMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'No Paired Machines',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Run `agyd pair` on your VPS or PC, then tap Pair to scan its QR code or paste the URI.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: controller.refreshActiveHost,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: state.hosts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final host = state.hosts[idx];
                    final isActive = host.id == state.activeHostId;
                    return SurfaceCard(
                      borderColor: isActive ? c.accent : c.border,
                      onTap: () async {
                        await controller.selectHost(host.id);
                        controller.setNavTab(1);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: host.diagnostics.connected ? c.success : c.textMuted,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Flexible(
                                          child: Text(
                                            host.name,
                                            style: const TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (host.isDemo) ...[
                                          const SizedBox(width: 6),
                                          StatusBadge(
                                            label: 'Demo',
                                            fg: c.accent,
                                            bg: c.accentSoft,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${host.os} · ${host.agyVersion}',
                                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              ConnectionPill(
                                diagnostics: host.diagnostics,
                                onTap: () => showDiagnosticsSheet(context, host),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Row(
                            children: [
                              Expanded(child: _MiniMeter(label: 'CPU', percent: host.cpuPercent)),
                              const SizedBox(width: 12),
                              Expanded(child: _MiniMeter(label: 'RAM', percent: host.ramPercent)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(height: 1, color: c.border),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                host.runningCount > 0
                                    ? '${host.runningCount} running · ${state.pendingApprovalCount} approval'
                                    : 'Daemon healthy',
                                style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                              ),
                              Text(
                                '${host.peerId.substring(0, host.peerId.length.clamp(0, 14))}…',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: c.textMuted,
                                  fontSize: 11,
                                ),
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
    );
  }
}

class _MiniMeter extends StatelessWidget {
  final String label;
  final int percent;
  const _MiniMeter({required this.label, required this.percent});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
            Text('$percent%', style: TextStyle(color: c.textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: c.surfaceRaised,
            color: c.accent,
          ),
        ),
      ],
    );
  }
}
