import 'dart:convert';
import 'dart:io';

import 'package:ragchat/app/persona.dart';
import 'package:ragchat/app/settings.dart';
import 'package:test/test.dart';

/// US-22 人设卡：渲染、序列化、切换；ADR-0009 设置兼容（旧字段容忍、写入丢弃）。
void main() {
  group('PersonaCard', () {
    test('render：字段齐全时全部渲染，空字段跳过', () {
      const full = PersonaCard(
        id: 'x',
        name: '小暖',
        personality: '温柔耐心',
        style: '口语化',
        catchphrase: '嗯，我在',
        addressTerm: '你',
        boundary: '不给医疗建议',
      );
      final r = full.render();
      expect(r, contains('你是小暖'));
      expect(r, contains('性格：温柔耐心'));
      expect(r, contains('说话：口语化'));
      expect(r, contains('常说：「嗯，我在」'));
      expect(r, contains('称呼用户为「你」'));
      expect(r, contains('不做：不给医疗建议'));

      const minimal = PersonaCard(id: 'y', name: '小助');
      expect(minimal.render(), '你是小助。', reason: '无附加字段时只报名字');

      expect(
        PersonaCard(id: 'z', name: '').render(),
        '',
        reason: '空卡渲染为空串，system 不加人设段',
      );
    });

    test('只有旧自由正文时原样使用（ADR-0010 数据兼容）', () {
      const old = PersonaCard(
        id: 'legacy',
        name: '阿鱼',
        text: '你是阿鱼，话少。',
      );
      expect(old.render(), '你是阿鱼，话少。');
      expect(old.isEmpty, isFalse);
    });

    test('encodeList / decodeList 往返保真', () {
      final cards = [
        const PersonaCard(id: 'a', name: 'A', style: '短句'),
        const PersonaCard(id: 'b', name: 'B', boundary: '不聊政治'),
      ];
      final json = PersonaCard.encodeList(cards);
      final back = PersonaCard.decodeList(json);
      expect(back.length, 2);
      expect(back[0].id, 'a');
      expect(back[0].style, '短句');
      expect(back[1].boundary, '不聊政治');
    });

    test('decodeList：null/坏 JSON 回退内置预设', () {
      expect(
        PersonaCard.decodeList(null).map((c) => c.id),
        builtinPersonas.map((c) => c.id),
      );
      expect(PersonaCard.decodeList('{坏掉的'), isNotEmpty);
    });
  });

  group('AppSettings（ADR-0009 兼容）', () {
    Future<String> tmpDir() async {
      final dir = await Directory.systemTemp.createTemp('chat_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      return dir.path;
    }

    test('人设卡列表与激活 id 往返保真', () async {
      final dir = await tmpDir();
      final cards = [const PersonaCard(id: 'mine', name: '自定义', style: '诗意的')];
      final s = AppSettings(
        confirmed: true,
        chatModelPath: '/m/c.gguf',
        activePersonaId: 'mine',
        personasJson: PersonaCard.encodeList(cards),
        accentId: 'teal',
      );
      await s.save(dir);

      final loaded = await AppSettings.load(dir);
      expect(loaded.activePersonaId, 'mine');
      final back = loaded.personas();
      expect(back.single.id, 'mine');
      expect(back.single.style, '诗意的');
      expect(loaded.activePersona(back).name, '自定义');
      expect(loaded.accentId, 'teal');
    });

    test('v2 旧 settings.json：RAG 字段读取容忍、personaId 映射、写入丢弃', () async {
      final dir = await tmpDir();
      await File('$dir/settings.json').writeAsString(
        jsonEncode({
          'refusalThreshold': 0.5,
          'topK': 3,
          'useGpu': false,
          'confirmed': true,
          'chatModelPath': '/m/c.gguf',
          'embedModelPath': '/m/e.gguf',
          'personaId': 'plain', // v2 旧字段名
          'customPersona': '像老师一样',
          'lastCategory': '历史',
          'accentId': 'pink',
        }),
      );
      final loaded = await AppSettings.load(dir);
      expect(loaded.confirmed, isTrue);
      expect(loaded.chatModelPath, '/m/c.gguf');
      expect(loaded.accentId, 'pink');

      await loaded.save(dir);
      final rewritten = jsonDecode(
        await File('$dir/settings.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(
        rewritten.containsKey('refusalThreshold'),
        isFalse,
        reason: 'RAG 字段写入时丢弃',
      );
      expect(rewritten.containsKey('customPersona'), isFalse);
      expect(
        rewritten['activePersonaId'],
        'plain',
        reason: '旧 personaId 值延续为激活 id',
      );
      expect(rewritten['personasJson'], isNotNull);
    });

    test('缺失/损坏回退默认：personas 回内置预设', () async {
      final dir = await tmpDir();
      final missing = await AppSettings.load(dir);
      expect(missing.personas().length, builtinPersonas.length);
      expect(missing.activePersona(missing.personas()).id, 'dafeiyu');

      await File('$dir/settings.json').writeAsString('{坏掉的');
      final broken = await AppSettings.load(dir);
      expect(broken.personasJson, isNull);
      expect(broken.useGpu, isFalse);
    });

    test('采样参数往返：温度与思考开关', () async {
      final dir = await tmpDir();
      final s = AppSettings(temperature: 0.35, enableThinking: true);
      await s.save(dir);
      final back = await AppSettings.load(dir);
      expect(back.temperature, 0.35);
      expect(back.enableThinking, isTrue);
      expect(AppSettings().temperature, 0.6, reason: '默认平衡档');
    });

    test('activePersona：激活 id 不在列表时回退第一张', () {
      final s = AppSettings(activePersonaId: 'ghost');
      final cards = [const PersonaCard(id: 'a', name: 'A')];
      expect(s.activePersona(cards).id, 'a');
    });
  });
}
