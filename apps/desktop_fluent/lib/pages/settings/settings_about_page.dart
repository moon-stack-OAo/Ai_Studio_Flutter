import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme_controller.dart';
import '../../update/update_controller.dart';

class SettingsAboutPage extends StatefulWidget {
  const SettingsAboutPage({
    super.key,
    required this.appearanceRepository,
    required this.dataBackupService,
    this.themeController,
    this.generation,
    this.updateController,
    this.packageInfo,
  });

  final AppearanceRepository appearanceRepository;
  final DataBackupService dataBackupService;
  final ThemeController? themeController;
  final GenerationRuntime? generation;
  final UpdateController? updateController;

  /// 测试可注入；生产为 null 时异步 `PackageInfo.fromPlatform()`。
  final PackageInfo? packageInfo;

  @override
  State<SettingsAboutPage> createState() => _SettingsAboutPageState();
}

class _SettingsAboutPageState extends State<SettingsAboutPage> {
  PackageInfo? _info;
  bool _infoLoading = true;
  StorageUsageEstimate? _usage;
  bool _usageLoading = true;
  bool _busy = false;

  AppearanceRepository get _repo => widget.appearanceRepository;
  DataBackupService get _backup => widget.dataBackupService;
  UpdateController? get _updater => widget.updateController;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _updater?.addListener(_onUpdaterChanged);
    _loadPackageInfo();
    _loadUsage();
    _updater?.ensureCurrentVersion();
  }

  @override
  void didUpdateWidget(covariant SettingsAboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updateController != widget.updateController) {
      oldWidget.updateController?.removeListener(_onUpdaterChanged);
      widget.updateController?.addListener(_onUpdaterChanged);
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _updater?.removeListener(_onUpdaterChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  void _onUpdaterChanged() {
    if (mounted) setState(() {});
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

  void _showInfoBar(String message, InfoBarSeverity severity) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(message),
          severity: severity,
          onClose: close,
        );
      },
    );
  }

  Future<void> _setCloseBehavior(String wire) async {
    if (_repo.settings.closeBehavior == wire) return;
    try {
      await _repo.update(closeBehavior: wire);
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('保存失败：$e', InfoBarSeverity.error);
    }
  }

  Future<void> _onCheckUpdate() async {
    final updater = _updater;
    if (updater == null) {
      _showInfoBar('更新服务未初始化', InfoBarSeverity.warning);
      return;
    }
    if (!updater.isConfigured) {
      _showInfoBar('未配置更新源', InfoBarSeverity.warning);
      return;
    }
    if (updater.isChecking || updater.isDownloading) return;

    final result = await updater.checkForUpdate();
    if (!mounted) return;

    switch (result.status) {
      case UpdateCheckStatus.upToDate:
        _showInfoBar(
          '已是最新版本（${result.latestVersion ?? result.currentVersion}）',
          InfoBarSeverity.success,
        );
      case UpdateCheckStatus.available:
        _showInfoBar(
          '发现新版本 ${result.latestVersion}',
          InfoBarSeverity.info,
        );
      case UpdateCheckStatus.notConfigured:
        _showInfoBar('未配置更新源', InfoBarSeverity.warning);
      case UpdateCheckStatus.noPlatformAsset:
        _showInfoBar(
          result.errorMessage ?? '清单中无当前平台的安装包',
          InfoBarSeverity.warning,
        );
      case UpdateCheckStatus.failed:
        _showInfoBar(
          result.errorMessage ?? '检查更新失败',
          InfoBarSeverity.error,
        );
    }
  }

  Future<void> _onDownloadAndInstall() async {
    final updater = _updater;
    final check = updater?.lastCheck;
    if (updater == null || check == null || !check.hasUpdate) return;
    if (updater.isDownloading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return ContentDialog(
          title: Text('下载并安装 ${check.latestVersion ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '将下载 Windows 安装包并校验签名后启动安装器。',
              ),
              if (check.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  check.notes.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: FluentTheme.of(dialogCtx)
                        .resources
                        .textFillColorSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '将校验安装包签名；失败则阻断安装。安装器启动后应用将退出。',
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
            Button(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('下载并安装'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final ok = await updater.downloadAndInstall(result: check);
    if (!mounted) return;
    if (!ok) {
      _showInfoBar(
        updater.lastError ?? '下载或安装失败',
        InfoBarSeverity.error,
      );
    }
  }

  void _stopGenerationIfBusy() {
    final gen = widget.generation;
    if (gen == null || !gen.busy) return;
    gen.abort();
  }

  Future<void> _onExport() async {
    if (_busy) return;
    var includeSecrets = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return ContentDialog(
              title: const Text('导出设置'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '将导出提供商、外观、对话默认与会话元数据为 JSON 文件。'
                    '媒体二进制不会写入备份。',
                  ),
                  const SizedBox(height: 14),
                  Checkbox(
                    checked: includeSecrets,
                    onChanged: (v) {
                      setLocal(() => includeSecrets = v == true);
                    },
                    content: const Text('包含 API Key 明文'),
                  ),
                  if (includeSecrets) ...[
                    const SizedBox(height: 10),
                    Text(
                      '警告：备份将含明文密钥，等同密钥副本。'
                      '请勿分享、云同步或截图；用完建议立即删除。',
                      style: TextStyle(
                        fontSize: 12,
                        color: fluentTokensOf(ctx).danger,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                Button(
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

    final location = await getSaveLocation(
      suggestedName:
          'ai-studio-backup-${DateTime.now().millisecondsSinceEpoch}.json',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final json = await _backup.exportBackupJson(
        DataBackupExportOptions(includeSecrets: includeSecrets),
      );
      await File(location.path).writeAsString(json, flush: true);
      if (!mounted) return;
      _showInfoBar(
        includeSecrets ? '已导出（含密钥，请妥善保管）' : '已导出设置',
        InfoBarSeverity.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('导出失败：$e', InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onImport() async {
    if (_busy) return;
    final files = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (files == null || !mounted) return;

    String raw;
    try {
      raw = await File(files.path).readAsString();
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('无法读取文件：$e', InfoBarSeverity.error);
      return;
    }

    DataBackupPayload payload;
    try {
      payload = DataBackupPayload.parse(raw);
    } on DataBackupSchemaException catch (e) {
      if (!mounted) return;
      _showInfoBar(e.message, InfoBarSeverity.error);
      return;
    } on DataBackupFormatException catch (e) {
      if (!mounted) return;
      _showInfoBar(e.message, InfoBarSeverity.error);
      return;
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('无法解析备份：$e', InfoBarSeverity.error);
      return;
    }

    if (!mounted) return;
    var importSecrets = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return ContentDialog(
              title: const Text('导入设置'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '将合并提供商与外观设置，并用备份中的会话替换本地会话。'
                    '${widget.generation?.busy == true ? '\n\n检测到进行中的生成，导入前将尝试停止。' : ''}',
                  ),
                  if (payload.includeSecrets) ...[
                    const SizedBox(height: 14),
                    Checkbox(
                      checked: importSecrets,
                      onChanged: (v) {
                        setLocal(() => importSecrets = v == true);
                      },
                      content: const Text('同时导入 API Key'),
                    ),
                    if (importSecrets) ...[
                      const SizedBox(height: 8),
                      Text(
                        '将用备份中的密钥覆盖本机对应提供商密钥。请确认备份来源可信。',
                        style: TextStyle(
                          fontSize: 12,
                          color: fluentTokensOf(ctx).danger,
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 10),
                    Text(
                      '此备份不含密钥，导入后本地 API Key 保持不变。',
                      style: TextStyle(
                        fontSize: 12,
                        color: FluentTheme.of(ctx)
                            .resources
                            .textFillColorSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                Button(
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
      widget.themeController?.loadFrom(_repo.settings);
      await _loadUsage();
      if (!mounted) return;
      final parts = <String>[
        if (result.providersAdded > 0 || result.providersMerged > 0)
          '提供商 +${result.providersAdded}/更新 ${result.providersMerged}',
        if (result.appearanceImported) '外观',
        if (result.chatDefaultsImported) '对话默认',
        if (result.sessionsImported) '会话',
        if (result.secretsApplied) '密钥已应用',
      ];
      _showInfoBar(
        parts.isEmpty ? '导入完成' : '导入完成：${parts.join(' · ')}',
        InfoBarSeverity.success,
      );
    } on DataBackupSchemaException catch (e) {
      if (!mounted) return;
      _showInfoBar(e.message, InfoBarSeverity.error);
    } on DataBackupFormatException catch (e) {
      if (!mounted) return;
      _showInfoBar(e.message, InfoBarSeverity.error);
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('导入失败：$e', InfoBarSeverity.error);
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
            final tokens = fluentTokensOf(ctx);
            return ContentDialog(
              title: const Text('清除本地数据'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '此操作不可撤销。'
                    '${widget.generation?.busy == true ? ' 检测到进行中的生成，清除前将尝试停止。' : ' 若仍有生成任务，请先停止。'}',
                  ),
                  const SizedBox(height: 14),
                  RadioGroup<_ClearChoice>(
                    groupValue: choice,
                    onChanged: (v) {
                      if (v != null) setLocal(() => choice = v);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final opt in _ClearChoice.values) ...[
                          if (opt != _ClearChoice.values.first)
                            const SizedBox(height: 6),
                          RadioButton<_ClearChoice>(
                            value: opt,
                            content: Text(opt.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (choice == _ClearChoice.all) ...[
                    const SizedBox(height: 12),
                    Text(
                      '将清除会话、媒体缓存、外观与对话默认、提供商配置、日志以及全部 API Key。',
                      style: TextStyle(fontSize: 12, color: tokens.danger),
                    ),
                  ],
                ],
              ),
              actions: [
                Button(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(tokens.danger),
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
        widget.themeController?.loadFrom(_repo.settings);
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
      _showInfoBar(
        parts.isEmpty ? '无需清理' : '已清除：${parts.join(' · ')}',
        InfoBarSeverity.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('清除失败：$e', InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _usageSummary() {
    if (_usageLoading) return '正在估算本地占用…';
    final u = _usage;
    if (u == null) return '无法估算本地占用。';
    final sessions =
        u.chatSessionCount + u.imageSessionCount + u.videoSessionCount;
    return '约 ${_formatBytes(u.totalApproxBytes)} · '
        '会话 $sessions · 消息 ${u.chatMessageCount} · '
        '媒体 ${_formatBytes(u.mediaCacheBytes)} · '
        '提供商 ${u.providerCount}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final close = _repo.settings.closeBehavior;
    final updater = _updater;
    final check = updater?.lastCheck;
    final checking = updater?.isChecking ?? false;
    final downloading = updater?.isDownloading ?? false;
    final progress = updater?.downloadProgress;

    return ColoredBox(
      color: tokens.canvas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        children: [
          Text(
            '关于与更新',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '版本信息、直链更新与桌面关闭行为。',
            style: TextStyle(
              fontSize: 13,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'AI Studio',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本 $_versionLabel · Windows / macOS',
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  updater == null || !updater.isConfigured
                      ? '更新通道：未配置更新源'
                      : '更新通道：GitHub Releases（签名校验）',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '不上架应用商店；Windows 安装包支持中英向导（AI.Studio_*_x64-setup.exe）。',
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(
                      onPressed:
                          (checking || downloading) ? null : _onCheckUpdate,
                      child: checking
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ProgressRing(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('检查中…'),
                              ],
                            )
                          : const Text('检查更新'),
                    ),
                    const Button(
                      onPressed: null,
                      child: Text('开源许可'),
                    ),
                  ],
                ),
                if (check != null && check.hasUpdate) ...[
                  const SizedBox(height: 14),
                  _UpdateAvailableCard(
                    result: check,
                    downloading: downloading,
                    progress: progress,
                    onInstall: _onDownloadAndInstall,
                  ),
                ],
                if (downloading && progress != null) ...[
                  const SizedBox(height: 10),
                  _DownloadProgressBar(progress: progress),
                ],
                const SizedBox(height: 8),
                Text(
                  '开源许可暂未开放',
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '关闭行为',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<String>(
                  groupValue: close,
                  onChanged: (value) {
                    if (value != null) _setCloseBehavior(value);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final opt in _closeOptions) ...[
                        if (opt != _closeOptions.first) const SizedBox(height: 6),
                        _CloseBehaviorTile(
                          wire: opt.wire,
                          title: opt.label,
                          subtitle: opt.subtitle,
                          selected: close == opt.wire,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '已生效：点击标题栏关闭或系统关闭时按此偏好执行；可随时改回「每次询问」。',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '数据',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _usageSummary(),
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Button(
                      onPressed: _busy ? null : _onExport,
                      child: const Text('导出设置'),
                    ),
                    Button(
                      onPressed: _busy ? null : _onImport,
                      child: const Text('导入设置'),
                    ),
                    Tooltip(
                      message: '清除本地数据（危险操作）',
                      child: Semantics(
                        button: true,
                        label: '清除本地数据',
                        child: Button(
                          onPressed: _busy ? null : _onClearData,
                          child: const Text('清除本地数据'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '默认导出不含 API Key。含密钥导出、导入密钥与全部清除均需确认。',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _UpdateAvailableCard extends StatelessWidget {
  const _UpdateAvailableCard({
    required this.result,
    required this.downloading,
    required this.onInstall,
    this.progress,
  });

  final UpdateCheckResult result;
  final bool downloading;
  final UpdateDownloadProgress? progress;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.lerp(tokens.primary, tokens.surface, 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.lerp(tokens.primary, tokens.border, 0.5)!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现新版本 ${result.latestVersion}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '当前 ${result.currentVersion}'
            '${result.matchedPlatformKey != null ? ' · ${result.matchedPlatformKey}' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          if (result.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              result.notes.trim(),
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: downloading ? null : onInstall,
            child: downloading
                ? Text(
                    progress?.fraction != null
                        ? '下载中… ${(progress!.fraction! * 100).toStringAsFixed(0)}%'
                        : '下载中…',
                  )
                : const Text('下载并安装'),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgressBar extends StatelessWidget {
  const _DownloadProgressBar({required this.progress});

  final UpdateDownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final fraction = progress.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProgressBar(value: fraction == null ? null : fraction * 100),
        const SizedBox(height: 4),
        Text(
          fraction == null
              ? '已下载 ${_formatBytes(progress.received)}'
              : '已下载 ${_formatBytes(progress.received)} / ${_formatBytes(progress.total!)}',
          style: TextStyle(
            fontSize: 11,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const _closeOptions = <({String wire, String label, String subtitle})>[
  (
    wire: 'ask',
    label: '每次询问',
    subtitle: '弹出确认：退出 / 最小化到托盘',
  ),
  (
    wire: 'quit',
    label: '直接退出',
    subtitle: '结束进程，不保留托盘',
  ),
  (
    wire: 'tray',
    label: '最小化到托盘',
    subtitle: '窗口隐藏，托盘菜单可还原 / 退出',
  ),
];

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CloseBehaviorTile extends StatelessWidget {
  const _CloseBehaviorTile({
    required this.wire,
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final String wire;
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final border = selected
        ? Color.lerp(tokens.primary, tokens.border, 0.45)!
        : tokens.border;
    final bg = selected
        ? Color.lerp(tokens.primary, tokens.surface, 0.86)!
        : tokens.surfaceMuted;
    final fg = selected ? tokens.primaryPressed : tokens.ink;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: RadioButton<String>(
          value: wire,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
