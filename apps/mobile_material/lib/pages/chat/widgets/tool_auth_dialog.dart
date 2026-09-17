import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// CHAT-TOOL-AUTH：Material AlertDialog 授权确认。
Future<bool> showToolAuthDialog({
  required BuildContext context,
  required ToolAuthPrompt prompt,
}) async {
  final title = prompt.toolTitle?.trim().isNotEmpty == true
      ? prompt.toolTitle!.trim()
      : prompt.toolName;
  final sideLabel = switch (prompt.sideEffect) {
    McpToolSideEffect.read => '读操作',
    McpToolSideEffect.write => '写操作',
    McpToolSideEffect.unknown => '副作用未声明',
  };
  final args = prompt.argumentsSummary?.trim();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final tokens = materialTokensOf(ctx);
      return AlertDialog(
        title: const Text('允许调用工具？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Server「${prompt.serverDisplayName}」请求调用工具「$title」。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: tokens.ink,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              const SizedBox(height: 12),
              _AuthMetaRow(label: '工具', value: prompt.toolName, tokens: tokens),
              const SizedBox(height: 6),
              _AuthMetaRow(label: '副作用', value: sideLabel, tokens: tokens),
              if (args != null && args.isNotEmpty) ...[
                const SizedBox(height: 6),
                _AuthMetaRow(label: '参数摘要', value: args, tokens: tokens),
              ],
              if (prompt.policyLevel == McpToolPolicyLevel.confirmOnce) ...[
                const SizedBox(height: 10),
                Text(
                  '本次允许后，本会话内同一工具可不再询问。',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('允许'),
          ),
        ],
      );
    },
  );
  return ok == true;
}

class _AuthMetaRow extends StatelessWidget {
  const _AuthMetaRow({
    required this.label,
    required this.value,
    required this.tokens,
  });

  final String label;
  final String value;
  final MaterialTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      ],
    );
  }
}
