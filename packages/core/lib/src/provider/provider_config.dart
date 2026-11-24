import 'provider_type.dart';
import 'model_capabilities.dart';

/// 本机提供商配置（密钥可随实例持有，序列化时由仓库决定是否落盘明文）。
class ProviderConfig {
  ProviderConfig({
    required this.id,
    required this.name,
    required this.type,
    this.baseUrl = '',
    this.apiKey = '',
    this.chatModel = '',
    this.imageModel = '',
    this.videoModel = '',
    this.enabled = true,
    this.builtin = false,
    Map<String, ModelCapabilityOverride> modelCapabilityOverrides = const {},
    this.hasModelCapabilityOverrides = false,
    this.lastTestOk,
    this.lastTestDetail,
    this.lastTestAtMs,
  }) : _modelCapabilityOverrides = Map.unmodifiable({
         for (final entry in modelCapabilityOverrides.entries)
           if (entry.key.trim().isNotEmpty && !entry.value.isAutomatic)
             entry.key.trim(): entry.value,
       });

  final Map<String, ModelCapabilityOverride> _modelCapabilityOverrides;
  Map<String, ModelCapabilityOverride> get modelCapabilityOverrides =>
      Map.unmodifiable(_modelCapabilityOverrides);

  /// Retains absent vs explicit empty when importing legacy backups.
  final bool hasModelCapabilityOverrides;
  ChatModelCapabilities capabilitiesFor(String modelId) =>
      resolveChatModelCapabilities(
        modelId,
        _modelCapabilityOverrides[modelId.trim()],
      );

  final String id;
  final String name;
  final ProviderType type;
  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String imageModel;
  final String videoModel;
  final bool enabled;
  final bool builtin;
  final bool? lastTestOk;
  final String? lastTestDetail;
  final int? lastTestAtMs;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  bool get hasChatModel => chatModel.trim().isNotEmpty;

  bool get hasImageModel => imageModel.trim().isNotEmpty;

  /// 是否具备发起对话的最低配置（供空态 / SSE 预检）。
  bool get canChat =>
      enabled && baseUrl.trim().isNotEmpty && hasApiKey && hasChatModel;

  /// 是否具备发起生图的最低配置。
  bool get canImage =>
      enabled && baseUrl.trim().isNotEmpty && hasApiKey && hasImageModel;

  bool get hasVideoModel => videoModel.trim().isNotEmpty;

  /// 是否具备发起生视频的最低配置（videoModel 可空表示不使用）。
  bool get canVideo =>
      enabled && baseUrl.trim().isNotEmpty && hasApiKey && hasVideoModel;

  /// UI / 日志用掩码，永不返回完整 Key。
  String get maskedApiKey {
    final key = apiKey.trim();
    if (key.isEmpty) return '';
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 3)}••••${key.substring(key.length - 4)}';
  }

  ProviderConfig copyWith({
    String? id,
    String? name,
    ProviderType? type,
    String? baseUrl,
    String? apiKey,
    String? chatModel,
    String? imageModel,
    String? videoModel,
    bool? enabled,
    bool? builtin,
    bool? lastTestOk,
    String? lastTestDetail,
    int? lastTestAtMs,
    bool clearLastTest = false,
    Map<String, ModelCapabilityOverride>? modelCapabilityOverrides,
    bool? hasModelCapabilityOverrides,
  }) {
    return ProviderConfig(
      modelCapabilityOverrides:
          ((baseUrl != null && baseUrl.trim() != this.baseUrl.trim()) ||
              (type != null && type != this.type))
          ? const {}
          : (modelCapabilityOverrides ?? this.modelCapabilityOverrides),
      hasModelCapabilityOverrides:
          hasModelCapabilityOverrides ??
          (modelCapabilityOverrides != null ||
              this.hasModelCapabilityOverrides ||
              (baseUrl != null && baseUrl.trim() != this.baseUrl.trim()) ||
              (type != null && type != this.type)),
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      chatModel: chatModel ?? this.chatModel,
      imageModel: imageModel ?? this.imageModel,
      videoModel: videoModel ?? this.videoModel,
      enabled: enabled ?? this.enabled,
      builtin: builtin ?? this.builtin,
      lastTestOk: clearLastTest ? null : (lastTestOk ?? this.lastTestOk),
      lastTestDetail: clearLastTest
          ? null
          : (lastTestDetail ?? this.lastTestDetail),
      lastTestAtMs: clearLastTest ? null : (lastTestAtMs ?? this.lastTestAtMs),
    );
  }

  /// 元数据 JSON（不含 apiKey）。
  Map<String, dynamic> toJsonMeta() => {
    if (hasModelCapabilityOverrides || _modelCapabilityOverrides.isNotEmpty)
      'modelCapabilityOverrides': {
        for (final e in _modelCapabilityOverrides.entries)
          if (!e.value.isAutomatic) e.key: e.value.toJson(),
      },
    'id': id,
    'name': name,
    'type': type.wireName,
    'baseUrl': baseUrl,
    'chatModel': chatModel,
    'imageModel': imageModel,
    'videoModel': videoModel,
    'enabled': enabled,
    'builtin': builtin,
    if (lastTestOk != null) 'lastTestOk': lastTestOk,
    if (lastTestDetail != null) 'lastTestDetail': lastTestDetail,
    if (lastTestAtMs != null) 'lastTestAtMs': lastTestAtMs,
  };

  /// 完整 JSON（含 apiKey，仅内存/测试用；禁止打日志）。
  Map<String, dynamic> toJson() => {...toJsonMeta(), 'apiKey': apiKey};

  factory ProviderConfig.fromJson(
    Map<String, dynamic> json, {
    String apiKey = '',
  }) {
    return ProviderConfig(
      modelCapabilityOverrides: decodeModelCapabilityOverrides(
        json['modelCapabilityOverrides'],
      ),
      hasModelCapabilityOverrides: json.containsKey('modelCapabilityOverrides'),
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'provider_unknown',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '未命名',
      type: ProviderType.fromWire(
        (json['type'] as String?) ?? (json['provider'] as String?),
      ),
      baseUrl: (json['baseUrl'] as String?)?.trim() ?? '',
      apiKey: apiKey.isNotEmpty ? apiKey : ((json['apiKey'] as String?) ?? ''),
      chatModel: (json['chatModel'] as String?)?.trim() ?? '',
      imageModel: (json['imageModel'] as String?)?.trim() ?? '',
      videoModel: (json['videoModel'] as String?)?.trim() ?? '',
      enabled: json['enabled'] != false,
      builtin: json['builtin'] == true,
      lastTestOk: json['lastTestOk'] as bool?,
      lastTestDetail: json['lastTestDetail'] as String?,
      lastTestAtMs: (json['lastTestAtMs'] as num?)?.toInt(),
    );
  }

  @override
  String toString() =>
      'ProviderConfig(id: $id, name: $name, type: ${type.wireName}, '
      'baseUrl: $baseUrl, apiKey: ${hasApiKey ? maskedApiKey : '(empty)'}, '
      'chatModel: $chatModel, imageModel: $imageModel, videoModel: $videoModel)';
}
