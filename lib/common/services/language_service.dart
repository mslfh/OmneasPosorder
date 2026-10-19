import 'package:flutter/material.dart';

class LanguageService {
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en', 'US'));

  String _currentLanguage = 'en';
  String get currentLanguage => _currentLanguage;

  void initialize(String languageCode) {
    _currentLanguage = (languageCode == 'zh') ? 'zh' : 'en';
    localeNotifier.value = _currentLanguage == 'zh'
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US');
  }

  void changeLanguage(String languageCode) {
    if (_currentLanguage == languageCode) return;
    _currentLanguage = (languageCode == 'zh') ? 'zh' : 'en';
    localeNotifier.value = _currentLanguage == 'zh'
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US');
  }

  /// 全局多语言字典
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Navigation / Tabs
      'nav_menu': 'Menu',
      'nav_orders': 'Orders',
      'nav_reports': 'Reports',
      'nav_settings': 'Settings',

      // Login Page
      'login_title': 'Omneas POS Login',
      'username': 'Username',
      'password': 'Password',
      'remember_me': 'Remember Me',
      'login_btn': 'Log In',
      'logging_in': 'Logging in...',
      'login_failed': 'Login failed. Please check credentials.',

      // Settings Page
      'settings_title': 'Settings',
      'language_setting': 'App Language',
      'language_name': 'English',
      'zh_cn': '简体中文',
      'en_us': 'English',
      'select_language': 'Select App Language',

      // Sections
      'section_general': 'General Settings',
      'section_api': 'API Server Configuration',
      'section_tasks': 'Background Tasks',
      'section_printer': 'Printer & Hardware',
      'section_store_hours': 'Store Hours Configuration',
      'section_merchant': 'Merchant Profile',
      'section_system': 'Account & System',
      'section_status': 'System Status',

      // Merchant Profile
      'merchant_name': 'Store Name',
      'merchant_address': 'Address',
      'merchant_phone': 'Phone Number',
      'merchant_abn': 'ABN / Tax ID',
      'edit_merchant': 'Edit Merchant Profile',
      'merchant_save_success': 'Merchant info updated successfully',

      // API Settings
      'api_url_label': 'API Server URL',
      'api_url_hint': 'http://127.0.0.1:8000/api/',
      'test_connection': 'Test Connection',
      'testing': 'Testing...',
      'auto_sync': 'Auto Sync Orders',
      'auto_sync_desc': 'Automatically sync orders to remote server',
      'conn_success': 'API Connection Successful',
      'conn_failed': 'API Connection Failed',

      // Background Tasks
      'fetch_interval': 'Remote Orders Fetch Interval',
      'fetch_interval_unit': 'seconds',
      'match_interval': 'Order Match Check Interval',
      'match_interval_unit': 'minutes',
      'task_status_title': 'Background Task Status',
      'task_status_subtitle': 'Real-time monitoring of background tasks',
      'within_hours': 'Within Store Hours',
      'outside_hours': 'Outside Store Hours (Paused)',
      'foreground_service': 'Foreground Fetch Service',

      // Printer
      'printer_type': 'Printer Type',
      'printer_net': 'Network Printer',
      'printer_ip': 'Printer IP Address',
      'printer_port': 'Printer Port',
      'test_printer': 'Test Printer',
      'auto_print': 'Auto Print Orders',
      'auto_print_desc': 'Automatically print orders after creation',
      'printer_success': 'Printer Connection Successful',
      'printer_failed': 'Printer Connection Failed',

      // Store hours
      'edit_hours': 'Edit Store Hours',
      'closed': 'Closed',
      'add_time_range': 'Add Time Range',

      // Days of Week
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',

      // System / Logout
      'reset_settings': 'Reset to Defaults',
      'reset_confirm_title': 'Reset Settings',
      'reset_confirm_msg': 'Are you sure you want to reset all settings to defaults?',
      'logout': 'Log Out',
      'logout_confirm_title': 'Log Out',
      'logout_confirm_msg': 'Are you sure you want to log out?',

      // Order Page & Cart
      'dining_table': 'Table',
      'select_table': 'Select Table',
      'table_order': 'Table Order',
      'table_reserved': 'Reserved',
      'table_occupied': 'Occupied',
      'table_available': 'Available',
      'import_preorder': 'Import Preorder',
      'submit_table_order': 'Submit Order',
      'append_items': 'Edit Items',
      'edit_items': 'Edit Items',
      'guest_count': 'Guests',
      'reservation_info': 'Reservation Info',
      'active_order_info': 'Active Table Order',
      'refresh_tables': 'Refresh Tables',
      'order_cart_title': 'Selected Products',
      'clear_cart': 'Clear All',
      'checkout': 'Checkout',
      'empty_cart_msg': 'No items selected yet',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'discount': 'Discount',
      'total': 'Total',
      'search_menu_hint': 'Search menu items...',
      'all_categories': 'All',
      'quick_input': 'Search',

