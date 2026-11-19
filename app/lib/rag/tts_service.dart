import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 引擎里的一个音色。
class TtsVoice {
  const TtsVoice({required this.name, required this.locale, this.label});
  final String name;
  final String locale;
  final String? label;

  /// 引擎给的 name 本身就是「中文（温柔女声）」这种中文标签就用它；
  /// 否则退回 displayName，再退回 locale。
  String get display {
    final l = label?.trim() ?? '';
    if (l.isNotEmpty) return l;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(name)) return name;
    // 讯飞这类引擎只给 locale：翻译成人话。
    const zh = {
      'zh': '中文（通用）',
      'zh-hans': '中文（简体）',
      'zh-hant': '中文（繁体）',
      'zh-cn': '中文（普通话）',
      'zh-tw': '中文（台湾）',
      'zh-hk': '中文（粤语）',
    };
    return zh[locale.toLowerCase()] ?? locale;
  }
}

/// 系统 TTS（Android TextToSpeech）封装：免费、离线、不碰网络。
/// 没有可用引擎时 [speak] 返回 false，UI 给一句提示就行。
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// 是否正在朗读（由引擎的 completion/cancel 回调驱动）。
  bool speaking = false;

  /// 朗读结束/被打断时回调，UI 用它把「停止」变回「朗读」。
  VoidCallback? onDone;
  bool _wired = false;
  String? _engine;

  Future<bool> init({double rate = 0.5, double pitch = 1.0}) async {
    if (_ready) return true;
    try {
      // 手机上有无引擎，这里能直接反映出来。
      if (!await _tts
          .isLanguageAvailable('zh-CN')
          .timeout(const Duration(seconds: 3))) {
        debugPrint('[tts] zh-CN 不可用');
        return false;
      }
      await _tts.setLanguage('zh-CN');
      await _tts
          .setSpeechRate(rate.clamp(0.1, 0.9))
          .timeout(const Duration(seconds: 3));
      await _tts
          .setPitch(pitch.clamp(0.7, 1.3))
          .timeout(const Duration(seconds: 3));
      // 不用 awaitSpeakCompletion：OPPO 等引擎会在开始时就 resolve，
      // 导致「停止」按钮一闪就回去。改由回调驱动状态。
      if (!_wired) {
        _wired = true;
        _tts.setCompletionHandler(_finish);
        _tts.setCancelHandler(_finish);
        _tts.setErrorHandler((msg) {
          debugPrint('[tts] engine error: $msg');
          _finish();
        });
      }
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('[tts] init failed: $e');
      return false;
    }
  }

  /// 系统里所有 TTS 引擎（包名）。装多个引擎时用。
  Future<List<String>> listEngines() async {
    try {
      final raw = await _tts.getEngines.timeout(const Duration(seconds: 4));
      final list = <String>[];
      if (raw is List) {
        for (final e in raw) {
          if (e != null) list.add(e.toString());
        }
      }
      debugPrint('[tts] engines=$list');
      return list;
    } catch (e) {
      debugPrint('[tts] getEngines failed: $e');
      return const [];
    }
  }

  /// 换引擎：flutter_tts 会重启底层 TTS，之后再查音色/发音。
  Future<bool> useEngine(String? id) async {
    if (id == _engine) return true;
    try {
      _engine = id;
      if (id != null && id.isNotEmpty) {
        await _tts.setEngine(id).timeout(const Duration(seconds: 5));
      } else {
        await _tts.setEngine('').timeout(const Duration(seconds: 5));
      }
      _ready = false;
      _wired = false;
      debugPrint('[tts] engine => ${id ?? 'default'}');
      return true;
    } catch (e) {
      debugPrint('[tts] setEngine failed: $e');
      return false;
    }
  }

  /// 列出引擎提供的中文音色（没有中文时退回全部）。
  Future<List<TtsVoice>> listVoices() async {
    try {
      final raw = await _tts.getVoices.timeout(const Duration(seconds: 4));
      final all = <TtsVoice>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is! Map) continue;
          final name = (v['name'] ?? '').toString();
          final locale = (v['locale'] ?? '').toString();
          if (name.isEmpty) continue;
          all.add(
            TtsVoice(
              name: name,
              locale: locale,
              label: v['displayName']?.toString(),
            ),
          );
        }
      }
      final zh = all.where((v) {
        final loc = v.locale.toLowerCase();
        return loc.startsWith('zh') || loc == 'chn' || v.name.contains('中文');
      });
      final picked = zh.isNotEmpty ? zh.toList() : all;
      debugPrint('[tts] voices=${picked.map((v) => v.display).join(' / ')}');
      return picked;
    } catch (e) {
      debugPrint('[tts] getVoices failed: $e');
      return const [];
    }
  }

  Future<bool> speak(
    String text, {
    double? rate,
    double? pitch,
    String? voiceName,
    String? voiceLocale,
  }) async {
    final ok = await init(rate: rate ?? 0.5);
    if (!ok) return false;
    try {
      if (rate != null) await _tts.setSpeechRate(rate.clamp(0.1, 0.9));
      await _tts.stop().timeout(const Duration(seconds: 3));
      if (pitch != null) {
        await _tts.setPitch(pitch.clamp(0.7, 1.3)).timeout(
          const Duration(seconds: 3),
        );
      }
      if (voiceName != null && voiceName.isNotEmpty) {
        final r = await _tts
            .setVoice({'name': voiceName, 'locale': voiceLocale ?? 'zh-CN'})
            .timeout(const Duration(seconds: 3));
        debugPrint('[tts] setVoice($voiceName, $voiceLocale) => $r');
        if (r != 1 && voiceLocale != null) {
          // 讯飞这类引擎只按 locale 认音色：name 对不上就退回设语言。
          await _tts.setLanguage(voiceLocale).timeout(
            const Duration(seconds: 3),
          );
        }
      }
      speaking = true;
      // 启动就返回；结束靠 completion 回调，不会卡住 UI。
      await _tts.speak(text).timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      speaking = false;
      debugPrint('[tts] speak failed: $e');
      return false;
    }
  }

  void _finish() {
    speaking = false;
    onDone?.call();
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _finish();
  }

  /// 语速 0.1–0.9（Android 的 1.0 会快得听不清中文）。
  Future<void> setRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate.clamp(0.1, 0.9));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void dispose() {
    try {
      _tts.stop();
    } catch (_) {}
  }
}
