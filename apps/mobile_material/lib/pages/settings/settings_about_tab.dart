import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme_controller.dart';
import '../../update/mobile_update_controller.dart';
import '../chat/widgets/markdown_host.dart';

class SettingsAboutTab extends StatefulWidget {
  const SettingsAboutTab({
    super.key,
    required this.dataBackupService,
    this.themeController,
    this.generation,
    this.packageInfo,
    this.updateController,
  });

  final DataBackupService dataBackupService;
  final ThemeController? themeController;
  final GenerationRuntime? generation;

  /// 测试可注入；生产为 null 时异步 `PackageInfo.fromPlatform()`。
  final PackageInfo? packageInfo;

  /// 测试可注入；生产为 null 时内部创建 [MobileUpdateController]。
  final MobileUpdateController? updateController;

  @override
  State<SettingsAboutTab> createState() => _SettingsAboutTabState();
}

class _SettingsAboutTabState extends State<SettingsAboutTab> {
  PackageInfo? _info;
  bool _infoLoading = true;
  late final MobileUpdateController _updater;
  late final bool _ownsUpdater;
  StorageUsageEstimate? _usage;
  bool _usageLoading = true;
  bool _busy = false;

  DataBackupService get _backup => widget.dataBackupService;

  @override
  void initState() {
    super.initState();
    _ownsUpdater = widget.updateController == null;
    _updater = widget.updateController ?? MobileUpdateController();
    _updater.addListener(_onUpdaterChanged);
    unawaited(_updater.ensurePrefsLoaded());
    _loadPackageInfo();
    _loadUsage();
  }