      // Order List Page & Detail Pages
      'order_list_title': 'Order Management',
      'order_detail': 'Order Details',
      'server_order_detail': 'Server Order Details',
      'search_order_hint': 'Search order ID or customer...',
      'order_id': 'Order #',
      'order_amount': 'Amount',
      'order_time': 'Time',
      'order_status': 'Status',
      'sync_status': 'Sync Status',
      'print_status': 'Print Status',
      'status_pending': 'Pending',
      'status_completed': 'Completed',
      'status_cancelled': 'Cancelled',
      'status_confirmed': 'Confirmed',
      'reprint_ticket': 'Reprint Ticket',
      'show_local_orders': 'Show Local Orders',
      'show_server_orders': 'Show Server Orders',
      'local_orders': 'Local Orders',
      'server_orders': 'Server Orders',
      'pull': 'Pull',
      'resync': 'Resync',
      'reprint': 'Reprint',
      'pull_all': 'Pull Server Orders to Local DB',
      'no_orders': 'No Orders',
      'no_orders_sub': 'Orders will appear here after placing',

      // Reports Page
      'report_title': 'Sales Reports',
      'today_sales': 'Today\'s Sales',
      'total_orders': 'Total Orders',
      'average_order': 'Average Value',
      'sales_trend': 'Sales Trend',

      // Dialogs & Configurations
      'choose_order': 'Choose Order',
      'match_details': 'Order Match Details',
      'matched': 'Matched',
      'mismatched': 'Data Mismatched',
      'printer_config': 'Printer Configuration',
      'server_config': 'Server Configuration',

      // Status Bar & Service Status
      'printer_status': 'Printer',
      'server_status': 'Server',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'check_status': 'Checking...',

      // Admin Mode
      'admin_mode': 'Admin Mode',
      'enter_admin_pwd': 'Enter Admin Password',
      'pwd_label': 'Password',
      'invalid_pwd': 'Password incorrect',
      'admin_mode_activated': 'Entered Admin Mode',
      'change_pwd': 'Change Password',
      'exit_admin': 'Exit Admin',

