import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import 'markdown_body.dart';

class ChatMessageTile extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback onToggleThink;
  final void Function(String filePath, List<String> lines) onViewDiff;
  final void Function(PermissionStatus decision, {String? optionId}) onResolvePermission;

  const ChatMessageTile({
    super.key,
    required this.msg,
    required this.onToggleThink,
    required this.onViewDiff,
    required this.onResolvePermission,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return switch (msg.kind) {
      ChatMessageKind.user => _buildUser(context, c),
      ChatMessageKind.thinking => _buildThinking(c),
      ChatMessageKind.plan => _buildPlan(c),
      ChatMessageKind.toolRead => _buildToolRead(c),
      ChatMessageKind.toolEdit => _buildToolEdit(c),
      ChatMessageKind.terminal => _buildTerminal(c),
      ChatMessageKind.assistant => _buildAssistant(context, c),
      ChatMessageKind.permission => _buildPermission(c),
    };
  }

  Widget _buildUser(BuildContext context, AppColors c) {
    final existingImages = msg.imagePaths.where((p) => p.isNotEmpty && File(p).existsSync()).toList();
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF4338CA)]),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (existingImages.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: existingImages
                    .map((path) => GestureDetector(
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(16),
                                child: InteractiveViewer(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(File(path)),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(path),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              msg.text,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.42),
            ),
            if (msg.chips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: msg.chips
                    .map((chip) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            chip,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.white,
                              fontSize: 10.5,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThinking(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleThink,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accentIndigo,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      msg.streaming ? 'Thinking...' : 'Thought for ${msg.duration}',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    msg.expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (msg.expanded && (msg.thinkingSteps.isNotEmpty || msg.text.isNotEmpty)) ...[
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: msg.thinkingSteps.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: msg.thinkingSteps
                          .map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $s',
                                  style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
                                ),
                              ))
                          .toList(),
                    )
                  : Text(
                      msg.text,
                      style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlan(AppColors c) {
    final pct = msg.planTotal > 0 ? (msg.planCurrent / msg.planTotal).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Plan · ${msg.text}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              StatusBadge(
                label: '${msg.planCurrent} / ${msg.planTotal}',
                fg: c.accent,
                bg: c.accentSoft,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: c.surfaceRaised,
              color: c.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRead(AppColors c) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 14, color: c.success),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Read ${msg.filePath}${msg.detail.isNotEmpty ? ' · ${msg.detail}' : ''}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: c.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolEdit(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 15, color: c.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    msg.filePath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+${msg.additions}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: c.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '-${msg.deletions}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: c.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: c.codeBg,
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: msg.diffLines.map((line) {
                  Color fg = const Color(0xFFCBD5E1);
                  Color? bg;
                  if (line.startsWith('+')) {
                    fg = const Color(0xFF86EFAC);
                    bg = const Color(0x2422C55E);
                  } else if (line.startsWith('-')) {
                    fg = const Color(0xFFFCA5A5);
                    bg = const Color(0x24EF4444);
                  }
                  return Container(
                    color: bg,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                        color: fg,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onViewDiff(msg.filePath, msg.diffLines),
              child: const Text('View full diff →', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '\$ ${msg.command}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFE2E8F0),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  msg.detail,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: Text(
              msg.text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistant(BuildContext context, AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgyMarkdownView(data: msg.text),
        if (msg.code.isNotEmpty) ...[
          const SizedBox(height: 8),
          AgyCodeBlock(code: msg.code, title: msg.codeTitle),
        ],
      ],
    );
  }

  Widget _buildPermission(AppColors c) {
    final isPending = msg.permStatus == PermissionStatus.pending;
    final isDenied = msg.permStatus == PermissionStatus.denied;
    final borderColor = isPending
        ? c.warning.withValues(alpha: 0.7)
        : isDenied
            ? c.danger.withValues(alpha: 0.5)
            : c.success.withValues(alpha: 0.5);
    final headerColor = isPending ? c.warning : (isDenied ? c.danger : c.success);
    final badgeLabel = switch (msg.permStatus) {
      PermissionStatus.pending => 'Pending',
      PermissionStatus.allowedOnce => 'Allowed Once',
      PermissionStatus.allowedAlways => 'Always Allowed',
      PermissionStatus.denied => 'Denied',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isPending ? Icons.bolt : (isDenied ? Icons.close : Icons.check_circle),
                size: 17,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Approval Required · Tool Permission',
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusBadge(
                label: badgeLabel,
                fg: headerColor,
                bg: isPending ? c.warningSoft : (isDenied ? c.dangerSoft : c.successSoft),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: c.codeBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '\$ ${msg.command}',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFFF8FAFC),
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'cwd: ${msg.cwd} · Sandbox: ${msg.sandbox}',
            style: TextStyle(fontFamily: 'monospace', color: c.textSecondary, fontSize: 11),
          ),
          if (isPending) ...[
            const SizedBox(height: 10),
            if (msg.permOptions.isNotEmpty)
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: msg.permOptions.map((opt) {
                  final optId = opt['optionId'] ?? '';
                  final optName = opt['name'] ?? optId;
                  final optKind = opt['kind'] ?? '';
                  final isReject = optKind.contains('reject') || optId.contains('reject');
                  final isAlways = optKind.contains('always') || optId.contains('always');
                  final decision = isReject
                      ? PermissionStatus.denied
                      : (isAlways ? PermissionStatus.allowedAlways : PermissionStatus.allowedOnce);
                  return FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: isReject
                          ? c.dangerSoft
                          : (isAlways ? c.success : c.surfaceRaised),
                      foregroundColor: isReject
                          ? c.danger
                          : (isAlways ? Colors.white : c.text),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    ),
                    onPressed: () => onResolvePermission(decision, optionId: optId),
                    child: Text(optName, style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.dangerSoft,
                        foregroundColor: c.danger,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => onResolvePermission(PermissionStatus.denied),
                      child: const Text('Deny', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => onResolvePermission(PermissionStatus.allowedOnce),
                      child: const Text('Allow Once', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => onResolvePermission(PermissionStatus.allowedAlways),
                      child: const Text('Always Allow', style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
