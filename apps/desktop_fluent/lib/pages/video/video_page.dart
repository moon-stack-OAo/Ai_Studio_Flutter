import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/empty_illustrations.dart';
import '../../widgets/fluent_empty_states.dart';
import '../../widgets/prompt_assist_panel.dart';
import 'video_controller.dart';
import 'widgets/video_composer.dart';
import 'widgets/video_player_dialog.dart';
import 'widgets/video_player_panel.dart';
import 'widgets/video_queue.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.providerRepository,
    required this.sessionRepository,
    required this.generation,
    this.chatDefaultsRepository,
    this.appLogRepository,
    this.chatClient,
    this.videoClient,
    this.onOpenProviders,
  });

  final ProviderRepository providerRepository;
  final VideoSessionRepository sessionRepository;
  final GenerationRuntime generation;
  final ChatDefaultsRepository? chatDefaultsRepository;
  final AppLogRepository? appLogRepository;
  final OpenAiCompatibleChatClient? chatClient;
  final OpenAiCompatibleVideoClient? videoClient;
  final VoidCallback? onOpenProviders;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoController(
      providerRepository: widget.providerRepository,
      sessionRepository: widget.sessionRepository,
      appLogRepository: widget.appLogRepository,
      generation: widget.generation,
      videoClient: widget.videoClient,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.startAutoResumeIfNeeded();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flashBannersIfNeeded() {
    final pendingError = _controller.bannerError;
    final pendingInfo = _controller.bannerInfo;
    if ((pendingError == null || pendingError.isEmpty) &&
        (pendingInfo == null || pendingInfo.isEmpty)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final info = _controller.bannerInfo;
      final banner = _controller.bannerError;
      if (info != null && info.isNotEmpty) {
        _controller.clearBannerInfo();
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: Text(info),
            severity: InfoBarSeverity.info,
            onClose: close,
          ),
        );
      }
      if (banner != null && banner.isNotEmpty) {
        _controller.clearBannerError();
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: Text(banner),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.providerRepository,
        widget.sessionRepository,
        widget.generation,
        _controller,
      ]),
      builder: (context, _) {
        final ready = widget.providerRepository.hasConfiguredVideoProvider;
        if (!ready) {
          return FluentFeatureEmpty(
            title: '尚未配置视频模型',
            message: '前往设置添加 API Key 并选择视频模型后，即可创建文生视频任务。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const FluentEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final items = session?.items ?? const <VideoItem>[];
        final creds = widget.providerRepository.activeVideoCredentials;
        final providerLabel = creds?.providerName ?? '';
        final modelLabel = creds?.videoModel ?? '';
        final generating = _controller.isGeneratingActiveSession;
        _controller.syncParamsToActiveProvider();
        _flashBannersIfNeeded();

        return ColoredBox(
          color: tokens.canvas,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VideoHeader(
                      providerLabel: providerLabel,
                      tokens: tokens,
                      hasPending: _controller.hasPendingResume,
                      onResume: _controller.resumePending,
                      onClear: items.isEmpty
                          ? null
                          : () => _controller.clearActiveItems(),
                    ),
                    if (generating)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Semantics(
                          liveRegion: true,
                          container: true,
                          label: '任务进行中 · 可取消',
                          child: const InfoBar(
                            title: Text('任务进行中 · 可取消'),
                            severity: InfoBarSeverity.info,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 11,
                              child: _QueuePanel(
                                tokens: tokens,
                                child: VideoQueue(
                                  items: items,
                                  selectedId: _controller.selectedItemId,
                                  onSelect: _controller.selectItem,
                                  onPlay: (item) {
                                    _controller.selectItem(item);
                                  },
                                  onOpen: (item) async {
                                    final ok =
                                        await _controller.openVideo(item);
                                    if (ok && context.mounted) {
                                      displayInfoBar(
                                        context,
                                        builder: (ctx, close) => InfoBar(
                                          title: const Text('已打开'),
                                          severity: InfoBarSeverity.success,
                                          onClose: close,
                                        ),
                                      );
                                    }
                                  },
                                  onSave: (item) async {
                                    final ok =
                                        await _controller.saveVideoAs(item);
                                    if (ok && context.mounted) {
                                      displayInfoBar(
                                        context,
                                        builder: (ctx, close) => InfoBar(
                                          title: const Text('已保存'),
                                          severity: InfoBarSeverity.success,
                                          onClose: close,
                                        ),
                                      );
                                    }
                                  },
                                  onReload: (item) {
                                    _controller.reloadVideo(item);
                                  },
                                  isReloading: (item) =>
                                      _controller.isReloading(item.id),
                                  onResume: (item) {
                                    _controller.resumeItem(
                                      widget.sessionRepository.activeId,
                                      item.id,
                                    );
                                  },
                                  onAbandon: (item) {
                                    _controller.abandonItem(
                                      widget.sessionRepository.activeId,
                                      item.id,
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 9,
                              child: VideoPlayerPanel(
                                item: _controller.selectedItem,
                                onOpenSystem: _controller.openVideo,
                                onSaveAs: _controller.saveVideoAs,
                                onExpand: _controller.selectedItem == null
                                    ? null
                                    : () {
                                        final item = _controller.selectedItem!;
                                        showVideoPlayerDialog(
                                          context,
                                          item: item,
                                          onOpenSystem: _controller.openVideo,
                                          onSaveAs: _controller.saveVideoAs,
                                        );
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              VideoComposer(
                prompt: _controller.promptDraft,
                onPromptChanged: _controller.setPromptDraft,
                duration: _controller.duration,
                onDurationChanged: _controller.setDuration,
                size: _controller.size,
                onSizeChanged: _controller.setSize,
                aspectRatio: _controller.aspectRatio,
                onAspectRatioChanged: _controller.setAspectRatio,
                useAspectRatio: _controller.useAspectRatio,
                showSize: _controller.showSize,
                useResolution: _controller.useResolution,
                resolution: _controller.resolution,
                onResolutionChanged: _controller.setResolution,
                resolutionOptions: VideoController.resolutionOptions,
                durationOptions: _controller.activeDurationOptions,
                sizeOptions: _controller.activeSizeOptions,
                aspectOptions: _controller.activeAspectOptions,
                modelLabel: modelLabel,
                providers: widget.providerRepository,
                modelsCache: _controller.modelsCache,
                referenceImage: _controller.referenceImage,
                onClearReference: _controller.clearReference,
                onPickReference: _controller.pickReferenceImage,
                onDropReference: _controller.dropReferenceImage,
                supportsReferenceImage: _controller.supportsReferenceImage,
                enabled: _controller.canGenerate,
                generating: generating,
                onGenerate: _controller.generate,
                onStop: _controller.stop,
                onProviderSwitched: _controller.syncParamsToActiveProvider,
                onPromptAssist: () {
                  showFluentPromptAssist(
                    context,
                    domain: PromptDomain.video,
                    mode: _controller.promptAssistMode,
                    draftPrompt: _controller.promptDraft,
                    providerRepository: widget.providerRepository,
                    chatDefaultsRepository: widget.chatDefaultsRepository,
                    chatClient: widget.chatClient,
                    onApply: _controller.applyPromptPreset,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.tokens, required this.child});

  final FluentTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Text(
                  '任务队列',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const Spacer(),
                Text(
                  '按状态筛选 · 回合时间分隔',
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _VideoHeader extends StatelessWidget {
  const _VideoHeader({
    required this.providerLabel,
    required this.tokens,
    required this.hasPending,
    required this.onResume,
    this.onClear,
  });

  final String providerLabel;
  final FluentTokens tokens;
  final bool hasPending;
  final VoidCallback onResume;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Text(
            '生视频工作区',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
          if (providerLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tokens.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    providerLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkSecondary,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (hasPending)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Button(
                onPressed: onResume,
                child: const Text('恢复未完成'),
              ),
            ),
          if (onClear != null)
            Button(
              onPressed: onClear,
              child: const Text('清空结果'),
            ),
        ],
      ),
    );
  }
}
