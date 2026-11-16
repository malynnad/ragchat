import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:nobodywho/nobodywho.dart' as nobodywho;
import 'package:path_provider/path_provider.dart';

import 'app/theme.dart';

/// 规格书 §7「实现前必须验证」的真机诊断页。
///
/// 验证项：
/// 1. nobodywho 能否加载 Qwen3-8B GGUF（成熟架构；Qwen3.5 新架构风险已规避）
/// 2. 内存预算：可用 RAM ≥ 模型文件 2 倍（官方建议），实测加载是否 OOM
/// 3. Vulkan（GPU）vs CPU 的生成速度对比
/// 4. 嵌入 API：Encoder.encode / encodeBatch / cosineSimilarity 全链路
class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final _log = <String>[];
  final _logScroll = ScrollController();

  String? _modelsDir;
  final _modelFiles = <String, int>{}; // 文件名 → 字节数
  int? _memAvailableKb;
  int? _memTotalKb;

  nobodywho.Encoder? _encoder;
  nobodywho.Chat? _chat;
  bool _chatOnGpu = true;
  bool _busy = false;
  bool _generating = false;
  int _tokenCount = 0;

  static const _chatModelFile = 'qwen3-8b-q4_k_m.gguf';
  static const _embedModelFile = 'qwen3-embedding-0.6b-q8_0.gguf';

  @override
  void initState() {
    super.initState();
    _scanModels();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _scanModels() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        _appendLog('✗ 无法获取外部存储目录');
        return;
      }
      final modelsDir = Directory('${dir.path}/models');
      _modelsDir = modelsDir.path;
      _appendLog('模型目录: ${modelsDir.path}');
      if (!modelsDir.existsSync()) {
        _appendLog('✗ 模型目录不存在（先 adb push 模型）');
        return;
      }
      final files = <String, int>{};
      for (final f in modelsDir.listSync()) {
        if (f is File && f.path.endsWith('.gguf')) {
          files[f.uri.pathSegments.last] = f.lengthSync();
        }
      }
      setState(() {
        _modelFiles
          ..clear()
          ..addAll(files);
      });
      for (final e in files.entries) {
        _appendLog('  ${e.key}: ${(e.value / 1e9).toStringAsFixed(2)} GB');
      }
      if (files.isEmpty) _appendLog('✗ 目录里没有 .gguf 文件');
      _readMemInfo();
    } catch (e) {
      _appendLog('✗ 扫描失败: $e');
    }
  }

  void _readMemInfo() {
    try {
      final lines = File('/proc/meminfo').readAsLinesSync();
      for (final line in lines) {
        if (line.startsWith('MemAvailable:')) {
          _memAvailableKb = int.parse(line.split(RegExp(r'\s+'))[1]);
        } else if (line.startsWith('MemTotal:')) {
          _memTotalKb = int.parse(line.split(RegExp(r'\s+'))[1]);
        }
      }
      setState(() {});
      _appendLog(
        '内存: 可用 ${(_memAvailableKb! / 1048576).toStringAsFixed(1)} GB / 总 ${(_memTotalKb! / 1048576).toStringAsFixed(1)} GB',
      );
      final chatSize = _modelFiles[_chatModelFile];
      if (chatSize != null) {
        final needGb = chatSize * 2 / 1e9;
        final haveGb = _memAvailableKb! / 1048576;
        _appendLog(
          '预算核对: 8B 模型需约 ${needGb.toStringAsFixed(1)} GB 可用（2×规则），当前 ${haveGb.toStringAsFixed(1)} GB → ${haveGb >= needGb ? "达标" : "偏紧，实测见分晓"}',
        );
      }
    } catch (e) {
      _appendLog('✗ 读 /proc/meminfo 失败: $e');
    }
  }

  String _modelPath(String name) => '$_modelsDir/$name';

  Future<void> _loadEncoder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _appendLog('— 加载嵌入模型 $_embedModelFile …');
      final sw = Stopwatch()..start();
      _encoder = await nobodywho.Encoder.fromPath(
        modelPath: _modelPath(_embedModelFile),
      );
      _appendLog('✓ 嵌入模型加载成功（${sw.elapsedMilliseconds} ms）');

      const text = '知识库问答测试：长城有多长？';
      sw.reset();
      final vec = await _encoder!.encode(text: text);
      _appendLog(
        '✓ encode 成功: ${vec.length} 维, ${sw.elapsedMilliseconds} ms, 前3值 ${vec.take(3).map((v) => v.toStringAsFixed(4)).toList()}',
      );

      final batch = await _encoder!.encodeBatch(
        texts: ['长城是中国古代的军事防御工程', '今天股市行情上涨'],
      );
      final sim = nobodywho.cosineSimilarity(
        a: vec.toList(),
        b: batch[0].toList(),
      );
      final sim2 = nobodywho.cosineSimilarity(
        a: vec.toList(),
        b: batch[1].toList(),
      );
      _appendLog(
        '✓ encodeBatch + cosineSimilarity: 相关句 $sim vs 无关句 $sim2（应前者明显更高）',
      );
    } catch (e, st) {
      _appendLog('✗ 嵌入验证失败: $e\n$st');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadChat({required bool useGpu}) async {
    if (_busy) return;
    if (_chat != null) {
      _appendLog('! 已有生成模型实例，先点「释放模型」（避免双倍内存占用）');
      return;
    }
    setState(() {
      _busy = true;
      _chatOnGpu = useGpu;
    });
    try {
      _readMemInfo();
      _appendLog('— 加载生成模型 $_chatModelFile（${useGpu ? "Vulkan GPU" : "CPU"}）…');
      final sw = Stopwatch()..start();
      _chat = await nobodywho.Chat.fromPath(
        modelPath: _modelPath(_chatModelFile),
        contextSize: 8192,
        useGpu: useGpu,
        templateVariables: const {'enable_thinking': false},
        systemPrompt: '你是一个知识库问答助手。根据提供的资料回答问题，答案要简洁。',
      );
      _appendLog(
        '✓ 生成模型加载成功（${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s）→ 验证项1通过：nobodywho 可加载该 GGUF',
      );
      _readMemInfo();
    } catch (e, st) {
      _appendLog('✗ 生成模型加载失败: $e\n$st');
      _appendLog('→ 若为内存不足：关闭后台应用重试，或改用 qwen3:4b');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _askTest() async {
    if (_busy || _chat == null || _generating) return;
    setState(() {
      _generating = true;
      _tokenCount = 0;
    });
    _appendLog('— 流式提问: 「用一句话介绍长城。」');
    final sw = Stopwatch()..start();
    int? firstTokenMs;
    final buf = StringBuffer();
    try {
      final stream = _chat!.ask('用一句话介绍长城。');
      await for (final token in stream) {
        firstTokenMs ??= sw.elapsedMilliseconds;
        _tokenCount++;
        buf.write(token);
        if (_tokenCount % 20 == 0) setState(() {});
      }
      final totalS = sw.elapsedMilliseconds / 1000;
      _appendLog('✓ 回答: $buf');
      _appendLog(
        '✓ 性能[${_chatOnGpu ? "GPU" : "CPU"}]: 首token ${firstTokenMs}ms, $_tokenCount tokens / ${totalS.toStringAsFixed(1)}s = ${(_tokenCount / totalS).toStringAsFixed(1)} tok/s',
      );
      final stats = await _chat!.getStats();
      _appendLog('  上下文: ${stats.contextUsed}/${stats.contextSize} tokens');
    } catch (e) {
      _appendLog('✗ 生成失败: $e');
    } finally {
      setState(() => _generating = false);
    }
  }

  void _stopGeneration() {
    _chat?.stopGeneration();
    _appendLog('— 已发送 stopGeneration()');
  }

  void _releaseModels() {
    _chat = null;
    _encoder = null;
    _appendLog('— 已释放模型引用（Rust 侧由 GC finalizer 回收；彻底释放建议重启 App）');
    _readMemInfo();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final memGb = _memAvailableKb == null
        ? '?'
        : (_memAvailableKb! / 1048576).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(title: const Text('nobodywho 真机验证')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _scanModels,
                  child: const Text('刷新状态'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _loadEncoder,
                  child: const Text('验证嵌入'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _loadChat(useGpu: true),
                  child: const Text('加载8B(GPU)'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _loadChat(useGpu: false),
                  child: const Text('加载8B(CPU)'),
                ),
                FilledButton(
                  onPressed: (_busy || _chat == null || _generating)
                      ? null
                      : _askTest,
                  child: const Text('提问测速'),
                ),
                FilledButton.tonal(
                  onPressed: _generating ? _stopGeneration : null,
                  child: const Text('停止'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _releaseModels,
                  child: const Text('释放模型'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '可用内存: $memGb GB · 模型: ${_modelFiles.length} 个'
                '${_generating ? " · 生成中 $_tokenCount tokens" : ""}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _logScroll,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: const TextStyle(
                  fontSize: kFontCaption,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
