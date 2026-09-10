import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('文生图 OpenAI 写 size，归一化 b64', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/images/generations'));
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['x-api-key'], 'sk-test');
      final body = jsonDecode(request.body) as Map;
      expect(body['model'], 'gpt-image-1');
      expect(body['prompt'], '一只猫');
      expect(body['n'], 2);
      expect(body['size'], '1024x1024');
      expect(body.containsKey('aspect_ratio'), isFalse);
      expect(body['response_format'], 'b64_json');
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': 'YWJj'},
            {'url': 'https://cdn.example/a.png'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = OpenAiCompatibleImageClient(client: client);
    final refs = await api.generateTextToImage(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'gpt-image-1',
      prompt: '一只猫',
      n: 2,
      size: '1024x1024',
      providerType: ProviderType.openai,
    );
    expect(refs.length, 2);
    expect(refs[0].type, ImageRefType.b64);
    expect(refs[0].src, startsWith('data:image/png;base64,'));
    expect(refs[1].type, ImageRefType.url);
    expect(refs[1].src, 'https://cdn.example/a.png');
  });

  test('文生图 xAI 写 aspect_ratio', () async {
    Map? captured;
    final client = MockClient((request) async {
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': 'eA=='},
          ],
        }),
        200,
      );
    });
    final api = OpenAiCompatibleImageClient(client: client);
    await api.generateTextToImage(
      baseUrl: 'https://api.x.ai/v1',
      apiKey: 'xai-k',
      model: 'grok-imagine-image',
      prompt: 'moon',
      aspectRatio: '16:9',
      providerType: ProviderType.xai,
    );
    expect(captured!['aspect_ratio'], '16:9');
    expect(captured!.containsKey('size'), isFalse);
  });

  test('文生图 Agnes 写 size 档位 + ratio + extra_body', () async {
    Map? captured;
    Uri? uri;
    final client = MockClient((request) async {
      uri = request.url;
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': 'YQ=='},
          ],
        }),
        200,
      );
    });
    final api = OpenAiCompatibleImageClient(client: client);
    await api.generateTextToImage(
      baseUrl: 'https://apihub.agnes-ai.com/v1',
      apiKey: 'ag-k',
      model: 'agnes-image-2.5-flash',
      prompt: 'city',
      size: '2K',
      aspectRatio: '16:9',
      providerType: ProviderType.openaiCompatible,
    );
    expect(uri!.path, endsWith('/images/generations'));
    expect(captured!['size'], '2K');
    expect(captured!['ratio'], '16:9');
    expect(captured!['return_base64'], isTrue);
    expect(
      (captured!['extra_body'] as Map)['response_format'],
      'b64_json',
    );
    expect(captured!.containsKey('response_format'), isFalse);
    expect(captured!.containsKey('aspect_ratio'), isFalse);
  });

  test('图生图 Agnes 走 generations + extra_body.image', () async {
    Map? captured;
    Uri? uri;
    final client = MockClient((request) async {
      uri = request.url;
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'data': [
            {'url': 'https://cdn.example/out.png'},
          ],
        }),
        200,
      );
    });
    final api = OpenAiCompatibleImageClient(client: client);
    final refs = await api.editImage(
      baseUrl: 'https://apihub.agnes-ai.com/v1',
      apiKey: 'ag-k',
      model: 'agnes-image-2.1-flash',
      prompt: 'make blue',
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      size: '1K',
      aspectRatio: '1:1',
      responseFormat: 'url',
      providerType: ProviderType.openaiCompatible,
    );
    expect(uri!.path, endsWith('/images/generations'));
    expect(captured!['size'], '1K');
    expect(captured!['ratio'], '1:1');
    final extra = captured!['extra_body'] as Map;
    expect(extra['response_format'], 'url');
    expect((extra['image'] as List).single, startsWith('data:image/png;base64,'));
    expect(refs.single.type, ImageRefType.url);
  });

  test('401 鉴权文案', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'bad key'},
        }),
        401,
      );
    });
    final api = OpenAiCompatibleImageClient(client: client);
    await expectLater(
      api.generateTextToImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-bad',
        model: 'm',
        prompt: 'x',
      ),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'msg',
          anyOf(contains('鉴权'), contains('bad key')),
        ),
      ),
    );
  });

  test('normalizeImageResponse 空 data', () {
    expect(normalizeImageResponse({'data': []}), isEmpty);
    expect(normalizeImageResponse(null), isEmpty);
  });

  test('ActiveImageCredentials toString masks key', () {
    const creds = ActiveImageCredentials(
      providerId: 'p',
      providerName: 'n',
      type: ProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-should-not-leak',
      imageModel: 'gpt-image-1',
    );
    expect(creds.toString().contains('sk-should-not-leak'), isFalse);
  });
}
