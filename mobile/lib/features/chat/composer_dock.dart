import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import 'chat_sheets.dart';

class ComposerDock extends ConsumerStatefulWidget {
  const ComposerDock({super.key});

  @override
  ConsumerState<ComposerDock> createState() => _ComposerDockState();
}

class _ComposerDockState extends ConsumerState<ComposerDock> {
  final _inputCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _inputCtrl.text;
    _inputCtrl.clear();
    await ref.read(appControllerProvider.notifier).sendPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final session = state.activeSession;
    final hostName = state.activeHost?.name ?? 'remote host';

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.attachedWorkspaceFiles.isNotEmpty || state.stagedUploads.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in state.attachedWorkspaceFiles)
                    InputChip(
                      label: Text('@$f', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onDeleted: () => controller.removeWorkspaceFile(f),
                    ),
                  for (final up in state.stagedUploads)
                    InputChip(
                      avatar: up.isImage &&
                              up.localPath.isNotEmpty &&
                              File(up.localPath).existsSync()
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: Image.file(
                                      File(up.localPath),
                                      width: 22,
                                      height: 22,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (up.uploading)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                ],
                              ),
                            )
                          : (up.uploading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    value: up.progress > 0 ? up.progress : null,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  up.error != null ? Icons.error_outline : Icons.upload_file,
                                  size: 15,
                                  color: up.error != null ? c.danger : c.success,
                                )),
                      label: Text(
                        up.uploading
                            ? '${up.filename} ${(up.progress * 100).round()}%'
                            : up.error != null
                                ? '${up.filename} (failed)'
                                : '${up.filename} (/tmp)',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      deleteButtonTooltipMessage:
                          up.uploading ? 'Cancel upload' : 'Remove attachment',
                      onDeleted: () => controller.removeStagedUpload(up),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _MiniToolChip(
                    label: '/ Slash',
                    onTap: () => showSlashCommandSheet(context, (cmd) {
                      _inputCtrl.text = '$cmd ${_inputCtrl.text}';
                    }),
                  ),
                  const SizedBox(width: 5),
                  _MiniToolChip(
                    label: '@ File',
                    onTap: () => showRemoteFilePickerSheet(context, ref),
                  ),
                  const SizedBox(width: 5),
                  _MiniToolChip(
                    icon: Icons.attach_file,
                    label: 'Upload /tmp',
                    onTap: () => showUploadTmpPickerSheet(context, ref),
                  ),
                  const SizedBox(width: 8),
                  _MiniToolChip(
                    label: '${session?.mode ?? 'Auto'} ▾',
                    accent: true,
                    onTap: () => showModeAndModelSheet(context, ref),
                  ),
                  const SizedBox(width: 5),
                  _MiniToolChip(
                    label: '${session?.model ?? 'Neon High'} ▾',
                    onTap: () => showModeAndModelSheet(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: c.borderStrong),
              ),
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: 'Ask Antigravity on $hostName...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: state.isStreaming ? c.danger : c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    icon: Icon(state.isStreaming ? Icons.stop : Icons.arrow_upward, size: 19),
                    onPressed: state.isStreaming
                        ? () => controller.cancelTurn()
                        : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniToolChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool accent;
  final VoidCallback onTap;

  const _MiniToolChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: accent ? c.accentSoft : c.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent ? c.accent.withValues(alpha: 0.35) : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: accent ? c.accent : c.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: accent ? c.accent : c.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
