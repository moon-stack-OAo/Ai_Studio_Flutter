import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'window_bootstrap.dart';

/// 系统托盘：显示 / 设置 / 检查更新 / 退出；左键显示主窗口。
class SystemTrayController with TrayListener {
  SystemTrayController({
    required this.onShow,
    required this.onQuit,
    this.onOpenSettings,
    this.onCheckUpdate,
  });

  final Future<void> Function() onShow;
  final Future<void> Function() onQuit;
  /// 可在 attach 后由壳层赋值（打开设置 / 检查更新）。
  VoidCallback? onOpenSettings;
  VoidCallback? onCheckUpdate;

  bool _ready = false;

  bool get isReady => _ready;

  static bool get isSupported {
    if (!supportsCustomTitleBar) return false;
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(_iconAssetPath());
      await trayManager.setToolTip('AI Studio');
      await trayManager.setContextMenu(_buildMenu());
      _ready = true;
    } catch (e, st) {
      debugPrint('托盘初始化失败: $e\n$st');
      try {
        trayManager.removeListener(this);
      } catch (_) {}
      _ready = false;
    }
  }

  Future<void> dispose() async {
    if (!_ready && !isSupported) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (e, st) {
      debugPrint('托盘销毁失败: $e\n$st');
    } finally {
      _ready = false;
    }
  }

  String _iconAssetPath() {
    if (Platform.isWindows) {
      return 'assets/tray_icon.ico';
    }
    return 'assets/tray_icon.png';
  }

  Menu _buildMenu() {
    return Menu(
      items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: '打开设置'),
        MenuItem(key: 'update', label: '检查更新'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    );
  }

  @override
  void onTrayIconMouseDown() {
    // Windows / Linux：左键显示；macOS 惯例左键也可显示主窗口。
    onShow();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isWindows || Platform.isLinux) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShow();
      case 'settings':
        onShow().then((_) {
          onOpenSettings?.call();
        });
      case 'update':
        onShow().then((_) {
          onCheckUpdate?.call();
        });
      case 'quit':
        onQuit();
      default:
        break;
    }
  }
}
