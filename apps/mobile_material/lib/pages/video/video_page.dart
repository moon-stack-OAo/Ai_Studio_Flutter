import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../platform/gallery_saver.dart';
import '../../platform/share_helper.dart';
import '../../shell/back_host.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';
import '../../widgets/media_model_picker_sheet.dart';
import '../../widgets/prompt_assist_sheet.dart';
import 'video_controller.dart';
import 'widgets/video_composer.dart';
import 'widgets/video_player_page.dart';
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
  final ScrollController _scroll = ScrollController();
  String? _lastBanner;
  String? _lastInfo;
  int _lastItemCount = 0;
  String _lastTail = '';

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
    _controller.addListener(_onControllerChanged);
    widget.sessionRepository.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.startAutoResumeIfNeeded();
      _maybeScrollToBottom();
    });
  }

  void _onSessionChanged() => _maybeScrollToBottom();

  void _maybeScrollToBottom() {
    final session = widget.sessionRepository.activeSession;
    final items = session?.items ?? const <VideoItem>[];
    final count = items.length;
    final tail = items.isEmpty
        ? ''
        : () {
            final last = items.reduce(
              (a, b) => a.createdAt >= b.createdAt ? a : b,
            );
            return '${last.id}:${last.status.name}:${last.progress}';
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
    if (!mounted) return;
    final banner = _controller.bannerError;
    if (banner != null &&
        banner.isNotEmpty &&
        banner != _lastBanner) {
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

    final info = _controller.bannerInfo;
    if (info != null && info.isNotEmpty && info != _lastInfo) {
      _lastInfo = info;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(info),
          action: SnackBarAction(
            label: '关闭',
            onPressed: _controller.clearBannerInfo,
          ),
        ),
      );
    }
    if (info == null) _lastInfo = null;
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
              return _VideoSessionListPage(
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

  Future<void> _pickVideoModel() async {
    final ready =
        widget.providerRepository.providersReadyFor(ModelKind.video);
    if (ready.isEmpty) return;
    await showMediaModelPickerSheet(
      context: context,
      providers: widget.providerRepository,
      modelsCache: _controller.modelsCache,
      kind: ModelKind.video,
    );
  }

  Future<void> _onSaveAlbum(VideoItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('正在保存到相册…')));

    final result = await _saveVideoToGallery(item);
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

  Future<void> _onShare(VideoItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final path = await _resolveLocalVideoPath(item);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('没有可分享的本地文件')),
      );
      return;
    }

    final result = await _shareHelper.shareLocalFile(
      path,
      mimeType: 'video/mp4',
    );
    if (!mounted) return;
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '分享失败')),
      );
    }
  }

  Future<String?> _resolveLocalVideoPath(VideoItem item) async {
    final local = item.localPath?.trim();
    if (local == null || local.isEmpty) return null;
    if (local.startsWith('http') ||
        local.startsWith('memory://') ||
        local.startsWith('data:')) {
      return null;
    }
    final path =
        local.startsWith('file:') ? Uri.parse(local).toFilePath() : local;
    final f = File(path);
    if (await f.exists()) return path;
    return null;
  }

  Future<GallerySaveResult> _saveVideoToGallery(VideoItem item) async {
    final local = item.localPath?.trim();
    if (local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        !local.startsWith('memory://') &&
        !local.startsWith('data:')) {
      final f = File(local);
      if (await f.exists()) {
        return _gallerySaver.saveVideoFile(local);
      }
    }

    final remote = (item.remoteVideoUrl ?? item.videoUrl ?? '').trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(remote)) {
      try {
        final res = await http.get(Uri.parse(remote));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return GallerySaveResult.failure(
            '下载视频失败：HTTP ${res.statusCode}',
          );
        }
        if (res.bodyBytes.isEmpty) {
          return GallerySaveResult.failure('视频数据为空');
        }
        return _gallerySaver.saveVideoBytes(res.bodyBytes);
      } catch (e) {
        return GallerySaveResult.failure('下载视频失败：$e');
      }
    }

    // 走控制器另存逻辑拿字节：落文档目录副本再写入相册
    final path = await _controller.saveVideoCopy(item);
    if (path == null || path.isEmpty) {
      return GallerySaveResult.failure(
        _controller.bannerError ?? '无法读取视频数据',
      );
    }
    try {
      final result = await _gallerySaver.saveVideoFile(path);
      return result;
    } finally {
      // 另存副本保留；相册写入不删除用户副本
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
        final ready = widget.providerRepository.hasConfiguredVideoProvider;
        if (!ready) {
          return MaterialFeatureEmpty(
            appBarTitle: '生视频',
            title: '尚未配置视频模型',
            message: '前往设置添加 API Key 并选择视频模型后，即可创建文生视频任务。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const MaterialEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final items = session?.items ?? const <VideoItem>[];
        final creds = widget.providerRepository.activeVideoCredentials;
        final modelLabel = creds == null
            ? ''
            : '${creds.providerName} · ${creds.videoModel}';
        final generating = _controller.isGeneratingActiveSession;
        final modelPickerEnabled = !generating &&
            widget.providerRepository
                .providersReadyFor(ModelKind.video)
                .isNotEmpty;
        final title = session?.title ?? '新视频';
        _controller.syncParamsToActiveProvider();

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
              if (_controller.hasPendingResume)
                TextButton(
                  onPressed: _controller.resumePending,
                  child: const Text('恢复'),
                ),
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
                  label: '任务进行中 · 可取消',
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
                              '任务进行中 · 可取消',
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
                        child: VideoComposer(
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
                          refBytes: _controller.refBytes,
                          onPickRef: _controller.pickRefImage,
                          onClearRef: _controller.clearRefImage,
                          supportsReferenceImage:
                              _controller.supportsReferenceImage,
                          enabled: _controller.canGenerate,
                          generating: generating,
                          onGenerate: _controller.generate,
                          onStop: _controller.stop,
                          onPickModel: _pickVideoModel,
                          modelPickerEnabled: modelPickerEnabled,
                          onPromptAssist: () {
                            showMaterialPromptAssist(
                              context,
                              domain: PromptDomain.video,
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
                      sliver: SliverToBoxAdapter(
                        child: VideoQueue(
                          items: items,
                          onPlay: (item) {
                            Navigator.of(context).push<void>(
                              materialFadeSlideRoute(
                                builder: (_) => VideoPlayerPage(
                                  item: item,
                                  onSaveAlbum: _onSaveAlbum,
                                  onShare: _onShare,
                                  onOpenSystem: _controller.openVideo,
                                ),
                              ),
                            );
                          },
                          onOpen: (item) async {
                            final ok = await _controller.openVideo(item);
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已打开')),
                              );
                            }
                          },
                          onSave: (item) async {
                            final path =
                                await _controller.saveVideoCopy(item);
                            if (path != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已保存：$path')),
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
                          onSaveAlbum: _onSaveAlbum,
                          onShare: _onShare,
                        ),
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

class _VideoSessionListPage extends StatelessWidget {
  const _VideoSessionListPage({
    required this.sessions,
    required this.activeId,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    this.busySessionId,
  });

  final List<VideoSession> sessions;
  final String activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<String> onDelete;
  final String? busySessionId;

  Future<void> _confirmDelete(
    BuildContext context,
    VideoSession session,
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
          title: const Text('生视频会话'),
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
                message: '还没有生视频会话，新建一条开始。',
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
                                    Icons.videocam_outlined,
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
