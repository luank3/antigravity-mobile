import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';

Future<void> showSlashCommandSheet(
  BuildContext context,
  void Function(String command) onPick,
) {
  const defaultCommands = [
    ('/plan', 'Switch to planning mode before editing files'),
    ('/compact', 'Summarize context to free up session window'),
    ('/goal', 'Run autonomously until verification passes'),
    ('/grill-me', 'Interactive interview to resolve design edge cases'),
    ('/boost', 'Enable deep verification & multi-angle checks'),
    ('/schedule', 'Create a recurring cron or delayed timer'),
  ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.colors;
      return Consumer(builder: (ctx, ref, _) {
        final live = ref.watch(appControllerProvider).availableCommands;
        final items = live.isNotEmpty
            ? live
                .map((cmd) => (
                      cmd.name.startsWith('/') ? cmd.name : '/${cmd.name}',
                      cmd.description,
                    ))
                .toList()
            : defaultCommands;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: c.borderStrong)),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              const Text('Slash Commands', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final item in items)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(item.$1, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                  subtitle: Text(item.$2, style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onPick(item.$1);
                  },
                ),
            ],
          ),
        );
      });
    },
  );
}

Future<void> showRemoteFilePickerSheet(BuildContext context, WidgetRef ref) {
  final files = ref.read(appControllerProvider).workspaceFiles;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.colors;
      return Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: c.borderStrong)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            const Text('Attach Remote Workspace File (@)', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final f in files)
              ListTile(
                title: Text(f.path, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                trailing: Text('@ Add', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                onTap: () {
                  ref.read(appControllerProvider.notifier).attachWorkspaceFile(f.path);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> showModeAndModelSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.colors;
      final appState = ref.watch(appControllerProvider);
      final session = appState.activeSession;
      final currentMode = session?.mode ?? 'Auto';
      final currentModel = session?.model ?? 'Neon High';

      final modeChoices = appState.availableModes.isNotEmpty
          ? appState.availableModes.map((m) => (m.id, m.name)).toList()
          : const [('auto', 'Auto'), ('plan', 'Plan'), ('accept-edits', 'Accept Edits')];
      final modelChoices = appState.availableModels.isNotEmpty
          ? appState.availableModels.map((m) => (m.id, m.name)).toList()
          : const [
              ('Neon High', 'Neon High'),
              ('Orch Neon', 'Orch Neon'),
              ('Opus 5.5', 'Opus 5.5'),
              ('Flash 3.8', 'Flash 3.8'),
            ];

      return Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: c.borderStrong)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Mode & Model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('EXECUTION MODE', style: TextStyle(color: c.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: modeChoices.map((m) {
                  final selected = currentMode.toLowerCase() == m.$1.toLowerCase() ||
                      currentMode.toLowerCase() == m.$2.toLowerCase();
                  return ChoiceChip(
                    label: Text(m.$2),
                    selected: selected,
                    onSelected: (_) {
                      ref.read(appControllerProvider.notifier).updateSessionModeAndModel(mode: m.$1);
                      Navigator.of(ctx).pop();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('MODEL', style: TextStyle(color: c.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final model in modelChoices)
                ListTile(
                  dense: true,
                  title: Text(model.$2),
                  trailing: (currentModel == model.$1 || currentModel == model.$2)
                      ? Icon(Icons.check, color: c.accent)
                      : null,
                  onTap: () {
                    ref.read(appControllerProvider.notifier).updateSessionModeAndModel(model: model.$1);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showUploadTmpPickerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.colors;
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: c.borderStrong)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Upload Device File to Remote /tmp', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Files stream via Noise XX /agy/blob/1.0.0 into /tmp/agyd-uploads/<session>/ and are attached to this prompt.',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.insert_drive_file_outlined, color: c.accent),
              title: const Text('Pick Any File from Device'),
              subtitle: const Text('Logs, JSON, source files, PDFs, archives'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final file = await FilePicker.pickFile();
                if (file != null && file.path != null) {
                  await ref.read(appControllerProvider.notifier).uploadLocalFile(
                        localPath: file.path!,
                        filename: file.name,
                      );
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: c.accentIndigo),
              title: const Text('Pick Photo or Screenshot'),
              subtitle: const Text('Sent as ACP image block + staged in /tmp'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (img != null) {
                  await ref.read(appControllerProvider.notifier).uploadLocalFile(
                        localPath: img.path,
                        filename: img.name,
                        mimeType: 'image/jpeg',
                      );
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
