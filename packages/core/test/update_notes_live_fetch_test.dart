import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('UpdateClient decodes octet-stream manifest as UTF-8 notes', () async {
    final chineseNotes = '### Changed\n\n- **Material 开屏**：去掉原生 splash logo';
    final payload = jsonEncode({
      'version': '9.9.9',
      'notes': chineseNotes,
      'platforms': {
        'windows-x86_64': {
          'url': 'https://example.com/a.exe',
          'signature': 'x',
        },
      },
    });
    final mock = MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(payload),
        200,
        headers: const {'content-type': 'application/octet-stream'},
      );
    });

    final client = UpdateClient(
      client: createSafeHttpClient(inner: mock),
      manifestUrl: 'https://example.com/latest.json',
      requireSignature: false,
    );
    addTearDown(client.close);

    final manifest = await client.fetchManifest();
    expect(manifest.notes.contains('开屏'), isTrue);
    final prepared = prepareUpdateNotes(manifest.notes);
    expect(prepared.contains('开屏'), isTrue);
    expect(prepared.contains('**'), isTrue);
    expect(prepared.contains('###'), isTrue);
  });
}
