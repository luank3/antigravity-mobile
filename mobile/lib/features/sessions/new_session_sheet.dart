import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';

Future<bool> showNewSessionSheet(BuildContext context) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _NewSessionSheet(),
  );
  return created == true;
}

class _NewSessionSheet extends ConsumerStatefulWidget {
  const _NewSessionSheet();

  @override
  ConsumerState<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends ConsumerState<_NewSessionSheet> {
  final _cwdCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  String _mode = 'Auto';
  String _model = 'Neon High';
  bool _sandbox = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appControllerProvider);
    final host = state.activeHost;
    final defaultCwd = (host != null && host.workspaceRoots.isNotEmpty)
        ? host.workspaceRoots.first
        : (state.activeSession?.cwd.isNotEmpty == true
            ? state.activeSession!.cwd
            : '~/dev/antigravity-mobile');
    _cwdCtrl.text = defaultCwd;
    if (state.availableModes.isNotEmpty) {
      _mode = state.availableModes.first.id;
    }
    if (state.availableModels.isNotEmpty) {
      _model = state.availableModels.first.id;
    }
  }

  @override
  void dispose() {
    _cwdCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final host = state.activeHost;
    final roots = host?.workspaceRoots ?? const <String>[];

    final modeItems = state.availableModes.isNotEmpty
        ? state.availableModes.map((m) => (m.id, m.name)).toList()
        : const [
            ('Auto', 'Auto'),
            ('Plan', 'Plan'),
            ('Accept Edits', 'Accept Edits'),
          ];
    final effectiveMode = modeItems.any((e) => e.$1 == _mode) ? _mode : modeItems.first.$1;

    final modelItems = state.availableModels.isNotEmpty
        ? state.availableModels.map((m) => (m.id, m.name)).toList()
        : const [
            ('Neon High', 'Neon High'),
            ('Orch Neon', 'Orch Neon'),
            ('Opus 5.5', 'Opus 5.5'),
            ('Flash 3.8', 'Flash 3.8'),
          ];
    final effectiveModel = modelItems.any((e) => e.$1 == _model) ? _model : modelItems.first.$1;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
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
                          'New ACP Session',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'On ${host?.name ?? 'Remote Host'}',
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              if (roots.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'ALLOWED WORKSPACE ROOTS',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: roots.map((root) {
                    return ChoiceChip(
                      label: Text(
                        root,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                      ),
                      selected: _cwdCtrl.text.trim() == root,
                      onSelected: (_) => setState(() => _cwdCtrl.text = root),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _cwdCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: 'Remote Workspace Folder (cwd)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Session Title (Optional)',
                  hintText: 'e.g., Fix Circuit Relay v2 timeouts',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: effectiveMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Mode',
                        border: OutlineInputBorder(),
                      ),
                      items: modeItems
                          .map((m) => DropdownMenuItem(
                                value: m.$1,
                                child: Text(m.$2, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _mode = v ?? modeItems.first.$1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: effectiveModel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(),
                      ),
                      items: modelItems
                          .map((m) => DropdownMenuItem(
                                value: m.$1,
                                child: Text(m.$2, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _model = v ?? modelItems.first.$1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Terminal Sandbox (--sandbox)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text('Restrict shell commands to workspace', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                value: _sandbox,
                onChanged: (v) => setState(() => _sandbox = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _creating
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        setState(() => _creating = true);
                        await ref.read(appControllerProvider.notifier).createNewSession(
                              cwd: _cwdCtrl.text.trim().isEmpty ? '~' : _cwdCtrl.text.trim(),
                              title: _titleCtrl.text,
                              mode: effectiveMode,
                              model: effectiveModel,
                              sandbox: _sandbox,
                            );
                        if (!mounted) return;
                        nav.pop(true);
                      },
                child: Text(_creating ? 'Starting ACP session...' : 'Create & Open Session'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
