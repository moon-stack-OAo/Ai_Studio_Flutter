import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 当前运行时对应的桌面更新清单平台键候选（按优先级）。
///
/// 约定键：`windows-x86_64`、`windows-x86_64-nsis`、`windows-x86_64-msi` 等。
List<String> desktopUpdatePlatformCandidates({
  bool? isWindows,
  bool? isMacOS,
  bool? isLinux,
  String? macArch,
}) {
  if (kIsWeb) return const [];

  final win = isWindows ?? Platform.isWindows;
  final mac = isMacOS ?? Platform.isMacOS;
  final linux = isLinux ?? Platform.isLinux;

  if (win) {
    return const [
      'windows-x86_64',
      'windows-x86_64-nsis',
      'x86_64-pc-windows-msvc',
      'windows-x86_64-msi',
    ];
  }
  if (mac) {
    final arch = (macArch ?? Platform.version).toLowerCase();
    // Platform.version 含 arch 信息有限；优先按宿主进程位数启发式。
    final preferArm = arch.contains('arm') ||
        arch.contains('aarch64') ||
        _hostLooksArm();
    if (preferArm) {
      return const [
        'darwin-aarch64',
        'aarch64-apple-darwin',
        'darwin-x86_64',
        'x86_64-apple-darwin',
      ];
    }
    return const [
      'darwin-x86_64',
      'x86_64-apple-darwin',
      'darwin-aarch64',
      'aarch64-apple-darwin',
    ];
  }
  if (linux) {
    return const [
      'linux-x86_64',
      'x86_64-unknown-linux-gnu',
    ];
  }
  return const [];
}

/// AppDock 资产 `platform` + `arch`（及文件名）到内部清单键的映射。
///
/// AppDock 平台枚举：`windows` / `macos` / `linux` / `android`。
/// 架构：`x64` / `arm64` / `x86` / `universal` / `unknown`。
/// Android 优先从文件名识别 ABI（`arm64-v8a` / `armeabi-v7a` / `x86_64`）。
List<String> appDockAssetPlatformKeys({
  required String platform,
  required String arch,
  String fileName = '',
}) {
  final plat = platform.trim().toLowerCase();
  final arc = arch.trim().toLowerCase();
  final name = fileName.trim().toLowerCase();

  if (plat == 'android' || name.endsWith('.apk') || name.contains('.apk.')) {
    final abi = _androidAbiFromName(name) ?? _androidAbiFromArch(arc);
    if (abi == 'armeabi-v7a') {
      return const ['armeabi-v7a', 'armv7-linux-androideabi'];
    }
    if (abi == 'x86_64') {
      return const ['x86_64', 'x86_64-linux-android'];
    }
    if (abi == 'arm64-v8a') {
      return const ['arm64-v8a', 'aarch64-linux-android'];
    }
    return const [];
  }

  if (plat == 'windows') {
    return const [
      'windows-x86_64',
      'windows-x86_64-nsis',
      'x86_64-pc-windows-msvc',
    ];
  }
  if (plat == 'macos') {
    if (arc == 'arm64' || name.contains('aarch64') || name.contains('arm64')) {
      return const ['darwin-aarch64', 'aarch64-apple-darwin'];
    }
    if (arc == 'x64' ||
        arc == 'x86_64' ||
        name.contains('x86_64') ||
        name.contains('x64')) {
      return const ['darwin-x86_64', 'x86_64-apple-darwin'];
    }
    return const ['darwin-aarch64', 'darwin-x86_64'];
  }
  if (plat == 'linux') {
    return const ['linux-x86_64', 'x86_64-unknown-linux-gnu'];
  }
  return const [];
}

String? _androidAbiFromName(String name) {
  if (name.contains('armeabi-v7a') || name.contains('armv7')) {
    return 'armeabi-v7a';
  }
  if (name.contains('x86_64') || name.contains('x64')) return 'x86_64';
  if (name.contains('arm64-v8a') ||
      name.contains('arm64') ||
      name.contains('aarch64')) {
    return 'arm64-v8a';
  }
  return null;
}

String? _androidAbiFromArch(String arch) {
  switch (arch) {
    case 'arm64':
    case 'aarch64':
      return 'arm64-v8a';
    case 'x64':
    case 'x86_64':
    case 'amd64':
      return 'x86_64';
    case 'x86':
    case 'armeabi-v7a':
    case 'armv7':
      return 'armeabi-v7a';
    default:
      return null;
  }
}

/// 将运行时 ABI / 字符串归一为 Android ABI 提示（如 `arm64-v8a`）。
String? normalizeAndroidAbiHint([String? raw]) {
  final hint = (raw ?? currentAndroidAbiHint() ?? '').trim().toLowerCase();
  if (hint.isEmpty) return null;
  if (hint.contains('armeabi-v7a') ||
      hint.contains('armeabi') ||
      hint.contains('armv7') ||
      hint == 'android_arm' ||
      hint == 'arm') {
    return 'armeabi-v7a';
  }
  if (hint.contains('x86_64') ||
      hint.contains('x86-64') ||
      hint == 'android_x64' ||
      hint == 'x64') {
    return 'x86_64';
  }
  if (hint.contains('arm64') ||
      hint.contains('aarch64') ||
      hint == 'android_arm64') {
    return 'arm64-v8a';
  }
  return null;
}

/// 当前进程对应的 Android ABI 提示；非 Android 或无法识别时返回 null。
String? currentAndroidAbiHint() {
  if (kIsWeb) return null;
  try {
    if (!Platform.isAndroid) return null;
  } catch (_) {
    return null;
  }
  switch (Abi.current()) {
    case Abi.androidArm64:
      return 'arm64-v8a';
    case Abi.androidArm:
      return 'armeabi-v7a';
    case Abi.androidX64:
      return 'x86_64';
    default:
      return null;
  }
}

/// Android 侧载清单平台键候选（按优先级）。
///
/// 未传 [abiHint] 时优先用 [currentAndroidAbiHint]；仍未知则默认 arm64。
List<String> androidUpdatePlatformCandidates({
  String? abiHint,
}) {
  final normalized = normalizeAndroidAbiHint(abiHint);
  if (normalized == 'armeabi-v7a') {
    return const [
      'armeabi-v7a',
      'armv7-linux-androideabi',
      'aarch64-linux-android',
      'arm64-v8a',
      'x86_64',
      'x86_64-linux-android',
    ];
  }
  if (normalized == 'x86_64') {
    return const [
      'x86_64',
      'x86_64-linux-android',
      'aarch64-linux-android',
      'arm64-v8a',
    ];
  }
  // 默认 / arm64-v8a：优先 64-bit ARM（主流真机）。
  return const [
    'aarch64-linux-android',
    'arm64-v8a',
    'armeabi-v7a',
    'armv7-linux-androideabi',
    'x86_64',
    'x86_64-linux-android',
  ];
}

bool _hostLooksArm() {
  try {
    // Dart VM 在 Apple Silicon 上通常为 arm64。
    return Platform.localHostname.isNotEmpty &&
        Platform.operatingSystemVersion.toLowerCase().contains('arm');
  } catch (_) {
    return false;
  }
}
