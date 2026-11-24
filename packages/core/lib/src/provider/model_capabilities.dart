import '../chat/chat_attach.dart';

/// Per-model compatibility hints. null means use the built-in heuristic.
class ModelCapabilityOverride {
  const ModelCapabilityOverride({this.vision, this.tools});
  final bool? vision;
  final bool? tools;
  bool get isAutomatic => vision == null && tools == null;
  Map<String, dynamic> toJson() => {
    if (vision != null) 'vision': vision,
    if (tools != null) 'tools': tools,
  };
}

Map<String, ModelCapabilityOverride> decodeModelCapabilityOverrides(
  Object? raw,
) {
  if (raw is! Map) return const {};
  final result = <String, ModelCapabilityOverride>{};
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final id = (entry.key as String).trim();
    final value = entry.value as Map;
    if (id.isEmpty ||
        (value.containsKey('vision') && value['vision'] is! bool) ||
        (value.containsKey('tools') && value['tools'] is! bool)) {
      continue;
    }
    final override = ModelCapabilityOverride(
      vision: value['vision'] as bool?,
      tools: value['tools'] as bool?,
    );
    if (!override.isAutomatic) result[id] = override;
  }
  return Map.unmodifiable(result);
}

class ChatModelCapabilities {
  const ChatModelCapabilities({required this.vision, required this.tools});
  final bool vision;
  final bool tools;
}

ChatModelCapabilities resolveChatModelCapabilities(
  String modelId,
  ModelCapabilityOverride? override,
) => ChatModelCapabilities(
  vision: override?.vision ?? supportsChatVision(modelId),
  tools: override?.tools ?? supportsChatTools(modelId),
);
