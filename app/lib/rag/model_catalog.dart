/// 候选模型目录（v2 P2）：设置页一键下载。
/// URL 于 2026-11-15 经 hf-mirror HEAD 验证（200 + content-length）；
/// 体积为 HEAD 实测字节数；备注引自 docs/工作原理与模型选型.md。
/// 2026-11-19：删掉聊天用的 0.6B（太弱），补一档 9B。
/// 官方 Qwen3.5 没有 6B / 8B 这两档，9B 是 4B 之上最近的一档。
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
  // 2026-11-18：下载源换成魔搭 ModelScope（国内直连）。
  // hf-mirror 的 LFS 会跳去 xethub 海外 CDN，实测 0.57 MB/s；魔搭 8.3 MB/s。
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-2B Q4_K_M',
    url: 'https://www.modelscope.cn/models/unsloth/Qwen3.5-2B-GGUF/resolve/master/Qwen3.5-2B-Q4_K_M.gguf',
    sizeBytes: 1280835840,
    note: '速度档：约 1.28 GiB，聊得动但容易跑题、复读',
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-4B Q4_K_M',
    url: 'https://www.modelscope.cn/models/unsloth/Qwen3.5-4B-GGUF/resolve/master/Qwen3.5-4B-Q4_K_M.gguf',
    sizeBytes: 2740937888,
    note: '默认档：约 2.55 GiB，2B 语无伦次时换它，手机上仍算能用',
    isDefault: true,
  ),
  CatalogModel(
    isChat: true,
    label: 'Qwen3.5-9B Q4_K_M',
    url: 'https://www.modelscope.cn/models/unsloth/Qwen3.5-9B-GGUF/resolve/master/Qwen3.5-9B-Q4_K_M.gguf',
    sizeBytes: 5680522464,
    note: '旗舰档：约 5.29 GiB，更稳更少跑题，但手机上出字明显慢',
  ),
  CatalogModel(
    isChat: false,
    label: 'Qwen3-Embedding-0.6B Q8_0',
    url: 'https://www.modelscope.cn/models/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/master/Qwen3-Embedding-0.6B-Q8_0.gguf',
    sizeBytes: 639150592,
    note: '1024 维；v2 情景记忆用，聊天不必装',
    isDefault: true,
  ),
];

/// 候选展示排序：生成模型在前、嵌入模型在后；同类型内按体积升序。
/// 即 Qwen3.5-2B → 4B → 9B → Embedding-0.6B。
List<CatalogModel> sortedCatalog() {
  final list = [...modelCatalog];
  list.sort((a, b) {
    if (a.isChat != b.isChat) return a.isChat ? -1 : 1;
    return a.sizeBytes.compareTo(b.sizeBytes);
  });
  return list;
}
