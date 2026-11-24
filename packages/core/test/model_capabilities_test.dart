import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderConfig provider({String id = 'p', String model = 'unknown'}) =>
      ProviderConfig(
        id: id,
        name: id,
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://example.com/v1',
        chatModel: model,
      );
  test(
    'automatic preserves heuristics and overrides are provider and case scoped',
    () {
      final p = provider().copyWith(
        modelCapabilityOverrides: {
          ' unknown ': const ModelCapabilityOverride(
            vision: true,
            tools: false,
          ),
        },
      );
      expect(p.capabilitiesFor('unknown').vision, isTrue);
      expect(p.capabilitiesFor('unknown').tools, isFalse);
      expect(
        p.capabilitiesFor('UNKNOWN').vision,
        supportsChatVision('UNKNOWN'),
      );
      expect(
        provider(id: 'other').capabilitiesFor('unknown').vision,
        supportsChatVision('unknown'),
      );
      for (final id in ['gpt-4o', 'grok-4.5', 'unknown']) {
        expect(provider().capabilitiesFor(id).vision, supportsChatVision(id));
        expect(provider().capabilitiesFor(id).tools, supportsChatTools(id));
      }
    },
  );
  test('defensive immutable map, serialization, false vs automatic', () {
    final map = {
      'm': const ModelCapabilityOverride(vision: false, tools: true),
    };
    final p = ProviderConfig(
      id: 'p',
      name: 'p',
      type: ProviderType.openaiCompatible,
      modelCapabilityOverrides: map,
    );
    map.clear();
    expect(p.modelCapabilityOverrides.length, 1);
    expect(() => p.modelCapabilityOverrides.clear(), throwsUnsupportedError);
    final roundtrip = ProviderConfig.fromJson(p.toJsonMeta());
    expect(roundtrip.capabilitiesFor('m').vision, isFalse);
    expect(roundtrip.capabilitiesFor('m').tools, isTrue);
    expect(roundtrip.toJsonMeta().containsKey('apiKey'), isFalse);
  });
  test('metadata changes keep overrides but backend change always clears', () {
    final map = {'m': const ModelCapabilityOverride(vision: true)};
    final p = provider().copyWith(modelCapabilityOverrides: map);
    expect(
      p
          .copyWith(name: 'renamed', apiKey: 'secret', chatModel: 'other')
          .modelCapabilityOverrides
          .length,
      1,
    );
    expect(
      p
          .copyWith(
            baseUrl: 'https://new.example/v1',
            modelCapabilityOverrides: map,
          )
          .modelCapabilityOverrides,
      isEmpty,
    );
    expect(
      p
          .copyWith(type: ProviderType.openai, modelCapabilityOverrides: map)
          .modelCapabilityOverrides,
      isEmpty,
    );
  });
  test(
    'malformed optional capabilities cannot enable hints or break legacy metadata',
    () {
      final p = ProviderConfig.fromJson({
        ...provider().toJsonMeta(),
        'modelCapabilityOverrides': {
          'bad': {'vision': 'true'},
          'bad2': {'tools': 1},
          'ok': {'vision': false},
          'future': {'unknown': true},
        },
      });
      expect(p.modelCapabilityOverrides.keys, ['ok']);
      expect(
        ProviderConfig.fromJson({
          ...provider().toJsonMeta(),
          'modelCapabilityOverrides': [],
        }).modelCapabilityOverrides,
        isEmpty,
      );
    },
  );
  test(
    'legacy import preserves only same backend; explicit empty clears and own backend hints apply',
    () {
      final local = provider().copyWith(
        modelCapabilityOverrides: {
          'm': const ModelCapabilityOverride(vision: true),
        },
      );
      ProviderConfig merge(ProviderConfig incoming) => mergeProviders(
        local: [local],
        incoming: [incoming],
        applySecrets: false,
      ).single;
      expect(merge(provider()).modelCapabilityOverrides.length, 1);
      expect(
        merge(
          provider().copyWith(baseUrl: 'https://new.example/v1'),
        ).modelCapabilityOverrides,
        isEmpty,
      );
      expect(
        merge(
          provider().copyWith(modelCapabilityOverrides: {}),
        ).modelCapabilityOverrides,
        isEmpty,
      );
      final incoming = ProviderConfig.fromJson({
        ...provider().toJsonMeta(),
        'baseUrl': 'https://new.example/v1',
        'modelCapabilityOverrides': {
          'm': {'tools': false},
        },
      });
      expect(merge(incoming).modelCapabilityOverrides['m']!.tools, isFalse);
    },
  );
  test(
    'repository save rejects stale hints supplied with backend change and roundtrips',
    () async {
      final p = provider().copyWith(
        modelCapabilityOverrides: {
          'm': const ModelCapabilityOverride(vision: true),
        },
      );
      final storage = MemoryProviderStorage(
        ProviderStoreSnapshot(providers: [p], activeProviderId: p.id),
      );
      final repo = ProviderRepository(storage: storage);
      await repo.load();
      final stale = ProviderConfig.fromJson({
        ...p.toJsonMeta(),
        'baseUrl': 'https://new.example/v1',
      });
      await repo.saveProvider(stale);
      await repo.waitForPersist();
      expect(repo.providers.single.modelCapabilityOverrides, isEmpty);
      final reloaded = ProviderRepository(storage: storage);
      await reloaded.load();
      expect(reloaded.providers.single.modelCapabilityOverrides, isEmpty);
      repo.dispose();
      reloaded.dispose();
    },
  );
}
