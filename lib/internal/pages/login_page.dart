import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../common/services/api_service.dart';
import '../../common/services/background_task_manager.dart';
import '../../common/services/app_initialization_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginPage({Key? key, required this.onLoginSuccess}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _rememberMe = false;
  String? _apiServerUrl;

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
    setState(() {
      _apiServerUrl = url;
    });
  }

  Future<void> _showSetApiServerDialog() async {
    final controller = TextEditingController(text: _apiServerUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('设置服务器地址'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: '如：https://api.xxx.com'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text('保存'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      final box = await Hive.openBox('authBox');
      await box.put('apiServerUrl', result);
      setState(() {
        _apiServerUrl = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('服务器地址已保存')));
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    print('[LOGIN] Start login');
    print('[LOGIN] Server URL: [32m[1m[4m[7m' + (_apiServerUrl ?? 'null') + '\u001b[0m');
    print('[LOGIN] Username: ' + _usernameController.text.trim());
    try {
      final api = ApiService();
      if (_apiServerUrl != null && _apiServerUrl!.isNotEmpty) {
        api.updateBaseUrl(_apiServerUrl!);
        print('[LOGIN] ApiService baseUrl set to: ' + _apiServerUrl!);
      }
      final loginData = {
        'userLogin': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
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
        await AppInitializationService.startBackgroundTasksAndNetworkListener();
        await BackgroundTaskManager().initialize();
        widget.onLoginSuccess();
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
      setState(() {
        _isLoading = false;
      });
      print('[LOGIN] End login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: '设置服务器地址',
            onPressed: _showSetApiServerDialog,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Card(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('登录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                    Text(_error!, style: TextStyle(color: Colors.red)),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading ? CircularProgressIndicator() : Text('登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}