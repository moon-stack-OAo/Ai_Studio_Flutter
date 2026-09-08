import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../chat/generation_gates.dart';
import '../chat/generation_runtime.dart';
import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../provider/provider_connection.dart';
import '../provider/provider_models_cache.dart';
import '../provider/provider_repository.dart';
import '../provider/provider_type.dart';
import '../security/safe_http_client.dart';
import 'image_client.dart';
import 'image_models.dart';
import 'image_quality.dart';
import 'image_session_repository.dart';

/// 生图 generate / stop 编排（无 UI 绑定，DESIGN.md §5.1）。
///
/// 持有参数状态、门闩、[ProviderModelsCache]；参考图字节由 app 解析后传入
/// [generate]。app 层 [ChangeNotifier] 仅做薄包装与平台 IO。
class ImageSessionFacade {
  ImageSessionFacade({
    required ProviderRepository providers,
    required ImageSessionRepository sessions,
    required this.generation,
    AppLogRepository? appLogs,
    OpenAiCompatibleImageClient? imageClient,
    http.Client Function()? createHttpClient,
    VoidCallback? onModelsChanged,
  })  : _providers = providers,
        _sessions = sessions,
        _appLogs = appLogs,
        _ownsClient = imageClient == null,
        _imageClient = imageClient ?? OpenAiCompatibleImageClient(),
        _createHttpClient = createHttpClient ?? createSafeHttpClient,
        modelsCache = ProviderModelsCache(
          providers: providers,
          onChanged: onModelsChanged,
        );

  final ProviderRepository _providers;
  final ImageSessionRepository _sessions;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleImageClient _imageClient;
  final bool _ownsClient;
  final http.Client Function() _createHttpClient;

  final ProviderModelsCache modelsCache;

  int _n = 1;
  String _size = '1024x1024';
  String _aspectRatio = '1:1';
  String _quality = defaultImageQuality;
  String _promptDraft = '';

  static const sizeOptions = <String>[
    '1024x1024',
    '1024x1792',
    '1792x1024',
  ];

  static const aspectOptions = <String>[
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
  ];

  static const qualityOptions = imageQualityOptions;

  ImageSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

  OpenAiCompatibleImageClient get imageClient => _imageClient;

  int get n => _n;
  String get size => _size;
  String get aspectRatio => _aspectRatio;
  String get quality => _quality;
  String get promptDraft => _promptDraft;

  bool get isGeneratingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get canGenerate => canGenerateImage(
        generation: generation,
        activeSessionId: _sessions.activeId,
        hasConfiguredImageProvider: _providers.hasConfiguredImageProvider,
        promptDraft: _promptDraft,
      );

  bool get useAspectRatio {
    final creds = _providers.activeImageCredentials;
    return creds?.type == ProviderType.xai;
  }

  bool get supportsQuality =>
      supportsImageQualityForProvider(_providers.activeProvider);

  void setPromptDraft(String value, {VoidCallback? onNotify}) {
    if (value == _promptDraft) return;
    _promptDraft = value;
    onNotify?.call();
  }

  void setN(int value, {VoidCallback? onNotify}) {
    final next = value.clamp(1, 4);
    if (next == _n) return;
    _n = next;
    onNotify?.call();
  }

  void setSize(String value, {VoidCallback? onNotify}) {
    if (value == _size) return;
    _size = value;
    onNotify?.call();
  }

  void setAspectRatio(String value, {VoidCallback? onNotify}) {
    if (value == _aspectRatio) return;
    _aspectRatio = value;
    onNotify?.call();
  }

  void setQuality(String value, {VoidCallback? onNotify}) {
    final next = value.trim();
    if (next.isEmpty || next == _quality) return;
    _quality = next;
    onNotify?.call();
  }

  void applyPromptPreset(String prompt, {VoidCallback? onNotify}) {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _promptDraft = text;
    onNotify?.call();
  }

  /// 拉取生图模型列表（仅 [ProviderConfig.canImage]）。
  Future<List<ProviderModelInfo>> loadImageModels({
    bool force = false,
    bool silentRefreshIfStale = true,
  }) {
    return modelsCache.load(
      force: force,
      silentRefreshIfStale: silentRefreshIfStale,
      canUse: (p) => p.canImage,
    );
  }

