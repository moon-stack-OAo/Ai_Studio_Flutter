import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// CHAT-MD Material 包装：助手气泡 Markdown + 代码块复制。
class MarkdownHost extends StatelessWidget {
  const MarkdownHost({
    super.key,
    required this.data,
    this.error = false,
  });

  final String data;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final ink = error ? tokens.danger : tokens.ink;
    final base = TextStyle(
      fontSize: 14,
      height: 1.55,
      color: ink,
      fontFamily: tokens.fontFamily,
    );

    if (data.isEmpty) {
      return Text(
        '…',
        style: base.copyWith(color: tokens.inkMuted),
      );
    }

    final styleSheet = MarkdownStyleSheet(
      p: base,
      a: base.copyWith(
        color: tokens.primary,
        decoration: TextDecoration.underline,
      ),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
      h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
      h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      h4: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      h5: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      h6: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      listBullet: base,
      tableHead: base.copyWith(fontWeight: FontWeight.w600),
      tableBody: base,
      blockquote: base.copyWith(color: tokens.inkSecondary),
      blockquoteDecoration: BoxDecoration(
        color: tokens.surfaceMuted,
        border: Border(
          left: BorderSide(color: tokens.border, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      code: TextStyle(
        fontSize: 13,
        height: 1.45,
        color: ink,
        backgroundColor: tokens.surfaceMuted,
      ).withMonoFont(tokens),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      blockSpacing: 10,
      listIndent: 24,
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      softLineBreak: true,
      styleSheet: styleSheet,
      builders: {
        'pre': _CodeBlockBuilder(tokens: tokens),
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.tokens});

  final MaterialTokens tokens;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    var language = '';
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'code') {
          final clazz = child.attributes['class'] ?? '';
          if (clazz.startsWith('language-')) {
            language = clazz.substring('language-'.length);
          }
          break;
        }
      }
    }

    return _CodeBlockCard(
      code: code,
      language: language,
      tokens: tokens,
    );
  }
}

class _CodeBlockCard extends StatelessWidget {
  const _CodeBlockCard({
    required this.code,
    required this.language,
    required this.tokens,
  });

  final String code;
  final String language;
  final MaterialTokens tokens;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制代码')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _copy(context),
                  child: const Text('复制'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(
              code.trimRight(),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: tokens.ink,
              ).withMonoFont(tokens),
            ),
          ),
        ],
      ),
    );
  }
}
