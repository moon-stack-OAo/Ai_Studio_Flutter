import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/empty_illustrations.dart';
import '../../widgets/fluent_empty_states.dart';
import '../../widgets/prompt_assist_panel.dart';
import 'image_controller.dart';
import 'widgets/image_composer.dart';
import 'widgets/image_lightbox.dart';
import 'widgets/image_timeline.dart';

class ImagePage extends StatefulWidget {
  const ImagePage({
    super.key,
    required this.providerRepository,
    required this.sessionRepository,
    required this.generation,
    this.chatDefaultsRepository,
    this.appLogRepository,
    this.chatClient,
    this.imageClient,
    this.onOpenProviders,
  });

  final ProviderRepository providerRepository;
  final ImageSessionRepository sessionRepository;
  final GenerationRuntime generation;
  final ChatDefaultsRepository? chatDefaultsRepository;
  final AppLogRepository? appLogRepository;
  final OpenAiCompatibleChatClient? chatClient;
  final OpenAiCompatibleImageClient? imageClient;
  final VoidCallback? onOpenProviders;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  late final ImageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ImageController(
      providerRepository: widget.providerRepository,
      sessionRepository: widget.sessionRepository,
      appLogRepository: widget.appLogRepository,
      generation: widget.generation,
      imageClient: widget.imageClient,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flashBannerIfNeeded() {
    final pending = _controller.bannerError;
    if (pending == null || pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final banner = _controller.bannerError;
      if (banner == null || banner.isEmpty) return;
      _controller.clearBannerError();
      displayInfoBar(
        context,
        builder: (ctx, close) => InfoBar(
          title: Text(banner),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    });
  }

  Future<void> _openLightbox(ImageItem item, int index, ImageRef ref) async {
    await ImageLightbox.show(
      context,
      ref: ref,
      refs: item.images,
      initialIndex: index,
      loadBytes: () => widget.sessionRepository.readImageBytes(ref),
      loadBytesFor: widget.sessionRepository.readImageBytes,
      onSaveRef: _controller.saveImageAs,
    );
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
        final ready = widget.providerRepository.hasConfiguredImageProvider;
        if (!ready) {
          return FluentFeatureEmpty(
            title: '尚未配置生图模型',
            message: '前往设置添加 API Key 并选择生图模型后，即可开始文生图。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const FluentEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final items = session?.items ?? const <ImageItem>[];
        final creds = widget.providerRepository.activeImageCredentials;
        final providerLabel = creds?.providerName ?? '';
        final modelLabel = creds?.imageModel ?? '';
        final generating = _controller.isGeneratingActiveSession;
        _flashBannerIfNeeded();

        return ColoredBox(
          color: tokens.canvas,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ImageHeader(
                      providerLabel: providerLabel,
                      tokens: tokens,
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
                          label: '正在生成 ${_controller.n} 张 · 可停止',
                          child: InfoBar(
                            title: Text('正在生成 ${_controller.n} 张 · 可停止'),
                            severity: InfoBarSeverity.info,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ImageTimeline(
                        items: items,
                        loadBytes: widget.sessionRepository.readImageBytes,
                        onPreview: _openLightbox,
                        onSave: (item, index, ref) async {
                          final ok = await _controller.saveImageAs(ref);
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
                        onUseAsReference: (item, index, ref) {
                          _controller.setReferenceFromItem(ref);
                          if (context.mounted) {
                            displayInfoBar(
                              context,
                              builder: (ctx, close) => InfoBar(
                                title: const Text('已设为参考图'),
                                severity: InfoBarSeverity.success,
                                onClose: close,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              ImageComposer(
                prompt: _controller.promptDraft,
                onPromptChanged: _controller.setPromptDraft,
                n: _controller.n,
                onNChanged: _controller.setN,
                size: _controller.size,
                onSizeChanged: _controller.setSize,
                aspectRatio: _controller.aspectRatio,
                onAspectRatioChanged: _controller.setAspectRatio,
                useAspectRatio: _controller.useAspectRatio,
                sizeOptions: ImageController.sizeOptions,
                aspectOptions: ImageController.aspectOptions,
                quality: _controller.quality,
                onQualityChanged: _controller.setQuality,
                supportsQuality: _controller.supportsQuality,
                qualityOptions: ImageController.qualityOptions,
                modelLabel: modelLabel,
                providers: widget.providerRepository,
                modelsCache: _controller.modelsCache,
                referenceImage: _controller.referenceImage,
                loadReferenceBytes: widget.sessionRepository.readImageBytes,
                onClearReference: _controller.clearReference,
                onPickReference: _controller.pickReferenceImage,
                onDropReference: _controller.dropReferenceImage,
                enabled: _controller.canGenerate,
                generating: generating,
                onGenerate: _controller.generate,
                onStop: _controller.stop,
                onPromptAssist: () {
                  showFluentPromptAssist(
                    context,
                    domain: PromptDomain.image,
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

class _ImageHeader extends StatelessWidget {
  const _ImageHeader({
    required this.providerLabel,
    required this.tokens,
    this.onClear,
  });

  final String providerLabel;
  final FluentTokens tokens;
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
            '生图时间线',
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
          if (onClear != null)
            Button(
              onPressed: onClear,
              child: const Text('清空本页结果'),
            ),
        ],
      ),
    );
  }
}
