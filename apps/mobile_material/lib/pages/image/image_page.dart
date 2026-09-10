import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/gallery_saver.dart';
import '../../platform/share_helper.dart';
import '../../shell/back_host.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';
import '../../widgets/media_model_picker_sheet.dart';
import '../../widgets/prompt_assist_sheet.dart';
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
  final ScrollController _scroll = ScrollController();
  String? _lastBanner;
  int _lastItemCount = 0;
  String _lastTail = '';

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
    _controller.addListener(_onControllerChanged);
    widget.sessionRepository.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToBottom());
  }

  void _onSessionChanged() => _maybeScrollToBottom();

  void _maybeScrollToBottom() {
    final session = widget.sessionRepository.activeSession;
    final items = session?.items ?? const <ImageItem>[];
    final count = items.length;
    final tail = items.isEmpty
        ? ''
        : () {
            final last = items.reduce(
              (a, b) => a.createdAt >= b.createdAt ? a : b,
            );
            return '${last.id}:${last.status.name}:${last.images.length}';
          }();
    if (count == _lastItemCount && tail == _lastTail) return;
    _lastItemCount = count;
    _lastTail = tail;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _onControllerChanged() {
    final banner = _controller.bannerError;
    if (banner != null &&
        banner.isNotEmpty &&
        banner != _lastBanner &&
        mounted) {
      _lastBanner = banner;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(banner),
          action: SnackBarAction(
            label: '关闭',
            onPressed: _controller.clearBannerError,
          ),
        ),
      );
    }
    if (banner == null) _lastBanner = null;
    _maybeScrollToBottom();
  }

  @override
  void dispose() {
    widget.sessionRepository.removeListener(_onSessionChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSessions() async {
    await Navigator.of(context).push<void>(
      materialFadeSlideRoute(
        builder: (context) {
          return ListenableBuilder(
            listenable: Listenable.merge([
              widget.sessionRepository,
              widget.generation,
            ]),
            builder: (context, _) {
              return _ImageSessionListPage(
                sessions: widget.sessionRepository.sortedSessions,
                activeId: widget.sessionRepository.activeId,
                busySessionId: widget.generation.sessionId,
                onSelect: (id) => _controller.setActiveSession(id),
                onCreate: () => _controller.createSession(),
                onDelete: (id) => _controller.removeSession(id),
              );
            },
          );
        },
      ),
    );
  }

  final GallerySaver _gallerySaver = const GallerySaver();
  final ShareHelper _shareHelper = const ShareHelper();

  Future<void> _openLightbox(ImageItem item, int index, ImageRef ref) async {
    await ImageLightbox.show(
      context,
      ref: ref,
      loadBytes: () => widget.sessionRepository.readImageBytes(ref),
      onSaveAlbum: () => _onSaveAlbum(item, index, ref),
      onShare: () => _onShare(item, index, ref),
      onUseAsReference: () => _onUseAsReference(item, index, ref),
    );
  }

  Future<void> _onUseAsReference(
    ImageItem item,
    int index,
    ImageRef ref,
  ) async {
    await _controller.setReferenceFromItem(ref);
    if (!mounted) return;
    if (_controller.bannerError != null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('已设为参考图')));
  }

  Future<void> _pickImageModel() async {
    final ready =
        widget.providerRepository.providersReadyFor(ModelKind.image);
    if (ready.isEmpty) return;
    await showMediaModelPickerSheet(
      context: context,
      providers: widget.providerRepository,
      modelsCache: _controller.modelsCache,
      kind: ModelKind.image,
      onProviderSwitched: _controller.syncParamsToActiveProvider,
    );
  }

  Future<void> _onSaveAlbum(ImageItem item, int index, ImageRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('正在保存到相册…')));

    final result = await _saveImageRefToGallery(ref);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (result.ok) {
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '保存到相册失败')),
      );
    }
  }

  Future<void> _onShare(ImageItem item, int index, ImageRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final path = await _resolveLocalImagePath(ref);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('没有可分享的本地文件')),
      );
      return;
    }

    final result = await _shareHelper.shareLocalFile(
      path,
      mimeType: 'image/png',
    );
    if (!mounted) return;
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '分享失败')),
      );
    }
  }

  Future<String?> _resolveLocalImagePath(ImageRef ref) async {
    if (ref.type == ImageRefType.file) {
      final path = ref.src.trim();
      if (path.isEmpty) return null;
      final file = File(path);
      if (await file.exists()) return path;
    }
    return null;
  }

  Future<GallerySaveResult> _saveImageRefToGallery(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
        final path = ref.src.trim();
        if (path.isEmpty) {
          return GallerySaveResult.failure('图片路径为空');
        }
        final file = File(path);
        if (await file.exists()) {
          return _gallerySaver.saveImageFile(path);
        }
        final bytes = await widget.sessionRepository.readImageBytes(ref);
        if (bytes == null || bytes.isEmpty) {
          return GallerySaveResult.failure('无法读取图片数据');
        }
        return _gallerySaver.saveImageBytes(bytes);
      case ImageRefType.b64:
        final bytes = await widget.sessionRepository.readImageBytes(ref);
        if (bytes == null || bytes.isEmpty) {
          return GallerySaveResult.failure('无法读取图片数据');
        }
        return _gallerySaver.saveImageBytes(bytes);
      case ImageRefType.url:
        final url = ref.src.trim();
        if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
          return GallerySaveResult.failure('无效的图片地址');
        }
        final client = createSafeHttpClient();
        try {
          final res = await client.get(Uri.parse(url));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            return GallerySaveResult.failure('下载图片失败：HTTP ${res.statusCode}');
          }
          final bytes = res.bodyBytes;
          if (bytes.isEmpty) {
            return GallerySaveResult.failure('图片数据为空');
          }
          // 优先写临时文件再 putImage，兼容大图
          final dir = await getTemporaryDirectory();
          final tmp = File(
            '${dir.path}${Platform.pathSeparator}'
            'ai-studio-gallery-${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await tmp.writeAsBytes(bytes, flush: true);
          try {
            return await _gallerySaver.saveImageFile(tmp.path);
          } finally {
            try {
              if (await tmp.exists()) await tmp.delete();
            } catch (_) {}
          }
        } catch (e) {
          return GallerySaveResult.failure('下载图片失败：$e');
        } finally {
          client.close();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
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
          return MaterialFeatureEmpty(
            appBarTitle: '生图',
            title: '尚未配置生图模型',
            message: '前往设置添加 API Key 并选择生图模型后，即可开始文生图。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const MaterialEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final items = session?.items ?? const <ImageItem>[];
        final creds = widget.providerRepository.activeImageCredentials;
        final modelLabel = creds == null
            ? ''
            : '${creds.providerName} · ${creds.imageModel}';
        final generating = _controller.isGeneratingActiveSession;
        final modelPickerEnabled = !generating &&
            widget.providerRepository
                .providersReadyFor(ModelKind.image)
                .isNotEmpty;
        final title = session?.title ?? '新生图';

        return Scaffold(
          backgroundColor: tokens.canvas,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              tooltip: '会话列表',
              icon: const Icon(Icons.menu),
              onPressed: _openSessions,
            ),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  tooltip: '清空结果',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _controller.clearActiveItems(),
                ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (generating)
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: '正在生成 ${_controller.n} 张 · 可停止',
                  child: Material(
                    color: tokens.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '正在生成 ${_controller.n} 张 · 可停止',
                              style: TextStyle(
                                fontSize: 13,
                                color: tokens.inkSecondary,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      sliver: SliverToBoxAdapter(
                        child: ImageComposer(
                          prompt: _controller.promptDraft,
                          onPromptChanged: _controller.setPromptDraft,
                          n: _controller.n,
                          onNChanged: _controller.setN,
                          size: _controller.size,
                          onSizeChanged: _controller.setSize,
                          aspectRatio: _controller.aspectRatio,
                          onAspectRatioChanged: _controller.setAspectRatio,
                          useAspectRatio: _controller.useAspectRatio,
                          showSize: _controller.showSize,
                          sizeOptions: _controller.activeSizeOptions,
                          aspectOptions: _controller.activeAspectOptions,
                          quality: _controller.quality,
                          onQualityChanged: _controller.setQuality,
                          supportsQuality: _controller.supportsQuality,
                          qualityOptions: ImageController.qualityOptions,
                          modelLabel: modelLabel,
                          enabled: _controller.canGenerate,
                          generating: generating,
                          onGenerate: _controller.generate,
                          onStop: _controller.stop,
                          refBytes: _controller.refBytes,
                          onPickRef: _controller.pickRefImage,
                          onClearRef: _controller.clearRefImage,
                          onPickModel: _pickImageModel,
                          modelPickerEnabled: modelPickerEnabled,
                          onPromptAssist: () {
                            showMaterialPromptAssist(
                              context,
                              domain: PromptDomain.image,
                              mode: _controller.promptAssistMode,
                              draftPrompt: _controller.promptDraft,
                              providerRepository: widget.providerRepository,
                              chatDefaultsRepository:
                                  widget.chatDefaultsRepository,
                              chatClient: widget.chatClient,
                              onApply: _controller.applyPromptPreset,
                            );
                          },
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      sliver: _TimelineSliver(
                        items: items,
                        loadBytes: widget.sessionRepository.readImageBytes,
                        onPreview: _openLightbox,
                        onSaveAlbum: _onSaveAlbum,
                        onShare: _onShare,
                        onUseAsReference: _onUseAsReference,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineSliver extends StatelessWidget {
  const _TimelineSliver({
    required this.items,
    required this.loadBytes,
    required this.onPreview,
    required this.onSaveAlbum,
    this.onShare,
    this.onUseAsReference,
  });

  final List<ImageItem> items;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSaveAlbum;
  final void Function(ImageItem item, int index, ImageRef ref)? onShare;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: MaterialContentEmpty(
          hint: '还没有生成结果',
          subtitle: '在上方填写提示词后生成。',
          illustration: MaterialEmptyIllustration.noImages(),
        ),
      );
    }

    final sorted = List<ImageItem>.from(items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ImageTimelineTurn(
              item: sorted[index],
              turnIndex: index + 1,
              loadBytes: loadBytes,
              onPreview: onPreview,
              onSaveAlbum: onSaveAlbum,
              onShare: onShare,
              onUseAsReference: onUseAsReference,
            ),
          );
        },
        childCount: sorted.length,
      ),
    );
  }
}

class _ImageSessionListPage extends StatelessWidget {
  const _ImageSessionListPage({
    required this.sessions,
    required this.activeId,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    this.busySessionId,
  });

  final List<ImageSession> sessions;
  final String activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<String> onDelete;
  final String? busySessionId;

  Future<void> _confirmDelete(
    BuildContext context,
    ImageSession session,
  ) async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除会话',
      message: '确定删除「${session.title}」？',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (ok) onDelete(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return BackHost(
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          title: const Text('生图会话'),
          leading: BackHost.leadingButton(context),
          actions: [
            IconButton(
              tooltip: '新建',
              icon: const Icon(Icons.add),
              onPressed: () {
                onCreate();
                BackHost.pop(context);
              },
            ),
          ],
        ),
        body: sessions.isEmpty
            ? MaterialSessionListEmpty(
                message: '还没有生图会话，新建一条开始。',
                onCreate: () {
                  onCreate();
                  BackHost.pop(context);
                },
                illustration: const MaterialEmptyIllustration.noSessions(),
              )
            : ListView.separated(
                itemCount: sessions.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: tokens.border,
                ),
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  final active = s.id == activeId;
                  final busy = s.id == busySessionId;
                  final status = busy ? '生成中' : '本地会话';
                  final label = active
                      ? '${s.title}，$status，已选中'
                      : '${s.title}，$status';
                  return Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: active,
                          label: label,
                          excludeSemantics: true,
                          child: ListTile(
                            selected: active,
                            leading: busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.image_outlined,
                                    color: active
                                        ? tokens.primary
                                        : tokens.inkMuted,
                                  ),
                            title: Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${s.items.length} 条结果'),
                            onTap: () {
                              onSelect(s.id);
                              BackHost.pop(context);
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除会话',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, s),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
