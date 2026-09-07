import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// CHAT-MD Fluent 包装：助手气泡 Markdown + 代码块角标复制。
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
    final tokens = fluentTokensOf(context);
    final ink = error ? tokens.danger : tokens.ink;
    final base = TextStyle(
      fontSize: 14,
      height: 1.65,
      color: ink,
      fontFamily: tokens.fontFamily,
    );

    if (data.isEmpty) {
      return const SizedBox.shrink();
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
        fontSize: 12.5,
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

  final FluentTokens tokens;

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
  final FluentTokens tokens;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('已复制代码'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // OD：深色 IDE 代码块（亮暗主题均用近黑底）
    const blockBg = Color(0xFF1E1E1C);
    const headBg = Color(0xFF2A2926);
    const codeInk = Color(0xFFECEAE4);
    const metaInk = Color(0xFFA8A49C);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            color: headBg,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    style: TextStyle(
                      fontSize: 11,
                      color: metaInk,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                HyperlinkButton(
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
                fontSize: 12.5,
                height: 1.55,
                color: codeInk,
              ).withMonoFont(tokens),
            ),
          ),
        ],
      ),
    );
  }
}
