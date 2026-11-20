import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Renders assistant responses with headings, lists, blockquotes, inline styles,
/// and syntax-highlighted fenced code blocks without external plugin dependencies.
class AgyMarkdownView extends StatelessWidget {
  final String data;

  const AgyMarkdownView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    final baseStyle = TextStyle(color: c.text, fontSize: 13.5, height: 1.5);
    final blocks = _parseBlocks(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildBlock(blocks[i], c, baseStyle),
        ],
      ],
    );
  }

  Widget _buildBlock(_MdBlock b, AppColors c, TextStyle baseStyle) {
    switch (b.kind) {
      case _MdKind.code:
        return AgyCodeBlock(code: b.text, title: b.meta.isEmpty ? 'code' : b.meta);
      case _MdKind.heading:
        final level = int.tryParse(b.meta) ?? 2;
        final size = switch (level) {
          1 => 17.5,
          2 => 15.5,
          _ => 14.2,
        };
        final style = baseStyle.copyWith(fontSize: size, fontWeight: FontWeight.w700, height: 1.35);
        return SelectableText.rich(
          TextSpan(style: style, children: parseInlineMarkdown(b.text, c, style)),
        );
      case _MdKind.quote:
        final quoteStyle = baseStyle.copyWith(color: c.textSecondary);
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
            border: Border(left: BorderSide(color: c.accent, width: 3)),
          ),
          child: SelectableText.rich(
            TextSpan(style: quoteStyle, children: parseInlineMarkdown(b.text, c, quoteStyle)),
          ),
        );
      case _MdKind.listItem:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text(
                b.meta,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ),
            Expanded(
              child: SelectableText.rich(
                TextSpan(style: baseStyle, children: parseInlineMarkdown(b.text, c, baseStyle)),
              ),
            ),
          ],
        );
      case _MdKind.paragraph:
        return SelectableText.rich(
          TextSpan(style: baseStyle, children: parseInlineMarkdown(b.text, c, baseStyle)),
        );
    }
  }
}

enum _MdKind { paragraph, heading, code, listItem, quote }

class _MdBlock {
  final _MdKind kind;
  final String text;
  final String meta;
  const _MdBlock(this.kind, this.text, [this.meta = '']);
}

List<_MdBlock> _parseBlocks(String input) {
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MdBlock>[];
  final paraBuf = <String>[];
  final quoteBuf = <String>[];

  var inFence = false;
  var fenceLang = '';
  final codeBuf = <String>[];

  void flushPara() {
    if (paraBuf.isNotEmpty) {
      blocks.add(_MdBlock(_MdKind.paragraph, paraBuf.join('\n').trimRight()));
      paraBuf.clear();
    }
  }

  void flushQuote() {
    if (quoteBuf.isNotEmpty) {
      blocks.add(_MdBlock(_MdKind.quote, quoteBuf.join('\n').trimRight()));
      quoteBuf.clear();
    }
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (inFence) {
      if (trimmed.startsWith('```')) {
        blocks.add(_MdBlock(_MdKind.code, codeBuf.join('\n'), fenceLang));
        codeBuf.clear();
        fenceLang = '';
        inFence = false;
      } else {
        codeBuf.add(line);
      }
      continue;
    }

    if (trimmed.startsWith('```')) {
      flushPara();
      flushQuote();
      inFence = true;
      fenceLang = trimmed.substring(3).trim();
      continue;
    }

    if (trimmed.isEmpty) {
      flushPara();
      flushQuote();
      continue;
    }

    if (trimmed.startsWith('>')) {
      flushPara();
      quoteBuf.add(trimmed.substring(1).trimLeft());
      continue;
    }
    flushQuote();

    final headingMatch = RegExp(r'^(#{1,4})\s+(.+)$').firstMatch(trimmed);
    if (headingMatch != null) {
      flushPara();
      blocks.add(_MdBlock(
        _MdKind.heading,
        headingMatch.group(2)!.trim(),
        '${headingMatch.group(1)!.length}',
      ));
      continue;
    }

    final bulletMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(line.trimLeft());
    if (bulletMatch != null) {
      flushPara();
      blocks.add(_MdBlock(_MdKind.listItem, bulletMatch.group(1)!, '•'));
      continue;
    }

    final numMatch = RegExp(r'^(\d+\.)\s+(.+)$').firstMatch(line.trimLeft());
    if (numMatch != null) {
      flushPara();
      blocks.add(_MdBlock(_MdKind.listItem, numMatch.group(2)!, numMatch.group(1)!));
      continue;
    }

    paraBuf.add(line);
  }

  if (inFence) {
    blocks.add(_MdBlock(_MdKind.code, codeBuf.join('\n'), fenceLang));
  }
  flushQuote();
  flushPara();
  return blocks;
}

