import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';

import 'window_bootstrap.dart';

/// 稳定进程名（PID 锁键）；勿用随启动路径变化的可执行名。
const kDesktopSingleInstanceProcessName = 'ai_studio_fluent';

/// 握手失败时的待记运行日志（日志仓库尚未就绪时暂存）。
String? pendingSingleInstanceLog;

/// 首实例「唤起」回调；可在 [WindowCloseCoordinator] 就绪后改挂 [showMainWindow]。
Future<void> Function() desktopSingleInstanceShow = showDesktopMainWindow;

/// 与托盘「显示主窗口」对齐：restore → show → focus → 任务栏可见。
Future<void> showDesktopMainWindow() async {
  if (!supportsCustomTitleBar) return;
  try {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  } catch (e, st) {
    debugPrint('显示主窗口失败: $e\n$st');
  }
}

/// 在窗口选项 / 仓库大量初始化**之前**完成单实例握手。
///
/// 仅做 [windowManager.ensureInitialized]（供唤起路径可用），不跑
/// [bootstrapDesktopWindow] 的尺寸/标题栏等重逻辑。
///
/// 返回 `true` 表示本进程应继续启动（首实例，或 IPC/锁失败降级）。
/// 次实例在成功通知首实例后会 [exit]；通知失败则返回 `true` 并写入 [pendingSingleInstanceLog]。
Future<bool> ensureDesktopSingleInstance() async {
  if (!supportsCustomTitleBar) return true;
  try {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return true;
    }
  } catch (_) {
    return true;
  }

  try {
    // 唤起回调依赖 window_manager；须早于 RPC 对外服务。
    await windowManager.ensureInitialized();

    // 正式验收与 `flutter run` 均需生效；默认 kDebugMode 下包会跳过检测。
    FlutterSingleInstance.debugMode = false;
    FlutterSingleInstance.processName = kDesktopSingleInstanceProcessName;
    FlutterSingleInstance.onFocus = (_) async {
      await desktopSingleInstanceShow();
    };

    final guard = FlutterSingleInstance();
    final isFirst = await guard.isFirstInstance();
    if (isFirst) return true;

    // bringToFront 留给 onFocus 统一 show/restore/focus（含托盘隐藏）。
    final err = await guard.focus(const <String, dynamic>{}, false);
    if (err != null) {
      final msg = '单实例唤起失败，允许本进程继续启动：$err';
      debugPrint(msg);
      pendingSingleInstanceLog = msg;
      return true;
    }

    exit(0);
  } catch (e, st) {
    final msg = '单实例握手失败，允许继续启动：$e';
    debugPrint('$msg\n$st');
    pendingSingleInstanceLog = msg;
    return true;
  }
}
