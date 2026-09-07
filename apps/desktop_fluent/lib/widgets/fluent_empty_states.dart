import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 桌面端全页空态（未配置提供商等）：短文案 + 主按钮。
class FluentFeatureEmpty extends StatelessWidget {
  const FluentFeatureEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ColoredBox(
      color: tokens.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  button: true,
                  label: actionLabel,
                  excludeSemantics: true,
                  child: FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 左窗格会话列表空态：文案 +「新建会话」。
class FluentSessionListEmpty extends StatelessWidget {
  const FluentSessionListEmpty({
    super.key,
    required this.onCreate,
    this.message = '还没有会话，新建一条开始使用。',
  });

  final VoidCallback onCreate;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '暂无会话',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: '新建会话',
              excludeSemantics: true,
              child: Button(
                onPressed: onCreate,
                child: const Text('新建会话'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 内容区简洁空提示（消息 / 时间线 / 队列）。
class FluentContentEmpty extends StatelessWidget {
  const FluentContentEmpty({
    super.key,
    required this.hint,
    this.subtitle,
  });

  final String hint;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 设置 · 提供商列表空态（顶栏已有添加时可弱引导）。
class FluentProvidersListEmpty extends StatelessWidget {
  const FluentProvidersListEmpty({
    super.key,
    this.onAdd,
  });

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '暂无提供商',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '添加 OpenAI / xAI 或兼容源后即可对话与生成。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
              ),
            ),
            if (onAdd != null) ...[
              const SizedBox(height: 12),
              Button(
                onPressed: onAdd,
                child: const Text('添加'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
