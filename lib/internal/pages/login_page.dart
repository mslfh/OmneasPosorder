import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../common/services/api_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/app_initialization_service.dart';
import '../../common/services/settings_service.dart';

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
    final box = await Hive.openBox('authBox');
    final url = box.get('apiServerUrl') as String?;
    final defaultUrl = 'http://127.0.0.1:8000/api';
    final serverUrl = url ?? defaultUrl;
    _apiServerUrlController.text = serverUrl;
  }

  String _cleanUrlFormat(String url) {
    // 去除末尾的 / 
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<void> _persistServerUrl(String serverUrl, {bool clearAuthToken = false}) async {
    final api = ApiService();
    api.updateBaseUrl(serverUrl);

    final box = await Hive.openBox('authBox');
    await box.put('apiServerUrl', serverUrl);
    if (clearAuthToken) {
      await box.delete('authToken');
      api.clearAuthToken();
    }

    final settingsService = SettingsService();
    try {
      await settingsService.initialize();
      await settingsService.updateApiServerUrl(serverUrl);
      print('[LOGIN] Settings synchronized successfully');
    } catch (e) {
      print('[LOGIN] Warning: Could not sync to settings: $e');
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
      final url = _cleanUrlFormat(_apiServerUrlController.text.trim());
      if (url.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      final api = ApiService();
      api.updateBaseUrl(url);

      // 尝试连接服务器健康检查接口
      try {
        final response = await api.get('/health').timeout(Duration(seconds: 10));
        if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('连接成功'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() => _error = '连接失败: ${response.statusCode}');
        }
      } catch (e) {
        setState(() => _error = '连接错误: $e');
      }
    } catch (e) {
      setState(() => _error = '测试失败: $e');
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    print('[LOGIN] Start login');
    final serverUrl = _cleanUrlFormat(_apiServerUrlController.text.trim());
    print('[LOGIN] Server URL: ' + serverUrl);
    print('[LOGIN] Username: ' + _usernameController.text.trim());
    try {
      if (serverUrl.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      final api = ApiService();
      api.updateBaseUrl(serverUrl);
      print('[LOGIN] ApiService baseUrl set to: ' + serverUrl);

      const loginData = {
        'userLogin': 'placeholder',
        'password': 'placeholder',
      };
      print('[LOGIN] Request data: ' + loginData.toString());
      final response = await api.post('login', data: {
        'userLogin': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      });
      print('[LOGIN] Response: ' + response.toString());
      print('[LOGIN] Response.data: ' + response.data.toString());
      final token = response.data['token'] ?? response.data['authToken'];
      print('[LOGIN] Token: ' + token.toString());
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
        print('[LOGIN] Login success, token saved.');
        // 登录成功后启动后台任务和网络监听
        await _enterApp();
      } else {
        print('[LOGIN] 登录失败，未获取到Token');
        setState(() {
          _error = '登录失败，未获取到Token';
        });
      }
    } catch (e, stack) {
      print('[LOGIN] Exception: ' + e.toString());
      print('[LOGIN] Stack: ' + stack.toString());
      setState(() {
        _error = '登录失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print('[LOGIN] End login');
    }
  }

  Future<void> _skipLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final serverUrl = _cleanUrlFormat(_apiServerUrlController.text.trim());
      if (serverUrl.isEmpty) {
        setState(() => _error = '请输入服务器地址');
        return;
      }

      await _persistServerUrl(serverUrl, clearAuthToken: true);
      print('[LOGIN] Skip login selected, entering app without authentication.');

      await _enterApp();
    } catch (e, stack) {
      print('[LOGIN] Skip login exception: ' + e.toString());
      print('[LOGIN] Skip login stack: ' + stack.toString());
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
        title: Text('登录'),
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
                    Text('登录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 24),
                    // API Server URL Configuration
                    TextField(
                      controller: _apiServerUrlController,
                      decoration: InputDecoration(
                        labelText: '服务器地址',
                        hintText: 'http://127.0.0.1:8000/api',
                        prefixIcon: Icon(Icons.cloud),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isTestingConnection ? null : _testConnection,
                        icon: _isTestingConnection
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.wifi_find),
                        label: Text(_isTestingConnection ? '测试中...' : '测试连接'),
                      ),
                    ),
                    SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(labelText: '账号'),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(labelText: '密码'),
                      obscureText: true,
                    ),
                    SizedBox(height: 16),
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
                        Text('记住账号和密码'),
                      ],
                    ),
                    SizedBox(height: 24),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading ? CircularProgressIndicator() : Text('登录'),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _skipLogin,
                        child: Text('跳过登录'),
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