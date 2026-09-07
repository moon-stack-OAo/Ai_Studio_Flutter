import '../chat/chat_context_trim.dart';
import '../openai/chat_client.dart';

/// 对话全局默认（可被单会话 overrides 覆盖）。
class ChatDefaults {
  const ChatDefaults({
    this.temperature = defaultChatTemperature,
    this.systemPrompt = '',
    this.maxTokens = 0,
    this.apiTimeoutMs = 180000,
    this.contextTrimEnabled = true,
    this.contextMaxTurns = defaultChatContextMaxTurns,
    this.contextMaxCharsEnabled = false,
    this.contextMaxChars = defaultChatContextMaxChars,
  });

  static const ChatDefaults recommended = ChatDefaults();

  final double temperature;
  final String systemPrompt;
  final int maxTokens;
  final int apiTimeoutMs;
  final bool contextTrimEnabled;
  final int contextMaxTurns;
  final bool contextMaxCharsEnabled;
  final int contextMaxChars;

  Duration get apiTimeout => Duration(milliseconds: apiTimeoutMs.clamp(1000, 600000));

  ChatDefaults copyWith({
    double? temperature,
    String? systemPrompt,
    int? maxTokens,
    int? apiTimeoutMs,
    bool? contextTrimEnabled,
    int? contextMaxTurns,
    bool? contextMaxCharsEnabled,
    int? contextMaxChars,
  }) {
    return ChatDefaults(
      temperature: temperature ?? this.temperature,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      maxTokens: maxTokens ?? this.maxTokens,
      apiTimeoutMs: apiTimeoutMs ?? this.apiTimeoutMs,
      contextTrimEnabled: contextTrimEnabled ?? this.contextTrimEnabled,
      contextMaxTurns: contextMaxTurns ?? this.contextMaxTurns,
      contextMaxCharsEnabled:
          contextMaxCharsEnabled ?? this.contextMaxCharsEnabled,
      contextMaxChars: contextMaxChars ?? this.contextMaxChars,
    );
  }

  /// 钳制到合法区间。
  ChatDefaults sanitized() {
    var temp = temperature;
    if (temp.isNaN || temp.isInfinite) temp = defaultChatTemperature;
    temp = temp.clamp(0.0, 2.0);

    var tokens = maxTokens;
    if (tokens < 0) tokens = 0;
    if (tokens > 200000) tokens = 200000;

    var timeout = apiTimeoutMs;
    if (timeout < 1000) timeout = 1000;
    if (timeout > 600000) timeout = 600000;

    var turns = contextMaxTurns;
    if (turns < 1) turns = 1;
    if (turns > 200) turns = 200;

    var chars = contextMaxChars;
    if (chars < 1) chars = 1;
    if (chars > 500000) chars = 500000;

    return ChatDefaults(
      temperature: temp,
      systemPrompt: systemPrompt,
      maxTokens: tokens,
      apiTimeoutMs: timeout,
      contextTrimEnabled: contextTrimEnabled,
      contextMaxTurns: turns,
      contextMaxCharsEnabled: contextMaxCharsEnabled,
      contextMaxChars: chars,
    );
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'systemPrompt': systemPrompt,
        'maxTokens': maxTokens,
        'apiTimeoutMs': apiTimeoutMs,
        'contextTrimEnabled': contextTrimEnabled,
        'contextMaxTurns': contextMaxTurns,
        'contextMaxCharsEnabled': contextMaxCharsEnabled,
        'contextMaxChars': contextMaxChars,
      };

  factory ChatDefaults.fromJson(Map<String, dynamic> json) {
    double readDouble(Object? v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int readInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    bool readBool(Object? v, bool fallback) {
      if (v is bool) return v;
      return fallback;
    }

    return ChatDefaults(
      temperature: readDouble(json['temperature'], defaultChatTemperature),
      systemPrompt: json['systemPrompt']?.toString() ?? '',
      maxTokens: readInt(json['maxTokens'], 0),
      apiTimeoutMs: readInt(json['apiTimeoutMs'], 180000),
      contextTrimEnabled: readBool(json['contextTrimEnabled'], true),
      contextMaxTurns:
          readInt(json['contextMaxTurns'], defaultChatContextMaxTurns),
      contextMaxCharsEnabled: readBool(json['contextMaxCharsEnabled'], false),
      contextMaxChars:
          readInt(json['contextMaxChars'], defaultChatContextMaxChars),
    ).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatDefaults &&
          temperature == other.temperature &&
          systemPrompt == other.systemPrompt &&
          maxTokens == other.maxTokens &&
          apiTimeoutMs == other.apiTimeoutMs &&
          contextTrimEnabled == other.contextTrimEnabled &&
          contextMaxTurns == other.contextMaxTurns &&
          contextMaxCharsEnabled == other.contextMaxCharsEnabled &&
          contextMaxChars == other.contextMaxChars;

  @override
  int get hashCode => Object.hash(
        temperature,
        systemPrompt,
        maxTokens,
        apiTimeoutMs,
        contextTrimEnabled,
        contextMaxTurns,
        contextMaxCharsEnabled,
        contextMaxChars,
      );
}