  void _onUpdaterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _updater.removeListener(_onUpdaterChanged);
    if (_ownsUpdater) _updater.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    if (widget.packageInfo != null) {
      setState(() {
        _info = widget.packageInfo;
        _infoLoading = false;
      });
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _info = info;
        _infoLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _infoLoading = false;
      });
    }
  }

  Future<void> _loadUsage() async {
    setState(() => _usageLoading = true);
    try {
      final usage = await _backup.estimateStorageUsage();
      if (!mounted) return;
      setState(() {
        _usage = usage;
        _usageLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usage = null;
        _usageLoading = false;
      });
    }
  }

  String get _versionLabel {
    if (_infoLoading) return '…';
    final info = _info;
    if (info == null) return '未知';
    return '${info.version}+${info.buildNumber}';
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isIos {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onToggleAutoCheck(bool value) async {
    await _updater.setAutoCheckUpdate(value);
  }

  Future<void> _onCheckUpdate() async {
    if (_updater.isChecking || _updater.isDownloading) return;

    final result = await _updater.checkForUpdate(silent: false);
    if (!mounted) return;

    if (_isIos) {
      switch (result.status) {
        case UpdateCheckStatus.upToDate:
          _snack('已是最新版本（${result.latestVersion ?? result.currentVersion}）');
        case UpdateCheckStatus.available:
          await _showUpdatePrompt(result);
        default:
          _snack(
            result.errorMessage ?? MobileUpdateController.iosNonStoreMessage,
          );
      }
      return;
    }

    if (!_isAndroid) {
      _snack(result.errorMessage ?? '当前平台不支持应用内更新');
      return;
    }

    switch (result.status) {
      case UpdateCheckStatus.upToDate:
        _snack('已是最新版本（${result.latestVersion ?? result.currentVersion}）');
      case UpdateCheckStatus.available:
        await _showUpdatePrompt(result);
      case UpdateCheckStatus.notConfigured:
        _snack('未配置更新源');
      case UpdateCheckStatus.noPlatformAsset:
        _snack(result.errorMessage ?? '清单中无当前平台的安装包');
      case UpdateCheckStatus.failed:
        _snack(result.errorMessage ?? '检查更新失败');
    }
  }

  Future<void> _showUpdatePrompt(UpdateCheckResult check) async {
    final notes = prepareUpdateNotes(check.notes);
    final version = check.latestVersion ?? '';
    final isIos = _updater.isIos || _isIos;
    final action = await showDialog<_AboutUpdateAction>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text('发现新版本 ${normalizeVersion(version)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIos
                      ? MobileUpdateController.iosNonStoreMessage
                      : '将下载 APK 并校验完整性后调起系统安装器。'
                          '请确认已允许「安装未知应用」。',
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MarkdownHost(data: notes, compact: true),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, _AboutUpdateAction.skip),
              child: const Text('跳过此版本'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, _AboutUpdateAction.later),
              child: const Text('稍后'),
            ),
            if (isIos)
              const FilledButton(
                onPressed: null,
                child: Text('下载并安装'),
              )
            else
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogCtx, _AboutUpdateAction.install),
                child: const Text('下载并安装'),
              ),
          ],
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _AboutUpdateAction.skip:
        await _updater.skipUpdateVersion(version);
        _snack('已跳过此版本');
      case _AboutUpdateAction.later:
        _snack('可在 设置 → 关于 中安装');
      case _AboutUpdateAction.install:
        final ok = await _updater.downloadAndInstall(result: check);
        if (!mounted) return;
        if (ok) {
          _snack('已调起安装器，请按系统提示完成安装');
        } else {
          _snack(_updater.lastError ?? '下载或安装失败');
        }
    }
  }

  void _stopGenerationIfBusy() {
    final gen = widget.generation;
    if (gen == null || !gen.busy) return;
    gen.abort();
  }

  Future<void> _onImportExport() async {
    if (_busy) return;
    final action = await showModalBottomSheet<_ImportExportAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('导出设置'),
                subtitle: const Text('默认不含 API Key'),
                onTap: () =>
                    Navigator.pop(sheetCtx, _ImportExportAction.export),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('导入设置'),
                subtitle: const Text('从 JSON 备份恢复'),
                onTap: () =>
                    Navigator.pop(sheetCtx, _ImportExportAction.import),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ImportExportAction.export:
        await _onExport();
      case _ImportExportAction.import:
        await _onImport();
    }
  }

  Future<void> _onExport() async {
    if (_busy) return;
    var includeSecrets = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final tokens = materialTokensOf(ctx);
            return AlertDialog(
              title: const Text('导出设置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '将导出提供商、外观、对话默认与会话元数据为 JSON。'
                      '媒体二进制不会写入备份。',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeSecrets,
                      onChanged: (v) {
                        setLocal(() => includeSecrets = v == true);
                      },
                      title: const Text('包含 API Key 明文'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (includeSecrets)
                      Text(
                        '警告：备份将含明文密钥，等同密钥副本。'
                        '请勿分享或云同步；用完建议立即删除。',
                        style: TextStyle(fontSize: 12, color: tokens.danger),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('导出'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final json = await _backup.exportBackupJson(
        DataBackupExportOptions(includeSecrets: includeSecrets),
      );
      final path = await _writeExportJson(json);
      if (!mounted) return;
      if (path == null) {
        _snack('已取消导出');
      } else {
        _snack(
          includeSecrets
              ? '已导出（含密钥）：$path'
              : '已导出：$path',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 优先系统保存对话框；不可用时写入应用文档目录。
  Future<String?> _writeExportJson(String json) async {
    final suggested =
        'ai-studio-backup-${DateTime.now().millisecondsSinceEpoch}.json';
    try {
      final location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location != null) {
        await File(location.path).writeAsString(json, flush: true);
        return location.path;
      }
      // 用户取消
      return null;
    } catch (_) {
      // 部分移动端不支持 getSaveLocation，回退到文档目录
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$suggested');
      await file.writeAsString(json, flush: true);
      return file.path;
    }
  }

  Future<void> _onImport() async {
    if (_busy) return;
    final XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      _snack('无法打开文件选择器：$e');
      return;
    }
    if (picked == null || !mounted) return;

    String raw;
    try {
      raw = await picked.readAsString();
    } catch (e) {
      if (!mounted) return;
      _snack('无法读取文件：$e');
      return;
    }

    DataBackupPayload payload;
    try {
      payload = DataBackupPayload.parse(raw);
    } on DataBackupSchemaException catch (e) {
      if (!mounted) return;
      _snack(e.message);
      return;
    } on DataBackupFormatException catch (e) {
      if (!mounted) return;
      _snack(e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      _snack('无法解析备份：$e');
      return;
    }

    if (!mounted) return;
    var importSecrets = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final tokens = materialTokensOf(ctx);
            return AlertDialog(
              title: const Text('导入设置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '将合并提供商与外观，并用备份会话替换本地会话。'
                      '${widget.generation?.busy == true ? '\n\n检测到进行中的生成，导入前将尝试停止。' : ''}',
                    ),
                    if (payload.includeSecrets) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: importSecrets,
                        onChanged: (v) {
                          setLocal(() => importSecrets = v == true);
                        },
                        title: const Text('同时导入 API Key'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (importSecrets)
                        Text(
                          '将覆盖本机对应提供商密钥。请确认备份来源可信。',
                          style: TextStyle(fontSize: 12, color: tokens.danger),
                        ),
                    ] else
                      Text(
                        '此备份不含密钥，本地 API Key 保持不变。',
                        style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('导入'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    _stopGenerationIfBusy();
    setState(() => _busy = true);
    try {
      final result = await _backup.importBackup(
        raw,
        options: DataBackupImportOptions(importSecrets: importSecrets),
      );
      final appearance = widget.themeController?.appearanceRepository;
      if (appearance != null) {
        widget.themeController?.loadFrom(appearance.settings);
      }
      await _loadUsage();
      if (!mounted) return;
      final parts = <String>[
        if (result.providersAdded > 0 || result.providersMerged > 0)
          '提供商',
        if (result.appearanceImported) '外观',
        if (result.chatDefaultsImported) '对话默认',
        if (result.sessionsImported) '会话',
        if (result.secretsApplied) '密钥',
      ];
      _snack(parts.isEmpty ? '导入完成' : '导入完成：${parts.join(' · ')}');
    } on DataBackupSchemaException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } on DataBackupFormatException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onClearData() async {
    if (_busy) return;
    var choice = _ClearChoice.sessions;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final tokens = materialTokensOf(ctx);
            return AlertDialog(
              title: const Text('清除本地数据'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '此操作不可撤销。'
                      '${widget.generation?.busy == true ? ' 检测到进行中的生成，清除前将尝试停止。' : ' 若仍有生成任务，请先停止。'}',
                    ),
                    const SizedBox(height: 8),
                    for (final opt in _ClearChoice.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          choice == opt
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: choice == opt ? tokens.primary : tokens.inkMuted,
                        ),
                        title: Text(opt.label),
                        onTap: () => setLocal(() => choice = opt),
                      ),
                    if (choice == _ClearChoice.all)
                      Text(
                        '将清除会话、媒体缓存、外观与对话默认、提供商、日志以及全部 API Key。',
                        style: TextStyle(fontSize: 12, color: tokens.danger),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.danger,
                  ),
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: Text(choice == _ClearChoice.all ? '全部清除' : '清除'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    _stopGenerationIfBusy();
    setState(() => _busy = true);
    try {
      final result = await _backup.clearLocalData(choice.flags);
      if (result.clearedSettings) {
        final appearance = widget.themeController?.appearanceRepository;
        if (appearance != null) {
          widget.themeController?.loadFrom(appearance.settings);
        }
      }
      await _loadUsage();
      if (!mounted) return;
      final parts = <String>[
        if (result.clearedSessions) '会话',
        if (result.clearedMediaCache) '媒体缓存',
        if (result.clearedSettings) '设置',
        if (result.clearedProviders) '提供商',
        if (result.clearedLogs) '日志',
        if (result.clearedSecrets) '密钥',
      ];
      _snack(parts.isEmpty ? '无需清理' : '已清除：${parts.join(' · ')}');
    } catch (e) {
      if (!mounted) return;
      _snack('清除失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _usageSummary() {
    if (_usageLoading) return '正在估算本地占用…';
    final u = _usage;
    if (u == null) return '无法估算本地占用';
    final sessions =
        u.chatSessionCount + u.imageSessionCount + u.videoSessionCount;
    return '约 ${_formatBytes(u.totalApproxBytes)} · 会话 $sessions · '
        '媒体 ${_formatBytes(u.mediaCacheBytes)}';
  }

  Widget _statusPill(MaterialTokens tokens) {
    final hasUpdate = _updater.hasAvailableUpdate;
    final check = _updater.lastCheck;
    final label = hasUpdate
        ? '有更新 ${check?.latestVersion ?? _updater.prefs.availableUpdateVersion ?? ''}'
            .trim()
        : '已是最新';
    final bg = hasUpdate
        ? Color.lerp(tokens.primary, tokens.surface, 0.85)!
        : tokens.surfaceMuted;
    final fg = hasUpdate ? tokens.primary : tokens.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hasUpdate
              ? Color.lerp(tokens.primary, tokens.border, 0.45)!
              : tokens.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final checking = _updater.isChecking;
    final downloading = _updater.isDownloading;
    final progress = _updater.downloadProgress;
    final progressLabel = _updater.progressLabel;
    final check = _updater.lastCheck;
    final busy = checking || downloading;
    final notes = prepareUpdateNotes(check?.notes ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Studio',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 $_versionLabel · Android / iOS',
                  style: TextStyle(fontSize: 13, color: tokens.inkSecondary),
                ),
                const SizedBox(height: 8),
                _statusPill(tokens),
                const SizedBox(height: 6),
                Text(
                  _isAndroid
                      ? '更新通道：GitHub Releases（完整性校验）'
                      : _isIos
                          ? '更新通道：非 App Store · 请通过内测渠道获取新版本'
                          : '分发：不上架 · 直链 / 侧载清单',
                  style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                ),
                if (_isAndroid) ...[
                  const SizedBox(height: 6),
                  Text(
                    '不上架应用商店；安装包为按 ABI 分包的 AI.Studio_*_<abi>.apk，需允许「安装未知应用」。',
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                ],
                if (_isIos) ...[
                  const SizedBox(height: 6),
                  Text(
                    'iOS 以企业签 / TestFlight 等非 Store 渠道分发，'
                    '不提供商店内购更新。${MobileUpdateController.iosNonStoreMessage}',
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启动时自动检查更新'),
                  subtitle: const Text('冷启动静默检查；关闭后仅手动检查'),
                  value: _updater.autoCheckUpdate,
                  onChanged: busy ? null : _onToggleAutoCheck,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : _onCheckUpdate,
                      child: checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('检查更新'),
                    ),
                    const OutlinedButton(
                      onPressed: null,
                      child: Text('开源许可'),
                    ),
                  ],
                ),
                if (check != null && check.hasUpdate) ...[
                  const SizedBox(height: 10),
                  Text(
                    '发现新版本 ${check.latestVersion}',
                    style: TextStyle(fontSize: 13, color: tokens.inkSecondary),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    MarkdownHost(data: notes, compact: true),
                  ],
                  const SizedBox(height: 8),
                  if (downloading)
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              height: 40,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(color: tokens.surfaceMuted),
                                  if (progress?.fraction != null)
                                    FractionallySizedBox(
                                      widthFactor:
                                          progress!.fraction!.clamp(0.0, 1.0),
                                      alignment: Alignment.centerLeft,
                                      child: ColoredBox(color: tokens.primary),
                                    )
                                  else
                                    const Align(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        progressLabel ??
                                            (progress?.fraction != null
                                                ? '正在下载… ${(progress!.fraction! * 100).toStringAsFixed(0)}%'
                                                : '正在下载…'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: (progress?.fraction ?? 0) > 0.45
                                              ? tokens.onPrimary
                                              : tokens.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _updater.cancelDownload,
                          child: const Text('取消'),
                        ),
                      ],
                    )
                  else if (!checking)
                    OutlinedButton(
                      onPressed: () async {
                        if (_isIos) {
                          await _showUpdatePrompt(check);
                          return;
                        }
                        if (_updater.isDownloading) return;
                        final ok =
                            await _updater.downloadAndInstall(result: check);
                        if (!mounted) return;
                        if (ok) {
                          _snack('已调起安装器，请按系统提示完成安装');
                        } else {
                          final err = _updater.lastError ?? '下载或安装失败';
                          _snack(err);
                        }
                      },
                      child: Text(_isIos ? '查看更新说明' : '下载并安装'),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                title: const Text('本地占用'),
                subtitle: Text(_usageSummary()),
              ),
              Divider(height: 1, color: tokens.border),
              ListTile(
                title: const Text('导入 / 导出'),
                subtitle: const Text('设置与会话备份（JSON）'),
                enabled: !_busy,
                trailing: Icon(Icons.chevron_right, color: tokens.inkMuted),
                onTap: _busy ? null : _onImportExport,
              ),
              Divider(height: 1, color: tokens.border),
              Semantics(
                button: true,
                label: '清理本地数据',
                child: ListTile(
                  title: const Text('清理本地数据'),
                  subtitle: const Text('会话 / 媒体缓存 / 全部'),
                  enabled: !_busy,
                  trailing: Icon(Icons.chevron_right, color: tokens.inkMuted),
                  onTap: _busy ? null : _onClearData,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _AboutUpdateAction { skip, later, install }

enum _ImportExportAction { export, import }

enum _ClearChoice {
  sessions,
  media,
  all;

  String get label => switch (this) {
        sessions => '仅会话（对话 / 生图 / 生视频）',
        media => '仅媒体缓存',
        all => '全部（含设置与密钥）',
      };

  ClearLocalDataFlags get flags => switch (this) {
        sessions => ClearLocalDataFlags.sessionsOnly,
        media => ClearLocalDataFlags.mediaOnly,
        all => ClearLocalDataFlags.all,
      };
}

String _formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}
