import 'package:ragchat/chat/app_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试专用：ffi 内存 SQLite（宿主机可跑，无需真机）。
/// widget 测试必须使用同 isolate 工厂，避免 fake-async 下跨 isolate 端口挂起。
Future<AppDb> openTestDb({bool inIsolate = true}) async {
  final factory = inIsolate ? databaseFactoryFfi : databaseFactoryFfiNoIsolate;
  final db = await factory.openDatabase(inMemoryDatabasePath);
  return AppDb.fromDatabase(db);
}
