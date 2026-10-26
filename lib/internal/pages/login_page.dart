import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../../common/services/api_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/app_initialization_service.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/language_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginPage({Key? key, required this.onLoginSuccess}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _apiServerUrlController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _rememberMe = false;
  bool _isTestingConnection = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
    _loadApiServerUrl();
  }

  Future<void> _loadSavedAccount() async {
    final box = await Hive.openBox('authBox');
    final savedUsername = box.get('savedUsername') as String?;
    final savedPassword = box.get('savedPassword') as String?;
    final rememberMe = box.get('rememberMe') as bool?;
    if (savedUsername != null) _usernameController.text = savedUsername;
    if (savedPassword != null) _passwordController.text = savedPassword;
    if (rememberMe != null) _rememberMe = rememberMe;
    setState(() {});
  }

  Future<void> _loadApiServerUrl() async {
    final settingsService = SettingsService();
    await settingsService.initialize();
    final settings = settingsService.getSettings();
    final serverUrl = settings.apiServerUrl.isNotEmpty
        ? settings.apiServerUrl
        : 'http://127.0.0.1:8000/api';
    _apiServerUrlController.text = serverUrl;
  }

  Future<void> _persistServerUrl(String serverUrl, {bool clearAuthToken = false}) async {
    final normalizedUrl = SettingsService.cleanUrlFormat(serverUrl);
    final settingsService = SettingsService();
    await settingsService.initialize();
    await settingsService.updateApiServerUrl(normalizedUrl);

    final api = ApiService();
    if (clearAuthToken) {
      final box = await Hive.openBox('authBox');
      await box.delete('authToken');
      api.clearAuthToken();
    }
  }

  Future<void> _enterApp() async {
    await AppInitializationService.startBackgroundTasksAndNetworkListener();
    await BackgroundTaskManager().initialize();
    widget.onLoginSuccess();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _error = null;
    });
    try {
      final url = SettingsService.cleanUrlFormat(_apiServerUrlController.text);
      if (url.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      final api = ApiService();
      await api.updateBaseUrl(url);

      // 尝试连接服务器健康检查接口
      try {
        final response = await api.get('/health').timeout(const Duration(seconds: 10));
        if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('连接成功'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          setState(() => _error = '连接失败: ${response.statusCode}');
        }
      } catch (e) {
        setState(() => _error = '连接错误: $e');
      }
    } catch (e) {
      setState(() => _error = '测试失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  static final Logger _logger = Logger();

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _logger.i('Start login');
    final serverUrl = SettingsService.cleanUrlFormat(_apiServerUrlController.text);
    _logger.i('Server URL: $serverUrl | Username: ${_usernameController.text.trim()}');
    try {
      if (serverUrl.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      final api = ApiService();
      await api.updateBaseUrl(serverUrl);

      final response = await api.post('login', data: {
        'userLogin': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      });
      _logger.d('Response: $response');
      final token = response.data?['token'] ?? response.data?['authToken'];
      final box = await Hive.openBox('authBox');
      if (token != null) {
        await box.put('authToken', token);
        api.setAuthToken(token);
        await _persistServerUrl(serverUrl);

        if (_rememberMe) {
          await box.put('savedUsername', _usernameController.text.trim());
          await box.put('savedPassword', _passwordController.text.trim());
          await box.put('rememberMe', true);
        } else {
          await box.delete('savedUsername');
          await box.delete('savedPassword');
          await box.put('rememberMe', false);
        }
        _logger.i('Login success, token saved.');
        // 登录成功后启动后台任务和网络监听
        await _enterApp();
      } else {
        _logger.w('登录失败，未获取到Token');
        setState(() {
          _error = '登录失败，未获取到Token';
        });
      }
    } catch (e, stack) {
      _logger.e('Login Exception: $e', error: e, stackTrace: stack);
      setState(() {
        _error = '登录失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _skipLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final serverUrl = SettingsService.cleanUrlFormat(_apiServerUrlController.text);
      if (serverUrl.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      await _persistServerUrl(serverUrl, clearAuthToken: true);
      _logger.i('Skip login selected, entering app without authentication.');

      await _enterApp();
    } catch (e, stack) {
      _logger.e('Skip login exception: $e', error: e, stackTrace: stack);
      setState(() {
        _error = '跳过登录失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('login_title'.tr),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Card(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('login_title'.tr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    // API Server URL Configuration
                    TextField(
                      controller: _apiServerUrlController,
                      decoration: InputDecoration(
                        labelText: 'api_url_label'.tr,
                        hintText: 'api_url_hint'.tr,
                        prefixIcon: const Icon(Icons.cloud),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isTestingConnection ? null : _testConnection,
                        icon: _isTestingConnection
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_find),
                        label: Text(_isTestingConnection ? 'testing'.tr : 'test_connection'.tr),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(labelText: 'username'.tr),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(labelText: 'password'.tr),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (val) {
                            setState(() {
                              _rememberMe = val ?? false;
                            });
                          },
                        ),
                        Text('remember_me'.tr),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading ? const CircularProgressIndicator() : Text('login_btn'.tr),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _apiServerUrlController.dispose();
    super.dispose();
  }
}