import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showAddRelay = false;
  final _relayCtrl = TextEditingController();

  @override
  void dispose() {
    _relayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      'Settings',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                    ),

                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DEVICE IDENTITY',
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        StatusBadge(
                          label: state.nodeError == null ? 'Online' : 'Init Error',
                          fg: state.nodeError == null ? c.success : c.danger,
                          bg: state.nodeError == null ? c.successSoft : c.dangerSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.surfaceRaised,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.mobilePeerId.isNotEmpty
                                  ? state.mobilePeerId
                                  : (state.nodeError ?? 'Starting libp2p node...'),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: c.accent,
                                fontSize: 11.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: state.mobilePeerId.isEmpty
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: state.mobilePeerId));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Mobile PeerID copied')),
                                    );
                                  },
                            child: const Text('Copy', style: TextStyle(fontSize: 11.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionTitle(kDebugMode ? 'Appearance & Preview' : 'Appearance'),
              const SizedBox(height: 6),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Orbital Carbon Dark Mode', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      value: state.isDarkTheme,
                      onChanged: (_) => controller.toggleTheme(),
                    ),
                    if (kDebugMode) ...[
                      Divider(height: 1, color: c.border),
                      SwitchListTile(
                        title: const Text('Show Preview Demo Host', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text('Includes simulated host alongside paired machines', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                        value: state.showDemoHost,
                        onChanged: controller.toggleDemoHost,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionTitle('NAT & Relay Preferences'),
              const SizedBox(height: 6),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Prefer LAN mDNS', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Connect directly when on the same Wi-Fi network', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.preferMdns,
                      onChanged: (v) => controller.setPreference(preferMdns: v),
                    ),
                    Divider(height: 1, color: c.border),
                    SwitchListTile(
                      title: const Text('Direct P2P Hole Punching', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Upgrade relayed links to direct peer-to-peer', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.enableDcutr,
                      onChanged: (v) => controller.setPreference(enableDcutr: v),
                    ),
                    Divider(height: 1, color: c.border),
                    SwitchListTile(
                      title: const Text('AutoRelay Fallback', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Route via relay servers when behind firewalls', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.enableAutoRelay,
                      onChanged: (v) => controller.setPreference(enableAutoRelay: v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionTitle('Background & Notifications'),
              const SizedBox(height: 6),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Foreground Keepalive Service', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Keep libp2p connection alive while app is backgrounded', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.enableForegroundService,
                      onChanged: (v) {
                        if (v) unawaited(controller.requestNotificationPermission());
                        controller.setPreference(enableForegroundService: v);
                      },
                    ),
                    Divider(height: 1, color: c.border),
                    SwitchListTile(
                      title: const Text('Permission Approval Alerts', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Notify when an agent pauses for command approval', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.notifPermissions,
                      onChanged: (v) {
                        if (v) unawaited(controller.requestNotificationPermission());
                        controller.setPreference(notifPermissions: v);
                      },
                    ),
                    Divider(height: 1, color: c.border),
                    SwitchListTile(
                      title: const Text('Task Completion Alerts', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Notify when an agent turn finishes or errors in background', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.notifCompletion,
                      onChanged: (v) {
                        if (v) unawaited(controller.requestNotificationPermission());
                        controller.setPreference(notifCompletion: v);
                      },
                    ),
                    Divider(height: 1, color: c.border),
                    SwitchListTile(
                      title: const Text('Keep Screen Awake While Streaming', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Hold WakeLock & screen-on flag during active turns', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      value: state.keepAwake,
                      onChanged: (v) => controller.setPreference(keepAwake: v),
                    ),
                    Divider(height: 1, color: c.border),
                    ListTile(
                      title: const Text('Send Test Alert', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Verify Android notification permission & alert sound', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          await controller.sendTestNotification();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(content: Text('Test notification sent')),
                            );
                        },
                        child: const Text('Test', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _SectionTitle('Self-Hosted Relays')),
                  if (state.relays.isNotEmpty)
                    TextButton(
                      onPressed: state.probingRelays ? null : controller.probeRelays,
                      child: Text(state.probingRelays ? 'Probing...' : 'Probe'),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _showAddRelay = !_showAddRelay),
                    child: Text(_showAddRelay ? 'Cancel' : '+ Add Relay'),
                  ),
                ],
              ),
              if (_showAddRelay) ...[
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _relayCtrl,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                        decoration: const InputDecoration(
                          labelText: 'Relay Multiaddr',
                          hintText: '/dns4/relay.example.com/udp/4001/quic-v1/p2p/12D3...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          await controller.addRelay(_relayCtrl.text);
                          _relayCtrl.clear();
                          if (mounted) setState(() => _showAddRelay = false);
                        },
                        child: const Text('Save Relay Multiaddr'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: state.relays.isEmpty
                    ? ListTile(
                        title: const Text('No self-hosted relays configured', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'Tap + Add Relay or pair a host to import its agy-relay multiaddr.',
                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < state.relays.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: c.border),
                            ListTile(
                              title: Text(state.relays[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                state.relays[i].multiaddr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusBadge(
                                    label: state.relays[i].status,
                                    fg: state.relays[i].online ? c.success : c.danger,
                                    bg: state.relays[i].online ? c.successSoft : c.dangerSoft,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 16, color: c.textMuted),
                                    tooltip: 'Remove relay',
                                    onPressed: () => controller.removeRelay(state.relays[i].multiaddr),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _SectionTitle('Paired Hosts'),
              const SizedBox(height: 6),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < state.hosts.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: c.border),
                      ListTile(
                        title: Text(state.hosts[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          state.hosts[i].peerId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                        trailing: state.hosts[i].isDemo
                            ? StatusBadge(label: 'Demo', fg: c.accent, bg: c.accentSoft)
                            : OutlinedButton(
                                onPressed: () => controller.removeHost(state.hosts[i].id),
                                child: const Text('Remove', style: TextStyle(fontSize: 11.5)),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              if (state.authorizedPeers.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SectionTitle('Authorized Peers on ${state.activeHost?.name ?? 'Host'}'),
                const SizedBox(height: 6),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < state.authorizedPeers.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: c.border),
                        ListTile(
                          title: Text(state.authorizedPeers[i].deviceName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            state.authorizedPeers[i].peerId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                          trailing: state.authorizedPeers[i].peerId == state.mobilePeerId
                              ? StatusBadge(label: 'This Device', fg: c.accent, bg: c.accentSoft)
                              : OutlinedButton(
                                  onPressed: () => controller.revokeAuthorizedPeer(state.authorizedPeers[i].peerId),
                                  child: const Text('Revoke', style: TextStyle(fontSize: 11.5)),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.colors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}
