import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../common/models/app_settings.dart';
import '../../common/services/settings_service.dart';
import '../../common/services/sync_service.dart';
import '../../common/services/print_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Logger _logger = Logger();
  final SettingsService _settingsService = SettingsService();
  final SyncService _syncService = SyncService();
  final PrintService _printService = PrintService();

  late AppSettings _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  // Form controllers
  final _apiUrlController = TextEditingController();
  final _printerAddressController = TextEditingController();
  final _printerPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _printerAddressController.dispose();
    _printerPortController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      await _settingsService.initialize();
      _settings = _settingsService.getSettings();

      // Update controllers
      _apiUrlController.text = _settings.apiServerUrl;
      _printerAddressController.text = _settings.printerAddress;
      _printerPortController.text = _settings.printerPort.toString();

      setState(() => _isLoading = false);
    } catch (e) {
      _logger.e('Failed to load settings: $e');
      _showErrorSnackBar('Failed to load settings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      // Validate input
      final apiUrl = _apiUrlController.text.trim();
      final printerAddress = _printerAddressController.text.trim();
      final printerPort = int.tryParse(_printerPortController.text.trim());

      if (apiUrl.isEmpty) {
        throw Exception('API Server URL cannot be empty');
      }

      if (printerAddress.isEmpty) {
        throw Exception('Printer address cannot be empty');
      }

      if (printerPort == null || printerPort <= 0 || printerPort > 65535) {
        throw Exception('Invalid printer port');
      }

      // Update settings
      final updatedSettings = _settings.copyWith(
        apiServerUrl: apiUrl,
        printerAddress: printerAddress,
        printerPort: printerPort,
      );

      // 先保存设置到本地存储
      await _settingsService.saveSettings(updatedSettings);
      _logger.i('Settings saved to local storage');

      // 立即应用设置到服务
      _syncService.configureBaseUrl(apiUrl);
      _printService.configurePrinter(
        printerIP: printerAddress,
        printerPort: printerPort,
      );
      _logger.i('Settings applied to services - API: $apiUrl, Printer: $printerAddress:$printerPort');

      _settings = updatedSettings;
      _showSuccessSnackBar('Settings saved and applied successfully');

    } catch (e) {
      _logger.e('Failed to save settings: $e');
      _showErrorSnackBar('Failed to save settings: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    try {
      final isConnected = await _syncService.checkNetworkConnectivity();
      if (isConnected) {
        _showSuccessSnackBar('API connection successful');
      } else {
        _showErrorSnackBar('API connection failed');
      }
    } catch (e) {
      _showErrorSnackBar('Connection test failed: $e');
    }
  }

  Future<void> _testPrinter() async {
    try {
      final isReady = await _printService.checkPrinterStatus();
      if (isReady) {
        _showSuccessSnackBar('Printer connection successful');
      } else {
        _showErrorSnackBar('Printer connection failed');
      }
    } catch (e) {
      _showErrorSnackBar('Printer test failed: $e');
    }
  }

  Future<void> _resetSettings() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Settings'),
        content: Text('Are you sure you want to reset all settings to defaults?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Reset'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (result == true) {
      await _settingsService.resetToDefaults();
      await _loadSettings();
      _showSuccessSnackBar('Settings reset to defaults');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          IconButton(
            icon: Icon(Icons.restore),
            onPressed: _resetSettings,
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Server Section
            _buildSectionCard(
              title: 'API Server Configuration',
              icon: Icons.cloud,
              children: [
                TextFormField(
                  controller: _apiUrlController,
                  decoration: InputDecoration(
                    labelText: 'API Server URL',
                    hintText: 'https://api.example.com',
                    prefixIcon: Icon(Icons.language),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testConnection,
                        icon: Icon(Icons.wifi_find),
                        label: Text('Test Connection'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SwitchListTile(
                  title: Text('Enable Auto Sync'),
                  subtitle: Text('Automatically sync orders to server'),
                  value: _settings.enableAutoSync,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(enableAutoSync: value);
                    });
                    _settingsService.updateAutoFeatures(enableAutoSync: value);
                  },
                ),
              ],
            ),

            SizedBox(height: 24),

            // Printer Section
            _buildSectionCard(
              title: 'Printer Configuration',
              icon: Icons.print,
              children: [
                DropdownButtonFormField<String>(
                  value: _settings.printerType,
                  decoration: InputDecoration(
                    labelText: 'Printer Type',
                    prefixIcon: Icon(Icons.print),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'network', child: Text('Network Printer')),
                    DropdownMenuItem(value: 'usb', child: Text('USB Printer')),
                    DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth Printer')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _settings = _settings.copyWith(printerType: value);
                      });
                    }
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _printerAddressController,
                  decoration: InputDecoration(
                    labelText: _settings.printerType == 'network' ? 'IP Address' : 'Address',
                    hintText: _settings.printerType == 'network' ? '192.168.1.100' : 'Printer address',
                    prefixIcon: Icon(Icons.location_on),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _printerPortController,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    hintText: '9100',
                    prefixIcon: Icon(Icons.settings_ethernet),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: _settings.printerType == 'network',
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testPrinter,
                        icon: Icon(Icons.print_outlined),
                        label: Text('Test Printer'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SwitchListTile(
                  title: Text('Enable Auto Print'),
                  subtitle: Text('Automatically print orders after placing'),
                  value: _settings.enableAutoPrint,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(enableAutoPrint: value);
                    });
                    _settingsService.updateAutoFeatures(enableAutoPrint: value);
                  },
                ),
              ],
            ),

            SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 20,
          right: 20,
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 20,
          right: 20,
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }
}
