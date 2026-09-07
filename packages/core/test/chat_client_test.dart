import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('拼接 SSE delta，遇 [DONE] 结束', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/chat/completions'));
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['x-api-key'], 'sk-test');
      final body = await bodyStream.bytesToString();
      final json = jsonDecode(body) as Map;
      expect(json['stream'], isTrue);
      expect(json.containsKey('max_tokens'), isFalse);

      final controller = StreamController<List<int>>();
      scheduleMicrotask(() {
        controller.add(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"你"}}]}\n'
            'data: {"choices":[{"delta":{"content":"好"}}]}\n'
            'data: [DONE]\n',
          ),
        );
        controller.close();
      });
      return http.StreamedResponse(controller.stream, 200);
    });

    final chat = OpenAiCompatibleChatClient(client: client);
    final deltas = <String>[];
    final full = await chat.streamChat(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'gpt-test',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
      onDelta: (d, _) => deltas.add(d),
    );
    expect(full, '你好');
    expect(deltas, ['你', '好']);
  });

  test('maxTokens>0 才写入 body', () async {
    Map? captured;
    final client = MockClient.streaming((request, bodyStream) async {
      captured = jsonDecode(await bodyStream.bytesToString()) as Map;
      return http.StreamedResponse(
        Stream.value(utf8.encode('data: [DONE]\n')),
        200,
      );
    });
    final chat = OpenAiCompatibleChatClient(client: client);
    await chat.streamChat(
      baseUrl: 'https://x.test/v1/',
      apiKey: 'k',
      model: 'm',
      messages: [
        {'role': 'user', 'content': 'a'},
      ],
      maxTokens: 64,
    );
    expect(captured!['max_tokens'], 64);
    expect(normalizeBaseUrl('https://x.test/v1/'), 'https://x.test/v1');
  });

  test('401 鉴权文案', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"bad key"}}')),
        401,
      );
    });
    final chat = OpenAiCompatibleChatClient(client: client);
    await expectLater(
      chat.streamChat(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-bad',
        model: 'm',
        messages: [
          {'role': 'user', 'content': 'x'},
        ],
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

  test('关闭 client 视为取消', () async {
    final real = http.Client();
    final chat = OpenAiCompatibleChatClient(client: real);
    final future = chat.streamChat(
      baseUrl: 'https://httpbin.org/delay/10',
      apiKey: 'k',
      model: 'm',
      messages: [
        {'role': 'user', 'content': 'x'},
      ],
      timeout: const Duration(seconds: 30),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    real.close();
    await expectLater(future, throwsA(isA<ChatAbortException>()));
  }, skip: '避免依赖外网；取消语义由 isAbortLike + ClientException 覆盖');

  test('isAbortLike / toAbortError', () {
    expect(toAbortError().message, '已取消');
    expect(isAbortLike(const ChatAbortException()), isTrue);
    expect(isAbortLike(Exception('ClientException: Connection closed')), isTrue);
  });

  test('错误 toString 不泄露 key', () {
    const err = ChatApiException('鉴权失败，请检查 API Key');
    expect(err.toString().contains('sk-'), isFalse);
  });
}
