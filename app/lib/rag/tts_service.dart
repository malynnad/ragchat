import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  Future<bool> speak(String text, {double? rate}) async {
    final ok = await init(rate: rate ?? 0.5);
    if (!ok) return false;
    try {
      if (rate != null) await _tts.setSpeechRate(rate.clamp(0.1, 0.9));
      await _tts.stop().timeout(const Duration(seconds: 3));
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
    _tts.stop();
  }
}
