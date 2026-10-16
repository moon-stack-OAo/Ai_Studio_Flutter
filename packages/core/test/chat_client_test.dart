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
    final result = await chat.streamChat(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'gpt-test',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
      onDelta: (d, _) => deltas.add(d),
    );
    expect(result.content, '你好');
    expect(result.toolCalls, isEmpty);
    expect(deltas, ['你', '好']);
  });

  for (final callbacks in ['onContentDelta', 'onDelta', 'both']) {
    test('中文 emoji 所有字节分片边界及逐 byte，$callbacks 内容一致', () async {
      const expectedDeltas = ['你好🙂', '世界🌏🚀'];
      final bytes = utf8.encode(
        'data: {"choices":[{"delta":{"content":"你好🙂"}}]}\n'
        'data: {"choices":[{"delta":{"content":"世界🌏🚀"},"finish_reason":"stop"}]}\n'
        'data: [DONE]\n',
      );
      final partitions = [
        for (var split = 0; split <= bytes.length; split++)
          [bytes.sublist(0, split), bytes.sublist(split)],
        [
          for (final byte in bytes) [byte],
        ],
      ];
      for (var i = 0; i < partitions.length; i++) {
        final chat = _chatWithStream(Stream.fromIterable(partitions[i]));
        final contentDeltas = <String>[];
        final legacyDeltas = <String>[];
        final fullTexts = <String>[];
        final result = await chat.streamChat(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
          messages: const [],
          onContentDelta: callbacks == 'onDelta' ? null : contentDeltas.add,
          onDelta: callbacks == 'onContentDelta'
              ? null
              : (delta, full) {
                  legacyDeltas.add(delta);
                  fullTexts.add(full);
                },
        );
        expect(result.content, expectedDeltas.join(), reason: '分片 $i');
        expect(result.finishReason, 'stop');
        if (callbacks != 'onDelta') {
          expect(contentDeltas, expectedDeltas, reason: '分片 $i');
        }
        if (callbacks != 'onContentDelta') {
          expect(legacyDeltas, expectedDeltas, reason: '分片 $i');
          expect(fullTexts, ['你好🙂', expectedDeltas.join()], reason: '分片 $i');
        }
      }
    });
  }

  test('非法 UTF-8 替换字符，EOF 时容忍截断序列', () async {
    final chat = _chatWithStream(
      Stream.fromIterable([
        utf8.encode('data: {"choices":[{"delta":{"content":"前'),
        [0xff],
        utf8.encode('后"}}]}\ndata: {"choices":[{"delta":{"content":"尾🙂"}}]}'),
        // 最后的不完整序列位于注释行，关闭 decoder 时应容错而非抛错。
        utf8.encode('\n: '),
        [0xf0, 0x9f],
      ]),
    );
    final deltas = <String>[];
    final result = await chat.streamChat(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'k',
      model: 'm',
      messages: const [],
      onContentDelta: deltas.add,
    );
    expect(result.content, '前\uFFFD后尾🙂');
    expect(deltas, ['前\uFFFD后', '尾🙂']);
  });

  test('[DONE] 后响应保持打开仍返回，并等待取消订阅完成', () async {
    final cancelled = Completer<void>();
    var cancelFinished = false;
    final responseBody = StreamController<List<int>>(
      onCancel: () async {
        cancelled.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cancelFinished = true;
      },
    );
    addTearDown(responseBody.close);
    responseBody.add(
      utf8.encode(
        'data: {"choices":[{"delta":{"content":"完成"},"finish_reason":"stop"}]}\n'
        'data: [DONE]\n',
      ),
    );
    final chat = _chatWithStream(responseBody.stream);
    final result = await chat
        .streamChat(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
          messages: const [],
        )
        .timeout(const Duration(seconds: 2));
    expect(result.content, '完成');
    expect(result.finishReason, 'stop');
    expect(responseBody.isClosed, isFalse);
    expect(cancelled.isCompleted, isTrue);
    expect(cancelFinished, isTrue);
  });

  for (final trailing in {
    '内容、工具及 finishReason':
        'data: {"choices":[{"delta":{"content":"不应出现","tool_calls":[{"index":1,"id":"late","function":{"name":"late","arguments":"{}"}}]},"finish_reason":"stop"}]}\n',
    '错误帧': 'data: {"error":{"message":"不应抛错"}}\n',
    '残留行': 'data: {"choices":[{"delta":{"content":"残留行不应出现"}}]}',
  }.entries) {
    test('[DONE] 忽略同 chunk 后续${trailing.key}', () async {
      final chat = _chatWithStream(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"保留","tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n'
            'data: [DONE]\n'
            '${trailing.value}',
          ),
        ),
      );
      final deltas = <String>[];
      final result = await chat.streamChat(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        messages: const [],
        onContentDelta: deltas.add,
      );
      expect(result.content, '保留');
      expect(deltas, ['保留']);
      expect(result.finishReason, 'tool_calls');
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.id, 'call_1');
      expect(result.toolCalls.single.name, 'lookup');
      expect(result.toolCalls.single.arguments, '{}');
    });
  }

  for (final ending in ['', 'data: [DONE]']) {
    test(
      '正常 EOF ${ending.isEmpty ? '无 DONE' : 'flush 残余 DONE'}保留工具增量与 finishReason',
      () async {
        final chat = _chatWithStream(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"查询","tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{\\"q\\":"}}]}}]}\n',
            ),
            utf8.encode(
              'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"中文🙂\\"}"}}]},"finish_reason":"tool_calls"}]}'
              '${ending.isEmpty ? '' : '\n$ending'}',
            ),
          ]),
        );
        final result = await chat.streamChat(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'k',
          model: 'm',
          messages: const [],
        );
        expect(result.content, '查询');
        expect(result.finishReason, 'tool_calls');
        expect(result.toolCalls, hasLength(1));
        expect(result.toolCalls.single.id, 'call_1');
        expect(result.toolCalls.single.name, 'lookup');
        expect(result.toolCalls.single.arguments, '{"q":"中文🙂"}');
      },
    );
  }

  test('超时按原始字节事件计时，UTF-8 尚未解码出字符也保持连接', () async {
    Stream<List<int>> responseBody() async* {
      yield utf8.encode('data: {"choices":[{"delta":{"content":"');
      for (final byte in utf8.encode('🙂')) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        yield [byte];
      }
      yield utf8.encode('"}}]}\ndata: [DONE]\n');
    }

    final chat = _chatWithStream(responseBody());
    final result = await chat.streamChat(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'k',
      model: 'm',
      messages: const [],
      timeout: const Duration(milliseconds: 300),
    );
    expect(result.content, '🙂');
  });

  test('2xx 响应在 UTF-8 序列中途悬挂仍超时并取消订阅', () async {
    final cancelled = Completer<void>();
    final responseBody = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    );
    addTearDown(responseBody.close);
    responseBody.add([
      ...utf8.encode('data: {"choices":[{"delta":{"content":"'),
      0xf0,
      0x9f,
    ]);
    final chat = _chatWithStream(responseBody.stream);
    await expectLater(
      chat
          .streamChat(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'k',
            model: 'm',
            messages: const [],
            timeout: const Duration(milliseconds: 20),
          )
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'message',
          '请求超时，请稍后重试或增大超时时间',
        ),
      ),
    );
    expect(cancelled.isCompleted, isTrue);
  });

  test('2xx 响应解码期间取消仍返回已取消且清理订阅', () async {
    final cancelled = Completer<void>();
    final responseBody = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    );
    addTearDown(responseBody.close);
    responseBody.add([0xf0, 0x9f]);
    responseBody.addError(http.ClientException('Connection closed'));
    final chat = _chatWithStream(responseBody.stream);
    await expectLater(
      chat.streamChat(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        messages: const [],
      ),
      throwsA(
        isA<ChatAbortException>().having((e) => e.message, 'message', '已取消'),
      ),
    );
    expect(cancelled.isCompleted, isTrue);
  });

  test('可选 tools 写入 body；缺省不传', () async {
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
      tools: [
        {
          'type': 'function',
          'function': {'name': 'lookup', 'parameters': <String, dynamic>{}},
        },
      ],
      toolChoice: 'auto',
    );
    expect(captured!['tools'], isA<List>());
    expect(captured!['tool_choice'], 'auto');

    await chat.streamChat(
      baseUrl: 'https://x.test/v1/',
      apiKey: 'k',
      model: 'm',
      messages: [
        {'role': 'user', 'content': 'a'},
      ],
    );
    expect(captured!.containsKey('tools'), isFalse);
  });

  test('流式 tool_calls 累积进 ChatStreamResult', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      final controller = StreamController<List<int>>();
      scheduleMicrotask(() {
        controller.add(
          utf8.encode(
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"q\\":"}}]}}]}\n'
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"x\\"}"}}]},"finish_reason":"tool_calls"}]}\n'
            'data: [DONE]\n',
          ),
        );
        controller.close();
      });
      return http.StreamedResponse(controller.stream, 200);
    });
    final chat = OpenAiCompatibleChatClient(client: client);
    final result = await chat.streamChat(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'k',
      model: 'm',
      messages: [
        {'role': 'user', 'content': 'x'},
      ],
    );
    expect(result.content, '');
    expect(result.finishReason, 'tool_calls');
    expect(result.toolCalls, hasLength(1));
    expect(result.toolCalls.single.id, 'call_1');
    expect(result.toolCalls.single.name, 'lookup');
    expect(result.toolCalls.single.arguments, '{"q":"x"}');
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

  test('非 2xx 响应体悬挂使用本次请求超时并取消流订阅', () async {
    final cancelled = Completer<void>();
    final responseBody = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    );
    addTearDown(responseBody.close);
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(responseBody.stream, 500);
    });
    final chat = OpenAiCompatibleChatClient(
      client: client,
      timeout: const Duration(seconds: 30),
    );
    await expectLater(
      chat
          .streamChat(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'sk-test',
            model: 'm',
            messages: const [],
            timeout: const Duration(milliseconds: 20),
          )
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'message',
          '请求超时，请稍后重试或增大超时时间',
        ),
      ),
    );
    await cancelled.future.timeout(const Duration(seconds: 2));
  });

  test('非 2xx 响应体收到部分数据后悬挂仍使用客户端默认超时', () async {
    final responseBody = StreamController<List<int>>();
    addTearDown(responseBody.close);
    responseBody.add(utf8.encode('{"error":{"message":"sk-secret-partial'));
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(responseBody.stream, 400);
    });
    final chat = OpenAiCompatibleChatClient(
      client: client,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      chat
          .streamChat(
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'sk-test',
            model: 'm',
            messages: const [],
          )
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'message',
          '请求超时，请稍后重试或增大超时时间',
        ),
      ),
    );
  });

  test('非 2xx 响应体读取取消仍返回已取消', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(
        Stream<List<int>>.error(http.ClientException('Connection closed')),
        500,
      );
    });
    final chat = OpenAiCompatibleChatClient(client: client);
    await expectLater(
      chat.streamChat(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'm',
        messages: const [],
      ),
      throwsA(
        isA<ChatAbortException>().having((e) => e.message, 'message', '已取消'),
      ),
    );
  });

  test('非 2xx 响应体读取异常仍回退 HTTP 状态文案', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(
        Stream<List<int>>.error(StateError('读取失败 sk-secret-must-not-leak')),
        401,
      );
    });
    final chat = OpenAiCompatibleChatClient(client: client);
    await expectLater(
      chat.streamChat(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'm',
        messages: const [],
      ),
      throwsA(
        isA<ChatApiException>()
            .having((e) => e.message, 'message', '鉴权失败，请检查 API Key')
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  for (final body in [
    '{"error":{"message":"bad key sk-secret-must-not-leak"}}',
    'bad key sk-secret-must-not-leak',
  ]) {
    test('非 2xx ${body.startsWith('{') ? 'JSON' : '纯文本'}错误响应仍脱敏', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain();
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 401);
      });
      final chat = OpenAiCompatibleChatClient(client: client);
      await expectLater(
        chat.streamChat(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'sk-secret-must-not-leak',
          model: 'm',
          messages: const [],
        ),
        throwsA(
          isA<ChatApiException>()
              .having((e) => e.message, 'message', contains('bad key'))
              .having((e) => e.message, 'secret', isNot(contains('sk-secret')))
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  }

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
    expect(
      isAbortLike(Exception('ClientException: Connection closed')),
      isTrue,
    );
  });

  test('错误 toString 不泄露 key', () {
    const err = ChatApiException('鉴权失败，请检查 API Key');
    expect(err.toString().contains('sk-'), isFalse);
  });
}

OpenAiCompatibleChatClient _chatWithStream(Stream<List<int>> stream) {
  final client = MockClient.streaming((request, bodyStream) async {
    await bodyStream.drain();
    return http.StreamedResponse(stream, 200);
  });
  return OpenAiCompatibleChatClient(client: client);
}
