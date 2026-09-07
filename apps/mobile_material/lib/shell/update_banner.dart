import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// M-UpdateBanner（FB-UPDATE）：壳层顶部轻量更新提示。
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.version,
    required this.onGoUpdate,
    required this.onLater,
    this.subtitle,
  });

  final String version;
  final VoidCallback onGoUpdate;
  final VoidCallback onLater;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final sub = subtitle?.trim();
    final announce = sub != null && sub.isNotEmpty
        ? '发现新版本 $version。$sub'
        : '发现新版本 $version';
    return Semantics(
      liveRegion: true,
      container: true,
      label: announce,
      child: Material(
        color: Color.lerp(tokens.primary, tokens.surface, 0.88),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.system_update_alt, size: 20, color: tokens.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发现新版本 $version',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkMuted,
                            fontFamily: tokens.fontFamily,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: onLater,
                            child: const Text('稍后'),
                          ),
                          FilledButton(
                            onPressed: onGoUpdate,
                            child: const Text('去更新'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '稍后',
                  onPressed: onLater,
                  icon: Icon(Icons.close, size: 18, color: tokens.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
