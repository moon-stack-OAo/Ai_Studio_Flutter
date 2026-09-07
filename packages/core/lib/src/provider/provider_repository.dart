import 'package:flutter/foundation.dart';

import '../security/url_safety.dart';
import '../util/id.dart';
import 'model_classify.dart';
import 'provider_config.dart';
import 'provider_connection.dart';
import 'provider_presets.dart';
import 'provider_storage.dart';
import 'provider_type.dart';

/// 提供商仓库：列表 CRUD、选中、持久化；可挂载连通性探测。
///
/// SSE（B）接入点：
/// - [activeProvider] / [activeChatCredentials]
/// - 读取 `baseUrl` + `apiKey` + `chatModel`
class ProviderRepository extends ChangeNotifier {
  ProviderRepository({
    required this._storage,
    ProviderConnectionTester? connectionTester,
  }) : connectionTester =
            connectionTester ?? OpenAiCompatibleConnectionTester();

  final ProviderStorage _storage;
  final ProviderConnectionTester connectionTester;

  List<ProviderConfig> _providers = const [];
  String _activeProviderId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<ProviderConfig> get providers => List.unmodifiable(_providers);

  String get activeProviderId => _activeProviderId;

  ProviderConfig? get activeProvider {
    if (_providers.isEmpty) return null;
    for (final p in _providers) {
      if (p.id == _activeProviderId) return p;
    }
    return _providers.first;
  }

  /// 是否存在任一可对话提供商（空态判断）。
  bool get hasConfiguredChatProvider =>
      _providers.any((p) => p.canChat);

  /// 是否存在任一可生图提供商（空态判断）。
  bool get hasConfiguredImageProvider =>
      _providers.any((p) => p.canImage);

  /// 是否存在任一可生视频提供商（空态判断；无 videoModel 视为不使用）。
  bool get hasConfiguredVideoProvider =>
      _providers.any((p) => p.canVideo);

  /// 按能力列出可用提供商（`canChat` / `canImage` / `canVideo`）。
  ///
  /// [lastTestOk] 不参与过滤，仅供 UI 徽章。
  List<ProviderConfig> providersReadyFor(ModelKind kind) {
    return [
      for (final p in _providers)
        if (_readyForKind(p, kind)) p,
    ];
  }

  static bool _readyForKind(ProviderConfig p, ModelKind kind) {
    switch (kind) {
      case ModelKind.chat:
        return p.canChat;
      case ModelKind.image:
        return p.canImage;
      case ModelKind.video:
        return p.canVideo;
      case ModelKind.other:
        return p.enabled &&
            p.baseUrl.trim().isNotEmpty &&
            p.hasApiKey;
    }
  }

  /// B 阶段 SSE 用：当前默认对话凭据；未就绪返回 null。
  ActiveChatCredentials? get activeChatCredentials {
    final p = activeProvider;
    if (p == null || !p.canChat) return null;
    return ActiveChatCredentials(
      providerId: p.id,
      providerName: p.name,
      type: p.type,
      baseUrl: p.baseUrl.trim(),
      apiKey: p.apiKey,
      chatModel: p.chatModel.trim(),
    );
  }

  /// 生图用：当前默认生图凭据；未就绪返回 null。
  ActiveImageCredentials? get activeImageCredentials {
    final p = activeProvider;
    if (p == null || !p.canImage) return null;
    return ActiveImageCredentials(
      providerId: p.id,
      providerName: p.name,
      type: p.type,
      baseUrl: p.baseUrl.trim(),
      apiKey: p.apiKey,
      imageModel: p.imageModel.trim(),
    );
  }

  /// 生视频用：当前默认视频凭据；未就绪（含未设 videoModel）返回 null。
  ActiveVideoCredentials? get activeVideoCredentials {
    final p = activeProvider;
    if (p == null || !p.canVideo) return null;
    return ActiveVideoCredentials(
      providerId: p.id,
      providerName: p.name,
      type: p.type,
      baseUrl: p.baseUrl.trim(),
      apiKey: p.apiKey,
      videoModel: p.videoModel.trim(),
    );
  }

