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
        color: c.navBg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 10),
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
                    _AttachedChip(
                      label: '@$f',
                      onRemove: () => controller.removeWorkspaceFile(f),
                    ),
                  for (final up in state.stagedUploads)
                    _AttachedChip(
                      leading: up.isImage &&
                              up.localPath.isNotEmpty &&
                              File(up.localPath).existsSync()
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(
                                      File(up.localPath),
                                      width: 18,
                                      height: 18,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (up.uploading)
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(strokeWidth: 1.8),
                                    ),
                                ],
                              ),
                            )
                          : (up.uploading
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    value: up.progress > 0 ? up.progress : null,
                                    strokeWidth: 1.8,
                                  ),
                                )
                              : Icon(
                                  up.error != null ? Icons.error_outline : Icons.insert_drive_file_outlined,
                                  size: 13,
                                  color: up.error != null ? c.danger : c.accent,
                                )),
                      label: up.uploading
                          ? '${up.filename} ${(up.progress * 100).round()}%'
                          : up.error != null
                              ? '${up.filename} (failed)'
                              : up.filename,
                      isError: up.error != null,
                      tooltip: up.uploading ? 'Cancel upload' : 'Remove attachment',
                      onRemove: () => controller.removeStagedUpload(up),
                    ),
                ],
              ),
              const SizedBox(height: 7),
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
                    label: 'Attach',
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
                    primaryText: true,
                    onTap: () => showModeAndModelSheet(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: c.borderStrong),
              ),
              padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: 'Ask Antigravity on $hostName...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 13.5),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 5),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: state.isStreaming ? null : c.accentGradient,
                      color: state.isStreaming ? c.danger : null,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: state.isStreaming
                            ? () => controller.cancelTurn()
                            : _submit,
                        child: Icon(
                          state.isStreaming ? Icons.stop : Icons.arrow_upward,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
  final bool primaryText;
  final VoidCallback onTap;

  const _MiniToolChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.accent = false,
    this.primaryText = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = accent ? c.accent : (primaryText ? c.text : c.textSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent ? c.accent.withValues(alpha: 0.25) : c.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
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

class _AttachedChip extends StatelessWidget {
  final Widget? leading;
  final String label;
  final bool isError;
  final String tooltip;
  final VoidCallback onRemove;

  const _AttachedChip({
    this.leading,
    required this.label,
    this.isError = false,
    this.tooltip = 'Remove attachment',
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = isError ? c.dangerSoft : c.accentSoft;
    final fg = isError ? c.danger : c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Icon(Icons.close, size: 13, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
