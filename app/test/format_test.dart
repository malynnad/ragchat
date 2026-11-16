import 'package:ragchat/app/format.dart';
import 'package:test/test.dart';

/// 存储占用显示：单位自适应，避免 48KB 的库显示成 0.0 MB（真机冒烟发现）。
/// 期望值手算（十进制单位，与磁盘标称一致）。
void main() {
  test('小于 1KB 显示 B', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
  });

  test('小于 1MB 显示 KB（真机 48KB 库不再显示 0.0 MB）', () {
    expect(formatBytes(49152), '49 KB');
    expect(formatBytes(999499), '999 KB');
  });

  test('KB 四舍五入到 1000 时进位为 MB', () {
    expect(formatBytes(999999), '1.00 MB');
  });

  test('小于 1GB 显示 MB，两位小数', () {
    expect(formatBytes(1500000), '1.50 MB');
  });

  test('GB 级显示两位小数', () {
    expect(formatBytes(5860000000), '5.86 GB');
  });
}
