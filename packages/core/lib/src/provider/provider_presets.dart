import 'provider_config.dart';
import 'provider_type.dart';

/// 内置预设（与现网 OpenAI / xAI 对齐；不含密钥）。
List<ProviderConfig> builtinProviderPresets() => [
      const ProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        type: ProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        chatModel: 'gpt-4o',
        imageModel: 'gpt-image-1',
        videoModel: 'sora-2',
        builtin: true,
      ),
      const ProviderConfig(
        id: 'xai',
        name: 'xAI Grok',
        type: ProviderType.xai,
        baseUrl: 'https://api.x.ai/v1',
        chatModel: 'grok-4.5',
        imageModel: 'grok-imagine-image',
        videoModel: 'grok-imagine-video',
        builtin: true,
      ),
    ];
