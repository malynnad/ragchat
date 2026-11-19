import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 系统 TTS（Android TextToSpeech）封装：免费、离线、不碰网络。
/// 没有可用引擎时 [speak] 返回 false，UI 给一句提示就行。
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// 是否正在朗读（awaitSpeakCompletion 生效时可靠）。
  bool speaking = false;

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
      await _tts.setPitch(pitch).timeout(const Duration(seconds: 3));
      await _tts.awaitSpeakCompletion(true).timeout(
        const Duration(seconds: 3),
      );
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('[tts] init failed: $e');
      return false;
    }
  }

  Future<bool> speak(String text, {double? rate}) async {
    final ok = await init(rate: rate ?? 0.5);
    if (!ok) return false;
    try {
      if (rate != null) await _tts.setSpeechRate(rate.clamp(0.1, 0.9));
      await _tts.stop().timeout(const Duration(seconds: 3));
      speaking = true;
      // 引擎卡死时不要永远停不下来：5 分钟后强制结束（正常朗读远短于此）。
      await _tts.speak(text).timeout(const Duration(minutes: 5));
      speaking = false;
      return true;
    } catch (e) {
      speaking = false;
      debugPrint('[tts] speak failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
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
    _tts.stop();
  }
}
