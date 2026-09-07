/// 对话消息与会话模型。

enum ChatRole {
  user,
  assistant,
  system;

  static ChatRole? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'user':
        return ChatRole.user;
      case 'assistant':
        return ChatRole.assistant;
      case 'system':
        return ChatRole.system;
      default:
        return null;
    }
  }

  String get wire => name;
}

class ChatOverrides {
  const ChatOverrides({this.systemPrompt, this.temperature});

  final String? systemPrompt;
  final double? temperature;

  bool get isEmpty => systemPrompt == null && temperature == null;

  ChatOverrides copyWith({
    String? systemPrompt,
    double? temperature,
    bool clearSystemPrompt = false,
    bool clearTemperature = false,
  }) {
    return ChatOverrides(
      systemPrompt:
          clearSystemPrompt ? null : (systemPrompt ?? this.systemPrompt),
      temperature:
          clearTemperature ? null : (temperature ?? this.temperature),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (systemPrompt != null) map['systemPrompt'] = systemPrompt;
    if (temperature != null) map['temperature'] = temperature;
    return map;
  }

  factory ChatOverrides.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ChatOverrides();
    String? prompt;
    if (json.containsKey('systemPrompt') && json['systemPrompt'] != null) {
      prompt = json['systemPrompt'].toString();
    }
    double? temp;
    if (json.containsKey('temperature') && json['temperature'] != null) {
      final n = json['temperature'];
      if (n is num) {
        temp = (n.toDouble().clamp(0.0, 2.0) * 10).round() / 10;
      } else {
        final parsed = double.tryParse(n.toString());
        if (parsed != null) {
          temp = (parsed.clamp(0.0, 2.0) * 10).round() / 10;
        }
      }
    }
    return ChatOverrides(systemPrompt: prompt, temperature: temp);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatOverrides &&
          systemPrompt == other.systemPrompt &&
          temperature == other.temperature;

  @override
  int get hashCode => Object.hash(systemPrompt, temperature);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.createdAt,
    required this.role,
    required this.content,
    this.streaming = false,
    this.stopped = false,
    this.error = false,
    this.errorMessage,
    this.model,
    this.latencyMs,
  });

  final String id;

  /// 毫秒时间戳。
  final int createdAt;
  final ChatRole role;
  final String content;
  final bool streaming;
  final bool stopped;
  final bool error;
  final String? errorMessage;

  /// 助手回复所用模型 id（CHAT-MSG-META）；旧消息可缺省。
  final String? model;

  /// 从发起请求到流式结束/停止/错误的耗时（毫秒）；旧消息可缺省。
  final int? latencyMs;

  ChatMessage copyWith({
    String? id,
    int? createdAt,
    ChatRole? role,
    String? content,
    bool? streaming,
    bool? stopped,
    bool? error,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? model,
    bool clearModel = false,
    int? latencyMs,
    bool clearLatencyMs = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      role: role ?? this.role,
      content: content ?? this.content,
      streaming: streaming ?? this.streaming,
      stopped: stopped ?? this.stopped,
      error: error ?? this.error,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      model: clearModel ? null : (model ?? this.model),
      latencyMs: clearLatencyMs ? null : (latencyMs ?? this.latencyMs),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'role': role.wire,
        'content': content,
        if (streaming) 'streaming': streaming,
        if (stopped) 'stopped': stopped,
        if (error) 'error': error,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (model != null && model!.isNotEmpty) 'model': model,
        if (latencyMs != null) 'latencyMs': latencyMs,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = ChatRole.tryParse(json['role']?.toString()) ?? ChatRole.user;
    int? latency;
    final rawLatency = json['latencyMs'];
    if (rawLatency is num) {
      latency = rawLatency.toInt();
    } else if (rawLatency != null) {
      latency = int.tryParse(rawLatency.toString());
    }
    final modelRaw = json['model']?.toString();
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      createdAt: (json['createdAt'] is num)
          ? (json['createdAt'] as num).toInt()
          : 0,
      role: role,
      content: json['content']?.toString() ?? '',
      streaming: json['streaming'] == true,
      stopped: json['stopped'] == true,
      error: json['error'] == true,
      errorMessage: json['errorMessage']?.toString(),
      model: (modelRaw == null || modelRaw.isEmpty) ? null : modelRaw,
      latencyMs: latency,
    );
  }
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.overrides = const ChatOverrides(),
  });

  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;
  final ChatOverrides overrides;

  ChatSession copyWith({
    String? id,
    String? title,
    int? createdAt,
    int? updatedAt,
    List<ChatMessage>? messages,
    ChatOverrides? overrides,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      overrides: overrides ?? this.overrides,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messages': messages.map((m) => m.toJson()).toList(),
        'overrides': overrides.toJson(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMsgs = json['messages'];
    final msgs = <ChatMessage>[];
    if (rawMsgs is List) {
      for (final e in rawMsgs) {
        if (e is Map) {
          msgs.add(ChatMessage.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final ovRaw = json['overrides'];
    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新对话',
      createdAt:
          (json['createdAt'] is num) ? (json['createdAt'] as num).toInt() : 0,
      updatedAt:
          (json['updatedAt'] is num) ? (json['updatedAt'] as num).toInt() : 0,
      messages: msgs,
      overrides: ChatOverrides.fromJson(
        ovRaw is Map ? Map<String, dynamic>.from(ovRaw) : null,
      ),
    );
  }
}

/// 持久化快照。
class ChatStoreSnapshot {
  const ChatStoreSnapshot({
    required this.sessions,
    required this.activeId,
  });

  final List<ChatSession> sessions;
  final String activeId;
}
