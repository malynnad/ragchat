/// 候选模型目录（v2 P2）：设置页一键下载。
/// URL 于 2026-11-15 经 hf-mirror HEAD 验证（200 + content-length）；
/// 体积为 HEAD 实测字节数；备注引自 docs/工作原理与模型选型.md。
/// 14B 与嵌入 4B 在本机（14.8 GB）属边缘配置：下载后需真机验证才算可用。
class CatalogModel {
  const CatalogModel({
    required this.isChat,
    required this.label,
    required this.url,
    required this.sizeBytes,
    required this.note,
    this.isDefault = false,
  });

  final bool isChat;
  final String label;
  final String url;
  final int sizeBytes;
  final String note;
  final bool isDefault;
}

const List<CatalogModel> modelCatalog = [
  // 2026-11-16 收敛：只留日常聊天够用的两档 + 一个嵌入模型。
  // 4B/8B/14B 都删了——手机上首字慢，聊天用不上。
  CatalogModel(
    isChat: true,
    label: 'Qwen3-0.6B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    sizeBytes: 396705472,
    note: '最小档：约 378 MiB，配置低的机器或只想快聊时选它',
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-2B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
    sizeBytes: 1280835840,
    note: '速度档：约 1.28 GiB，聊得动但容易跑题、复读',
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-4B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
    sizeBytes: 2740937888,
    note: '默认档：约 2.55 GiB，2B 语无伦次时换它，手机上仍算能用',
    isDefault: true,
  ),
  CatalogModel(
    isChat: false,
    label: 'Qwen3-Embedding-0.6B Q8_0',
    url: 'https://hf-mirror.com/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf',
    sizeBytes: 639150592,
    note: '1024 维；v2 情景记忆用，聊天不必装',
    isDefault: true,
  ),
];

/// 候选展示排序（v2 bugfix）：先按类型分组——生成模型在前、嵌入模型在后；
/// 同类型内按体积升序。即 Qwen3-0.6B → Qwen3.5-2B → Embedding-0.6B。
List<CatalogModel> sortedCatalog() {
  final list = [...modelCatalog];
  list.sort((a, b) {
    if (a.isChat != b.isChat) return a.isChat ? -1 : 1;
    return a.sizeBytes.compareTo(b.sizeBytes);
  });
  return list;
}
