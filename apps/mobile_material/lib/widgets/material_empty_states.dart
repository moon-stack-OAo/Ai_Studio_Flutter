import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// 移动端全页空态（未配置提供商等）：竖向 CTA。
class MaterialFeatureEmpty extends StatelessWidget {
  const MaterialFeatureEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
    this.appBarTitle,
    this.illustration,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? appBarTitle;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _MaterialEmptyAppear(
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
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  label: actionLabel,
                  excludeSemantics: true,
                  child: FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 48),
                    ),
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (appBarTitle == null) {
      return ColoredBox(color: tokens.canvas, child: body);
    }

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(title: Text(appBarTitle!)),
      body: body,
    );
  }
}

/// 会话列表空态：文案 + 竖向「新建会话」。
class MaterialSessionListEmpty extends StatelessWidget {
  const MaterialSessionListEmpty({
    super.key,
    required this.onCreate,
    this.title = '暂无会话',
    this.message = '还没有会话，点下方新建一条开始。',
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
    final tokens = materialTokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 88),
        child: _MaterialEmptyAppear(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 12),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
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
                  fontSize: 14,
                  height: 1.45,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                button: true,
                label: actionLabel,
                excludeSemantics: true,
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 48),
                  ),
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
class MaterialContentEmpty extends StatelessWidget {
  const MaterialContentEmpty({
    super.key,
    required this.hint,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    this.illustration,
  });

  final String hint;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Padding(
      padding: padding,
      child: Center(
        child: _MaterialEmptyAppear(
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
                  fontSize: 14,
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
                    fontSize: 13,
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

/// 设置 · 提供商列表空态。
class MaterialProvidersListEmpty extends StatelessWidget {
  const MaterialProvidersListEmpty({
    super.key,
    this.onAdd,
    this.illustration,
  });

  final VoidCallback? onAdd;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Card(
      color: tokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        child: _MaterialEmptyAppear(
          child: Column(
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 12),
              ],
              Text(
                '暂无提供商',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.ink,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '添加 OpenAI / xAI 或兼容源后即可对话与生成。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              if (onAdd != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('添加提供商'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialEmptyAppear extends StatefulWidget {
  const _MaterialEmptyAppear({required this.child});

  final Widget child;

  @override
  State<_MaterialEmptyAppear> createState() => _MaterialEmptyAppearState();
}

class _MaterialEmptyAppearState extends State<_MaterialEmptyAppear> {
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
      duration: MaterialMotion.listAppear,
      curve: MaterialMotion.standard,
      child: widget.child,
    );
  }
}
