/// 提供商协议类型（与现网 OpenAI / xAI / 兼容层对齐）。
enum ProviderType {
  openai,
  xai,
  openaiCompatible;

  String get wireName => switch (this) {
        ProviderType.openai => 'openai',
        ProviderType.xai => 'xai',
        ProviderType.openaiCompatible => 'openai-compatible',
      };

  String get label => switch (this) {
        ProviderType.openai => 'OpenAI',
        ProviderType.xai => 'xAI',
        ProviderType.openaiCompatible => 'OpenAI 兼容',
      };

  static ProviderType fromWire(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'openai':
        return ProviderType.openai;
      case 'xai':
        return ProviderType.xai;
      case 'openai-compatible':
      case 'openai_compatible':
      case 'compatible':
        return ProviderType.openaiCompatible;
      default:
        return ProviderType.openaiCompatible;
    }
  }
}