  void stop() {
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  /// 读取 [ImageRef] 字节（file / b64 走会话资产；url 走 HTTP）。
  Future<Uint8List?> resolveImageBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
      case ImageRefType.b64:
        return _sessions.readImageBytes(ref);
      case ImageRefType.url:
        final client = _createHttpClient();
        try {
          final res = await client.get(Uri.parse(ref.src));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            return res.bodyBytes;
          }
        } catch (_) {
        } finally {
          client.close();
        }
        return null;
    }
  }

  /// 文生 / 图生编排。参考图由 app 先读成 [imageBytes] 再传入。
  ///
  /// [bannerOnGenerateError] 为 true 时，非取消类错误也会 [onBanner]
  ///（移动端）；桌面可保持 false，仅写日志。
  Future<void> generate({
    String? prompt,
    int? n,
    String? size,
    String? aspectRatio,
    String? quality,
    Uint8List? imageBytes,
    String? imageFileName,
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    bool bannerOnGenerateError = false,
    bool clearPromptDraft = true,
  }) async {
    final text = (prompt ?? _promptDraft).trim();
    if (text.isEmpty) return;

    final useN = n ?? _n;
    final useSize = size ?? _size;
    final useAspect = aspectRatio ?? _aspectRatio;
    final useQuality = quality ?? _quality;

    final creds = _providers.activeImageCredentials;
    if (creds == null) {
      onBanner?.call('请先配置提供商生图模型与 API Key');
      return;
    }

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    final sessionId = session.id;

    if (isGenerationBlocked(
      generation: generation,
      activeSessionId: sessionId,
    )) {
      return;
    }

    final refBytes =
        (imageBytes != null && imageBytes.isNotEmpty) ? imageBytes : null;
    final isEdit = refBytes != null;
    final refPreview = isEdit ? 'ref:${refBytes.length}' : null;
    final refName = (imageFileName ?? 'image.png').trim();
    final effectiveRefName = refName.isEmpty ? 'image.png' : refName;

    if (clearPromptDraft) {
      _promptDraft = '';
    }
    onBanner?.call(null);
    onNotify();

    final qualityParam = supportsQuality ? useQuality : null;
    final passAspect = useAspectRatio;
    final pending = await _sessions.appendLoadingItem(
      sessionId,
      mode: isEdit ? ImageGenMode.edit : ImageGenMode.text,
      prompt: text,
      model: creds.imageModel,
      providerName: creds.providerName,
      n: useN,
      size: passAspect ? null : useSize,
      aspectRatio: passAspect ? useAspect : null,
      quality: qualityParam,
      refPreview: refPreview,
    );
    if (pending == null) return;

    final httpClient = _createHttpClient();
    final token = generation.begin(sessionId, httpClient.close);
    onNotify();

    try {
      final List<ImageRef> refs;
      if (isEdit) {
        refs = await _imageClient.editImage(
          baseUrl: creds.baseUrl,
          apiKey: creds.apiKey,
          model: creds.imageModel,
          providerType: creds.type,
          prompt: text,
          imageBytes: refBytes,
          imageFileName: effectiveRefName,
          n: useN,
          size: passAspect ? null : useSize,
          aspectRatio: passAspect ? useAspect : null,
          quality: qualityParam,
          client: httpClient,
        );
      } else {
        refs = await _imageClient.generateTextToImageWithCredentials(
          creds,
          prompt: text,
          n: useN,
          size: passAspect ? null : useSize,
          aspectRatio: passAspect ? useAspect : null,
          quality: qualityParam,
          client: httpClient,
        );
      }
      await _sessions.completeItem(sessionId, pending.id, refs);
    } on ChatAbortException {
      await _sessions.failItem(sessionId, pending.id, '已取消');
    } catch (e) {
      if (isAbortLike(e)) {
        await _sessions.failItem(sessionId, pending.id, '已取消');
      } else {
        final msg = toChatErrorMessage(e, '生成失败');
        await _sessions.failItem(sessionId, pending.id, msg);
        if (bannerOnGenerateError) {
          onBanner?.call(msg);
        }
        final logs = _appLogs;
        if (logs != null) {
          unawaited(
            logs.append(
              level: AppLogLevel.error,
              source: AppLogSources.image,
              message: msg,
            ),
          );
        }
      }
    } finally {
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      onNotify();
    }
  }

  void dispose() {
    modelsCache.dispose();
    if (_ownsClient) _imageClient.close();
  }
}