      // Common Actions & Labels
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'ok': 'OK',
      'reset': 'Reset',
      'status_running': 'Running',
      'status_stopped': 'Stopped',
      'status_active': 'Active',
      'status_inactive': 'Inactive',
      'permission_request': 'Request / Refresh Permissions',
      'permission_triggered': 'Permission request triggered',
      'edit': 'Edit',
      'save': 'Save',
      'delete': 'Delete',
      'last_updated': 'Last updated',
      'quantity': 'Qty',
      'price': 'Price',
      'options': 'Options',
      'note': 'Note',
      'items': 'Items',
      'customer': 'Customer',
      'payment': 'Payment',
      'cash': 'Cash',
      'pos': 'POS / Card',
      'online': 'Online',
      'terminal': 'Terminal',
      'refund': 'Refund',
      'select_all': 'Select All',
      'search': 'Search',
      'back': 'Back',
      'copy': 'Copy',
      'no_data': 'No Data',
    },
    'zh': {
      // Navigation / Tabs
      'nav_menu': '点餐',
      'nav_orders': '订单',
      'nav_reports': '报表',
      'nav_settings': '设置',

      // Login Page
      'login_title': 'Omneas POS 系统登录',
      'username': '用户名',
      'password': '密码',
      'remember_me': '记住密码',
      'login_btn': '登 录',
      'logging_in': '正在登录...',
      'login_failed': '登录失败，请检查账号密码。',

      // Settings Page
      'settings_title': '系统设置',
      'language_setting': '语言设置',
      'language_name': '简体中文',
      'zh_cn': '简体中文',
      'en_us': 'English',
      'select_language': '选择应用语言',

      // Sections
      'section_general': '通用设置',
      'section_api': 'API 服务器配置',
      'section_tasks': '后台任务管理',
      'section_printer': '打印机与硬件',
      'section_store_hours': '营业时间设置',
      'section_merchant': '商家信息设置',
      'section_system': '账号与系统操作',
      'section_status': '运行状态概览',

      // Merchant Profile
      'merchant_name': '店铺名称',
      'merchant_address': '店铺地址',
      'merchant_phone': '联系电话',
      'merchant_abn': 'ABN 税号',
      'edit_merchant': '编辑商家信息',
      'merchant_save_success': '商家信息更新成功',

      // API Settings
      'api_url_label': 'API 服务器 URL',
      'api_url_hint': 'http://127.0.0.1:8000/api/',
      'test_connection': '测试服务器连接',
      'testing': '测试中...',
      'auto_sync': '自动同步订单',
      'auto_sync_desc': '自动将本地订单同步至远程服务器',
      'conn_success': 'API 连接测试成功',
      'conn_failed': 'API 连接测试失败',

      // Background Tasks
      'fetch_interval': '远程订单拉取间隔',
      'fetch_interval_unit': '秒',
      'match_interval': '订单数据核对间隔',
      'match_interval_unit': '分钟',
      'task_status_title': '后台任务管理器状态',
      'task_status_subtitle': '实时监控后台定时服务运行情况',
      'within_hours': '营业时间内',
      'outside_hours': '非营业时间（暂停）',
      'foreground_service': '前台拉取服务',

      // Printer
      'printer_type': '打印机类型',
      'printer_net': '网络打印机',
      'printer_ip': '打印机 IP 地址',
      'printer_port': '端口号',
      'test_printer': '测试打印机连接',
      'auto_print': '自动打印小票',
      'auto_print_desc': '订单提交后自动发送至打印机',
      'printer_success': '打印机连接测试成功',
      'printer_failed': '打印机连接测试失败',

      // Store hours
      'edit_hours': '编辑营业时间',
      'closed': '已打烊',
      'add_time_range': '添加营业时间段',

      // Days of Week
      'monday': '星期一',
      'tuesday': '星期二',
      'wednesday': '星期三',
      'thursday': '星期四',
      'friday': '星期五',
      'saturday': '星期六',
      'sunday': '星期日',

      // System / Logout
      'reset_settings': '重置为默认设置',
      'reset_confirm_title': '重置设置',
      'reset_confirm_msg': '确定要把所有设置恢复为初始默认值吗？',
      'logout': '退出登录',
      'logout_confirm_title': '退出登录',
      'logout_confirm_msg': '确定要退出当前账号登录吗？',

      // Order Page & Cart
      'dining_table': '桌台',
      'select_table': '选择桌台',
      'table_order': '堂食坐台',
      'table_reserved': '已预约',
      'table_occupied': '就座中',
      'table_available': '空闲',
      'import_preorder': '导入预点单',
      'submit_table_order': '开台下单',
      'append_items': '编辑菜品',
      'edit_items': '编辑菜品',
      'guest_count': '就餐人数',
      'reservation_info': '预约信息',
      'active_order_info': '当前坐台单',
      'refresh_tables': '刷新桌台',
      'order_cart_title': '已点菜品',
      'clear_cart': '清空',
      'checkout': '结账付款',
      'empty_cart_msg': '暂未选择任何菜品',
      'subtotal': '小计',
      'tax': '税费',
      'discount': '折扣',
      'total': '合计',
      'search_menu_hint': '搜索菜品...',
      'all_categories': '全部菜品',
      'quick_input': '快捷输入',

      // Order List Page & Detail Pages
      'order_list_title': '订单列表与管理',
      'order_detail': '订单详情',
      'server_order_detail': '服务器订单详情',
      'search_order_hint': '搜索订单号/顾客姓名...',
      'order_id': '订单号 #',
      'order_amount': '金额',
      'order_time': '时间',
      'order_status': '状态',
      'sync_status': '同步状态',
      'print_status': '打印状态',
      'status_pending': '待处理',
      'status_completed': '已完成',
      'status_cancelled': '已取消',
      'status_confirmed': '已确认',
      'reprint_ticket': '补打小票',
      'show_local_orders': '显示本地订单',
      'show_server_orders': '显示服务器订单',
      'local_orders': '本地订单',
      'server_orders': '服务器订单',
      'pull': '拉取',
      'resync': '重新同步',
      'reprint': '重新打印',
      'pull_all': '拉取服务器订单到本地',
      'no_orders': '暂无订单',
      'no_orders_sub': '下单后订单将在此显示',

      // Reports Page
      'report_title': '销售报表',
      'today_sales': '今日营业额',
      'total_orders': '总订单量',
      'average_order': '客单价',
      'sales_trend': '销售趋势',

      // Dialogs & Configurations
      'choose_order': '选择网络订单',
      'match_details': '订单核对详情',
      'matched': '数据匹配一致',
      'mismatched': '存在差异',
      'printer_config': '打印机设置',
      'server_config': '服务器配置',

      // Status Bar & Service Status
      'printer_status': '打印机',
      'server_status': '服务器',
      'connected': '已连接',
      'disconnected': '未连接',
      'check_status': '检查中...',

      // Admin Mode
      'admin_mode': '管理员模式',
      'enter_admin_pwd': '请输入管理员密码',
      'pwd_label': '密码',
      'invalid_pwd': '密码错误',
      'admin_mode_activated': '已进入管理模式',
      'change_pwd': '修改密码',
      'exit_admin': '退出管理模式',

      // Common Actions & Labels
      'cancel': '取消',
      'confirm': '确定',
      'ok': '好的',
      'reset': '重置',
      'status_running': '运行中',
      'status_stopped': '停止',
      'status_active': '活跃',
      'status_inactive': '未激活',
      'permission_request': '请求/刷新系统权限',
      'permission_triggered': '权限请求已触发',
      'edit': '修改',
      'save': '保存',
      'delete': '删除',
      'last_updated': '最后更新时间',
      'quantity': '数量',
      'price': '价格',
      'options': '规格',
      'note': '备注',
      'items': '商品明细',
      'customer': '顾客信息',
      'payment': '支付方式',
      'cash': '现金',
      'pos': 'POS 刷卡',
      'online': '线上网单',
      'terminal': '收银终端',
      'refund': '退款',
      'select_all': '全选',
      'search': '搜索',
      'back': '返回',
      'copy': '复制',
      'no_data': '暂无数据',
    },
  };

  String tr(String key) {
    final langMap = _localizedValues[_currentLanguage] ?? _localizedValues['en']!;
    return langMap[key] ?? key;
  }
}

extension StringTr on String {
  String get tr => LanguageService().tr(this);
}