  /// 按 id 取提供商（恢复任务用）。
  ProviderConfig? providerById(String id) => _findById(id);

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _providers = List<ProviderConfig>.from(snap.providers);
      _activeProviderId = snap.activeProviderId;
      if (_providers.isEmpty) {
        _providers = builtinProviderPresets();
        _activeProviderId = _providers.first.id;
        await _persist();
      } else if (!_providers.any((p) => p.id == _activeProviderId)) {
        _activeProviderId = _providers.first.id;
        await _persist();
      }
      _loaded = true;
    } catch (e) {
      _lastError = '加载提供商失败：$e';
      if (_providers.isEmpty) {
        _providers = builtinProviderPresets();
        _activeProviderId = _providers.first.id;
        _loaded = true;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storage.save(
      ProviderStoreSnapshot(
        providers: _providers,
        activeProviderId: _activeProviderId,
      ),
    );
  }

  Future<void> setActiveProvider(String id) async {
    if (!_providers.any((p) => p.id == id)) return;
    _activeProviderId = id;
    await _persist();
    notifyListeners();
  }

  /// 新增自定义提供商并选中。
  Future<ProviderConfig> addProvider({
    String? name,
    ProviderType type = ProviderType.openaiCompatible,
    String baseUrl = '',
    String apiKey = '',
    String chatModel = '',
    String imageModel = '',
    String videoModel = '',
  }) async {
    final item = ProviderConfig(
      id: createId('provider'),
      name: (name ?? '').trim().isEmpty ? '自定义接口' : name!.trim(),
      type: type,
      baseUrl: baseUrl.trim(),
      apiKey: apiKey,
      chatModel: chatModel.trim(),
      imageModel: imageModel.trim(),
      videoModel: videoModel.trim(),
    );
    _providers = [..._providers, item];
    _activeProviderId = item.id;
    await _persist();
    notifyListeners();
    return item;
  }

  /// 合并更新字段并保存。
  Future<ProviderConfig?> updateProvider(
    String id, {
    String? name,
    ProviderType? type,
    String? baseUrl,
    String? apiKey,
    String? chatModel,
    String? imageModel,
    String? videoModel,
    bool? enabled,
    bool? lastTestOk,
    String? lastTestDetail,
    int? lastTestAtMs,
    bool clearLastTest = false,
  }) async {
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      assertSafeFetchUrl(baseUrl.trim());
    }
    final index = _providers.indexWhere((p) => p.id == id);
    if (index < 0) return null;
    final current = _providers[index];
    final next = current.copyWith(
      name: name,
      type: type,
      baseUrl: baseUrl,
      apiKey: apiKey,
      chatModel: chatModel,
      imageModel: imageModel,
      videoModel: videoModel,
      enabled: enabled,
      lastTestOk: lastTestOk,
      lastTestDetail: lastTestDetail,
      lastTestAtMs: lastTestAtMs,
      clearLastTest: clearLastTest,
    );
    final list = List<ProviderConfig>.from(_providers);
    list[index] = next;
    _providers = list;
    await _persist();
    notifyListeners();
    return next;
  }

  /// 用完整配置替换（表单「保存」）。
  ///
  /// [baseUrl] 非空时会做出站 URL 硬拦（见 [assertSafeFetchUrl]）。
  Future<ProviderConfig?> saveProvider(ProviderConfig config) async {
    final base = config.baseUrl.trim();
    if (base.isNotEmpty) {
      assertSafeFetchUrl(base);
    }
    final index = _providers.indexWhere((p) => p.id == config.id);
    if (index < 0) {
      _providers = [..._providers, config];
      _activeProviderId = config.id;
    } else {
      final list = List<ProviderConfig>.from(_providers);
      // 内置标记不可被表单抹掉
      final merged = config.copyWith(builtin: _providers[index].builtin);
      list[index] = merged;
      _providers = list;
    }
    await _persist();
    notifyListeners();
    return _providers.firstWhere((p) => p.id == config.id);
  }

  /// 删除非内置；至少保留一个。返回是否成功。
  Future<bool> removeProvider(String id) async {
    ProviderConfig? target;
    for (final p in _providers) {
      if (p.id == id) {
        target = p;
        break;
      }
    }
    if (target == null) return false;
    if (target.builtin) return false;
    if (_providers.length <= 1) return false;
    _providers = _providers.where((p) => p.id != id).toList();
    if (_activeProviderId == id) {
      _activeProviderId = _providers.first.id;
    }
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> resetPresets() async {
    _providers = builtinProviderPresets();
    _activeProviderId = _providers.first.id;
    await _persist();
    notifyListeners();
  }

  /// 用快照整体替换（导入备份用）。
  Future<void> replaceAll(ProviderStoreSnapshot snapshot) async {
    var providers = List<ProviderConfig>.from(snapshot.providers);
    var activeId = snapshot.activeProviderId;
    if (providers.isEmpty) {
      providers = builtinProviderPresets();
      activeId = providers.first.id;
    } else if (!providers.any((p) => p.id == activeId)) {
      activeId = providers.first.id;
    }
    _providers = providers;
    _activeProviderId = activeId;
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  ProviderConfig? _findById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 测试连接并写回 lastTest*（不把 Key 打进 detail）。
  Future<ProviderConnectionResult> testConnection(String id) async {
    final provider = _findById(id);
    if (provider == null) {
      return const ProviderConnectionResult(ok: false, detail: '提供商不存在');
    }
    final result = await connectionTester.testConnection(provider);
    await updateProvider(
      id,
      lastTestOk: result.ok,
      lastTestDetail: result.detail,
      lastTestAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    return result;
  }

  Future<List<ProviderModelInfo>> listModels(String id) async {
    final provider = _findById(id);
    if (provider == null) {
      throw StateError('提供商不存在');
    }
    return connectionTester.listModels(provider);
  }
}

/// SSE / 对话层读取当前默认 chat 凭据的轻量 DTO。
class ActiveChatCredentials {
  const ActiveChatCredentials({
    required this.providerId,
    required this.providerName,
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    required this.chatModel,
  });

  final String providerId;
  final String providerName;
  final ProviderType type;
  final String baseUrl;

  /// 完整 Key；调用方禁止写入日志。
  final String apiKey;
  final String chatModel;

  @override
  String toString() =>
      'ActiveChatCredentials(providerId: $providerId, name: $providerName, '
      'baseUrl: $baseUrl, chatModel: $chatModel, apiKey: ***)';
}

/// 生图层读取当前默认 image 凭据的轻量 DTO。
class ActiveImageCredentials {
  const ActiveImageCredentials({
    required this.providerId,
    required this.providerName,
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    required this.imageModel,
  });

  final String providerId;
  final String providerName;
  final ProviderType type;
  final String baseUrl;

  /// 完整 Key；调用方禁止写入日志。
  final String apiKey;
  final String imageModel;

  @override
  String toString() =>
      'ActiveImageCredentials(providerId: $providerId, name: $providerName, '
      'baseUrl: $baseUrl, imageModel: $imageModel, apiKey: ***)';
}

/// 生视频层读取当前默认 video 凭据的轻量 DTO。
class ActiveVideoCredentials {
  const ActiveVideoCredentials({
    required this.providerId,
    required this.providerName,
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    required this.videoModel,
  });

  final String providerId;
  final String providerName;
  final ProviderType type;
  final String baseUrl;

  /// 完整 Key；调用方禁止写入日志。
  final String apiKey;
  final String videoModel;

  @override
  String toString() =>
      'ActiveVideoCredentials(providerId: $providerId, name: $providerName, '
      'baseUrl: $baseUrl, videoModel: $videoModel, apiKey: ***)';
}
