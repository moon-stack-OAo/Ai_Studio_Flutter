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
    this.illustration,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final Widget? illustration;

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
            child: _FluentEmptyAppear(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (illustration != null) ...[
                    illustration!,
                    const SizedBox(height: 16),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
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
      ),
    );
  }
}

/// 左窗格会话列表空态：文案 +「新建会话」。
class FluentSessionListEmpty extends StatelessWidget {
  const FluentSessionListEmpty({
    super.key,
    required this.onCreate,
    this.title = '暂无会话',
    this.message = '还没有会话，新建一条开始。',
    this.actionLabel = '新建会话',
    this.illustration,
  });

  final VoidCallback onCreate;
  final String title;
  final String message;
  final String actionLabel;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _FluentEmptyAppear(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 10),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
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
                label: actionLabel,
                excludeSemantics: true,
                child: Button(
                  onPressed: onCreate,
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
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
    this.illustration,
  });

  final String hint;
  final String? subtitle;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: _FluentEmptyAppear(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 10),
              ],
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
      ),
    );
  }
}

/// 设置 · 提供商列表空态（顶栏已有添加时可弱引导）。
class FluentProvidersListEmpty extends StatelessWidget {
  const FluentProvidersListEmpty({
    super.key,
    this.onAdd,
    this.illustration,
  });

  final VoidCallback? onAdd;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: _FluentEmptyAppear(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 10),
              ],
              Text(
                '暂无提供商',
                textAlign: TextAlign.center,
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
      ),
    );
  }
}

class _FluentEmptyAppear extends StatefulWidget {
  const _FluentEmptyAppear({required this.child});

  final Widget child;

  @override
  State<_FluentEmptyAppear> createState() => _FluentEmptyAppearState();
}

class _FluentEmptyAppearState extends State<_FluentEmptyAppear> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: FluentMotion.listAppear,
      curve: FluentMotion.standard,
      child: widget.child,
    );
  }
}
