import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';

Future<void> showDiagnosticsSheet(BuildContext context, PairedHost host) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DiagnosticsSheetContent(hostId: host.id),
  );
}

class _DiagnosticsSheetContent extends ConsumerStatefulWidget {
  final String hostId;
  const _DiagnosticsSheetContent({required this.hostId});

  @override
  ConsumerState<_DiagnosticsSheetContent> createState() => _DiagnosticsSheetContentState();
}

class _DiagnosticsSheetContentState extends ConsumerState<_DiagnosticsSheetContent> {
  bool _retrying = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final host = state.hosts.firstWhere(
      (h) => h.id == widget.hostId,
      orElse: () => state.hosts.first,
    );
    final d = host.diagnostics;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: c.borderStrong)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Diagnostics',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${host.name} · ${host.agyVersion}',
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  _HopNode(icon: Icons.smartphone, label: 'Mobile', sub: 'Android'),
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: d.isRelayed ? c.warning : c.success,
                    ),
                  ),
                  if (d.isRelayed) ...[
                    _HopNode(icon: Icons.hub_outlined, label: 'agy-relay', sub: 'Circuit v2'),
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: c.accent,
                      ),
                    ),
                  ],
                  _HopNode(
                    icon: Icons.dns_outlined,
                    label: host.name,
                    sub: d.isRelayed ? 'Sym NAT' : d.pathType.toUpperCase(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                _DiagTile(
                  label: 'HOST PEER ID',
                  value: '${host.peerId.substring(0, host.peerId.length.clamp(0, 14))}…',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: host.peerId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Host PeerID copied')),
                    );
                  },
                ),
                _DiagTile(
                  label: 'PATH TYPE',
                  value: d.isRelayed ? 'Circuit Relay v2' : d.pathType.toUpperCase(),
                ),
                _DiagTile(
                  label: 'TRANSPORT',
                  value: d.transport.isNotEmpty ? d.transport : 'QUIC v1 · Noise XX',
                ),
                _DiagTile(
                  label: 'LIVE RTT',
                  value: d.rttMs > 0 ? '${d.rttMs} ms' : 'Measuring',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.successSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, size: 18, color: c.success),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'End-to-end encrypted via libp2p Noise XX (Ed25519). Relays only forward opaque ciphertext.',
                      style: TextStyle(color: c.success, fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _retrying
                  ? null
                  : () async {
                      setState(() {
                        _retrying = true;
                        _statusMessage = null;
                      });
                      final res = await ref
                          .read(appControllerProvider.notifier)
                          .retryHolePunch(host.id);
                      if (mounted) {
                        setState(() {
                          _retrying = false;
                          _statusMessage = res.message;
                        });
                      }
                    },
              child: Text(_retrying ? 'Attempting DCUtR Hole-Punch...' : 'Retry DCUtR Hole-Punch'),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HopNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  const _HopNode({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.borderStrong),
          ),
          child: Icon(icon, size: 18, color: c.accent),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          sub,
          style: TextStyle(fontFamily: 'monospace', fontSize: 9.5, color: c.textMuted),
        ),
      ],
    );
  }
}

class _DiagTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _DiagTile({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
