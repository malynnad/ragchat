import 'package:ragchat/app/app_state.dart';
import 'package:ragchat/rag/model_catalog.dart';
import 'package:test/test.dart';

/// v2 P2：候选目录常量完整性。URL 可达性已于 2026-11-15 用 HEAD 实测
/// （全部 200 + content-length），此处只守卫常量不被改坏。
void main() {
  test('目录条目完整：https URL、正体积、备注非空', () {
    expect(modelCatalog, isNotEmpty);
    for (final m in modelCatalog) {
      expect(
        m.url,
        startsWith('https://hf-mirror.com/'),
        reason: '${m.label} 应走国内镜像',
      );
      expect(m.label, isNotEmpty);
      expect(m.sizeBytes, greaterThan(0));
      expect(m.note, isNotEmpty);
    }
  });

  test('只留日常聊天档：生成两档、嵌入一档，默认项各恰好一个', () {
    final chat = modelCatalog.where((m) => m.isChat).toList();
    final embed = modelCatalog.where((m) => !m.isChat).toList();
    expect(chat.length, 3, reason: '0.6B 快聊 / 2B 折中 / 4B 质量档');
    expect(embed.length, 1, reason: '嵌入 0.6B 一个就够');
    expect(chat.where((m) => m.isDefault).length, 1);
    expect(embed.where((m) => m.isDefault).length, 1);
    expect(chat.firstWhere((m) => m.isDefault).label, contains('Qwen3.5-4B'));
    expect(embed.firstWhere((m) => m.isDefault).label, contains('0.6B'));
  });

  test('首启默认下载与聊天模型目录的默认项一致', () {
    final defaultChat = modelCatalog.singleWhere(
      (m) => m.isChat && m.isDefault,
    );
    expect(AppState.chatModelUrl, defaultChat.url);
  });
}
