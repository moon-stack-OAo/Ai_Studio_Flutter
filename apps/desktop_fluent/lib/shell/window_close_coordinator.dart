import 'dart:async';
import 'dart:io' show exit;

import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'system_tray_controller.dart';
import 'window_bootstrap.dart';

/// 桌面关闭三态协调器：读 [AppearanceRepository.closeBehavior]，
/// 拦截标题栏/系统关闭，并与托盘联动。
class WindowCloseCoordinator with WindowListener {
  WindowCloseCoordinator({
    required AppearanceRepository appearanceRepository,
    required this._navigatorKey,
    this.onBeforeQuit,
    this.onOpenSettings,
    this.onCheckUpdate,
  }) : _appearance = appearanceRepository;

  final AppearanceRepository _appearance;
  final GlobalKey<NavigatorState> _navigatorKey;
  /// 真正退出前回调（如 [GenerationRuntime.abort]）；最小化到托盘不触发。
  final VoidCallback? onBeforeQuit;
  VoidCallback? onOpenSettings;
  VoidCallback? onCheckUpdate;

  SystemTrayController? _tray;
  bool _attached = false;
  bool _asking = false;
  bool _quitting = false;

  bool get isAttached => _attached;

  Future<void> attach() async {
    if (!supportsCustomTitleBar || _attached) return;
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    _tray = SystemTrayController(
      onShow: showMainWindow,
      onQuit: quitApp,
      onOpenSettings: onOpenSettings,
      onCheckUpdate: onCheckUpdate,
    );
    await _tray!.init();
    _attached = true;
  }

  Future<void> detach() async {
    if (!_attached) return;
    windowManager.removeListener(this);
    await _tray?.dispose();
    _tray = null;
    _attached = false;
  }

  /// 标题栏关闭与系统关闭统一入口（触发 preventClose → [onWindowClose]）。
  Future<void> requestClose() async {
    if (!supportsCustomTitleBar) return;
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (_quitting) return;
    final prevent = await windowManager.isPreventClose();
    if (!prevent) return;

    final behavior = _appearance.settings.closeBehavior;
    switch (behavior) {
      case 'quit':
        await quitApp();
      case 'tray':
        await hideToTray();
      case 'ask':
      default:
        await _askClose();
    }
  }

  Future<void> _askClose() async {
    if (_asking) return;
    _asking = true;
    try {
      await showMainWindow();
      final ctx = _navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        await hideToTray();
        return;
      }

      var remember = false;
      final action = await showDialog<String>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (dialogCtx, setLocal) {
              return ContentDialog(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 756),
                title: const Text('关闭 AI Studio'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('请选择关闭窗口后的行为：'),
                    const SizedBox(height: 10),
                    const Text('• 退出程序：结束进程并完全退出'),
                    const Text('• 最小化到托盘：后台继续运行，可从托盘恢复'),
                    const SizedBox(height: 12),
                    Checkbox(
                      checked: remember,
                      onChanged: (v) => setLocal(() => remember = v ?? false),
                      content: const Text('记住我的选择'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '可在「设置 → 关于与更新」中重置为每次询问',
                      style: TextStyle(
                        fontSize: 11,
                        color: FluentTheme.of(dialogCtx)
                            .resources
                            .textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Button(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () => Navigator.pop(dialogCtx, 'tray'),
                        child: const Text('最小化到托盘'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx, 'quit'),
                        child: const Text('退出程序'),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );

      if (action == null) return;

      if (remember &&
          AppearanceSettings.closeBehaviorValues.contains(action)) {
        // 不阻塞窗口消失 / 退出路径；失败仍可观察。
        unawaited(_rememberCloseBehavior(action));
      }

      if (action == 'quit') {
        await quitApp();
      } else if (action == 'tray') {
        await hideToTray();
      }
    } finally {
      _asking = false;
    }
  }

  Future<void> _rememberCloseBehavior(String action) async {
    try {
      await _appearance.update(closeBehavior: action);
    } catch (e, st) {
      debugPrint('记住关闭行为失败: $e\n$st');
    }
  }

  Future<void> showMainWindow() async {
    if (!supportsCustomTitleBar) return;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      debugPrint('显示主窗口失败: $e\n$st');
    }
  }

  Future<void> hideToTray() async {
    if (!supportsCustomTitleBar) return;
    try {
      await windowManager.hide();
    } catch (e, st) {
      debugPrint('隐藏到托盘失败: $e\n$st');
    }
  }

  Future<void> quitApp() async {
    if (_quitting) return;
    _quitting = true;
    try {
      // 1. 尽快让窗口消失，避免 destroy 拆 IndexedStack 时的体感卡顿。
      if (supportsCustomTitleBar) {
        try {
          await windowManager.hide();
        } catch (e, st) {
          debugPrint('退出前隐藏窗口失败: $e\n$st');
        }
      }

      // 2. 仅真正退出时 abort 生成（托盘隐藏不走此路径）。
      try {
        onBeforeQuit?.call();
      } catch (e, st) {
        debugPrint('退出前 abort 失败: $e\n$st');
      }

      // 3. 托盘销毁放在窗口消失之后，不挡用户体感。
      final tray = _tray;
      _tray = null;
      if (tray != null) {
        try {
          await tray.dispose();
        } catch (e, st) {
          debugPrint('退出时销毁托盘失败: $e\n$st');
        }
      }

      // 4. 放行关闭并销毁窗口。
      if (supportsCustomTitleBar) {
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
        await windowManager.destroy();
      }
    } catch (e, st) {
      debugPrint('退出失败: $e\n$st');
      // 与更新安装后退出同策略：destroy 失败时强制结束进程。
      try {
        exit(0);
      } catch (_) {
        _quitting = false;
      }
    }
  }
}