List<InlineSpan> parseInlineMarkdown(String text, AppColors c, TextStyle baseStyle) {
  final pattern = RegExp(
    r'(`[^`\n]+`|\*\*[^*\n]+\*\*|\*[^*\n]+\*|\[[^\]\n]+\]\([^\)\n]+\))',
  );
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final m in pattern.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    final tok = m.group(0)!;
    if (tok.startsWith('`') && tok.endsWith('`') && tok.length >= 2) {
      spans.add(TextSpan(
        text: ' ${tok.substring(1, tok.length - 1)} ',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: (baseStyle.fontSize ?? 13.5) - 1,
          color: c.accent,
          backgroundColor: c.surfaceRaised,
        ),
      ));
    } else if (tok.startsWith('**') && tok.endsWith('**') && tok.length >= 4) {
      spans.add(TextSpan(
        text: tok.substring(2, tok.length - 2),
        style: baseStyle.copyWith(fontWeight: FontWeight.w700),
      ));
    } else if (tok.startsWith('*') && tok.endsWith('*') && tok.length >= 2) {
      spans.add(TextSpan(
        text: tok.substring(1, tok.length - 1),
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (tok.startsWith('[')) {
      final linkMatch = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(tok);
      if (linkMatch != null) {
        spans.add(TextSpan(
          text: linkMatch.group(1),
          style: baseStyle.copyWith(
            color: c.accent,
            decoration: TextDecoration.underline,
            decorationColor: c.accent,
          ),
        ));
      } else {
        spans.add(TextSpan(text: tok));
      }
    }
    cursor = m.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

/// Syntax-highlighted fenced code block with language badge and Copy button.
class AgyCodeBlock extends StatelessWidget {
  final String code;
  final String title;

  const AgyCodeBlock({
    super.key,
    required this.code,
    this.title = 'code',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.isNotEmpty ? title : 'code',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  child: const Text('Copy', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(11),
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.48,
                  color: Color(0xFFE2E8F0),
                ),
                children: highlightCode(code),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<TextSpan> highlightCode(String code) {
  final tokenRe = RegExp(
    r'(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*|"(?:\\.|[^"\\\n])*"|'
    r"'(?:\\.|[^'\\\n])*'|"
    r'`[^`]*`|@[A-Za-z_]\w*|\b\d+(?:\.\d+)?\b|'
    r'\b(?:func|package|import|return|if|else|for|range|switch|case|default|'
    r'type|struct|interface|var|const|go|defer|select|chan|map|nil|true|false|'
    r'class|extends|implements|with|final|late|async|await|Future|Stream|Widget|'
    r'void|bool|int|double|String|def|elif|from|as|try|except|finally|raise|pass|'
    r'lambda|fn|let|mut|pub|use|mod|function|export|null|undefined|new|this|super|'
    r'enum|break|continue)\b)',
  );

  final spans = <TextSpan>[];
  var cursor = 0;

  for (final m in tokenRe.allMatches(code)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: code.substring(cursor, m.start)));
    }
    final tok = m.group(0)!;
    Color color;
    if (tok.startsWith('//') || tok.startsWith('/*') || tok.startsWith('#')) {
      color = const Color(0xFF64748B);
    } else if (tok.startsWith('"') || tok.startsWith("'") || tok.startsWith('`')) {
      color = const Color(0xFF86EFAC);
    } else if (tok.startsWith('@')) {
      color = const Color(0xFFF472B6);
    } else if (RegExp(r'^\d').hasMatch(tok)) {
      color = const Color(0xFFFDBA74);
    } else {
      color = const Color(0xFF93C5FD);
    }
    spans.add(TextSpan(text: tok, style: TextStyle(color: color)));
    cursor = m.end;
  }

  if (cursor < code.length) {
    spans.add(TextSpan(text: code.substring(cursor)));
  }
  return spans;
}
