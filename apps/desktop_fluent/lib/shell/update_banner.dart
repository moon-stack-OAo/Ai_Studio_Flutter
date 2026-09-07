import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// F-UpdateBanner（FB-UPDATE）：壳层顶部轻量更新提示。
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.version,
    required this.onGoUpdate,
    required this.onLater,
  });

  final String version;
  final VoidCallback onGoUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: '发现新版本 $version。可前往关于页下载安装，或稍后再说。',
        child: InfoBar(
          title: Text(
            '发现新版本 $version',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            '可前往关于页下载安装，或稍后再说。',
            style: TextStyle(
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
          severity: InfoBarSeverity.info,
          isLong: true,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Button(
                onPressed: onLater,
                child: const Text('稍后'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onGoUpdate,
                child: const Text('去更新'),
              ),
            ],
          ),
          onClose: onLater,
        ),
      ),
    );
  }
}
