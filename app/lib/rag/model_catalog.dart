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
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-2B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
    sizeBytes: 1280835840,
    note: '聊天速度档：约 1.28 GB，优先低延迟与低内存占用',
    isDefault: true,
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3-8B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf',
    sizeBytes: 5027784512,
    note: '本机实测平衡点：首字约 3 秒，约 8 token/秒',
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3-4B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    sizeBytes: 2497281312,
    note: '速度档：解码估算约 15 token/秒；复杂综合题与引用稳定性下降',
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3-14B Q4_K_M',
    url: 'https://hf-mirror.com/unsloth/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-Q4_K_M.gguf',
    sizeBytes: 9001753984,
    note: '质量档：本机内存边缘，下载后需真机验证；不建议日常使用',
  ),
  CatalogModel(
    isChat: false,
    label: 'Qwen3-Embedding-0.6B Q8_0',
    url: 'https://hf-mirror.com/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf',
    sizeBytes: 639150592,
    note: '1024 维；本机实测相关 0.64 / 无关 0.17',
    isDefault: true,
  ),
  CatalogModel(
    isChat: false,
    label: 'Qwen3-Embedding-4B Q8_0',
    url: 'https://hf-mirror.com/Qwen/Qwen3-Embedding-4B-GGUF/resolve/main/Qwen3-Embedding-4B-Q8_0.gguf',
    sizeBytes: 4279660224,
    note: '2560 维，检索更强；更换后必须全量重建索引，导入变慢',
  ),
];

/// 候选展示排序（v2 bugfix）：先按类型分组——生成模型在前、嵌入模型在后；
/// 同类型内按体积升序。即 Qwen3-4B/8B/14B → Embedding-0.6B/4B。
List<CatalogModel> sortedCatalog() {
  final list = [...modelCatalog];
  list.sort((a, b) {
    if (a.isChat != b.isChat) return a.isChat ? -1 : 1;
    return a.sizeBytes.compareTo(b.sizeBytes);
  });
  return list;
}
