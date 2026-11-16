import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/rag/model_catalog.dart';
import 'package:test/test.dart';

/// v2 bugfix 守卫：
/// (1) 模型选择按角色过滤（含 embed → 嵌入，其余 → 生成），避免互选错；
/// (2) 候选目录标题不再写死「当前默认」（切换后不失真），可按体积升序。
void main() {
  group('filesForRole 角色过滤', () {
    late AppState state;
    setUp(() {
      state = AppState();
      state.modelFiles.addAll([
        ModelFile('/m/qwen3-8b-q4_k_m.gguf', 5000),
        ModelFile('/m/qwen3-4b-q4_k_m.gguf', 2500),
        ModelFile('/m/qwen3-embedding-0.6b-q8_0.gguf', 639),
        ModelFile('/m/qwen3-embedding-4b-q8_0.gguf', 4280),
      ]);
    });

    test('生成角色只列非 embed 文件', () {
      final chat = state.filesForRole(isChat: true).map((f) => f.name).toList();
      expect(
        chat,
        containsAll(['qwen3-8b-q4_k_m.gguf', 'qwen3-4b-q4_k_m.gguf']),
      );
      expect(chat.every((n) => !n.contains('embed')), isTrue);
      expect(chat.length, 2);
    });

    test('嵌入角色只列 embed 文件', () {
      final embed = state
          .filesForRole(isChat: false)
          .map((f) => f.name)
          .toList();
      expect(
        embed,
        containsAll([
          'qwen3-embedding-0.6b-q8_0.gguf',
          'qwen3-embedding-4b-q8_0.gguf',
        ]),
      );
      expect(embed.length, 2);
    });

    test('大小写不敏感（Embedding 大写也归嵌入）', () {
      state.modelFiles.add(ModelFile('/m/Qwen3-Embedding-0.6B-Q8_0.gguf', 639));
      final embed = state
          .filesForRole(isChat: false)
          .map((f) => f.name)
          .toList();
      expect(embed, contains('Qwen3-Embedding-0.6B-Q8_0.gguf'));
    });

    test('无某角色文件时返回空（UI 据此提示）', () {
      final onlyChat = AppState();
      onlyChat.modelFiles.add(ModelFile('/m/qwen3-8b-q4_k_m.gguf', 5000));
      expect(onlyChat.filesForRole(isChat: false), isEmpty);
    });
  });

  group('候选目录', () {
    test('标题不再写死「当前默认」', () {
      for (final m in modelCatalog) {
        expect(m.label, isNot(contains('当前默认')));
      }
    });

    test('按类型分组再升序：生成 0.6B→2B，嵌入 0.6B', () {
      expect(sortedCatalog().map((m) => m.label).toList(), [
        'Qwen3-0.6B Q4_K_M',
        'Qwen3.5-2B Q4_K_M',
        'Qwen3-Embedding-0.6B Q8_0',
      ]);
    });
  });
}
