import 'package:hive/hive.dart';

class AdminPasswordService {
  static const String _boxName = 'authBox';
  static const String _passwordKey = 'adminPassword';
  static const String _defaultPassword = '12345abc';

  /// 获取管理员密码（第一次会返回默认密码）
  static Future<String> getAdminPassword() async {
    try {
      final box = await Hive.openBox(_boxName);
      final password = box.get(_passwordKey) as String?;
      if (password == null) {
        // 首次初始化为默认密码
        await box.put(_passwordKey, _defaultPassword);
        return _defaultPassword;
      }
      return password;
    } catch (e) {
      print('[ERROR] AdminPasswordService getAdminPassword: $e');
      return _defaultPassword;
    }
  }

  /// 验证密码
  static Future<bool> verifyPassword(String inputPassword) async {
    try {
      final correctPassword = await getAdminPassword();
      return inputPassword == correctPassword;
    } catch (e) {
      print('[ERROR] AdminPasswordService verifyPassword: $e');
      return false;
    }
  }

  /// 修改密码
  static Future<bool> changePassword(String oldPassword, String newPassword) async {
    try {
      // 验证旧密码
      final isValid = await verifyPassword(oldPassword);
      if (!isValid) {
        return false;
      }

      // 保存新密码
      final box = await Hive.openBox(_boxName);
      await box.put(_passwordKey, newPassword);
      return true;
    } catch (e) {
      print('[ERROR] AdminPasswordService changePassword: $e');
      return false;
    }
  }

  /// 重置为默认密码
  static Future<void> resetToDefault() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_passwordKey, _defaultPassword);
    } catch (e) {
      print('[ERROR] AdminPasswordService resetToDefault: $e');
    }
  }
}

