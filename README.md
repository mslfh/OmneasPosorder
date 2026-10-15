# Omneas POS Order - 项目开发与架构指南 (AI Prompt Friendly README)

面向餐饮、咖啡厅与小型零售店的跨平台离线优先（Offline-First）POS 点餐与订单管理系统。本文档旨在为 AI 助手与开发人员提供清晰的系统架构、项目结构、开发规范与功能扩展指南。

---

## 📌 1. 项目简介与架构概述 (Overview)

`Omneas POS Order` (omneas_posorder) 是一套高性能、支持物理快捷键点餐的 POS 终端。系统具备完整的离线可用性、网络恢复后后台自动同步、ESC/POS 票据双联打印、以及与服务器数据的实时比对校验。

### 核心设计原则
1. **离线优先 (Offline-First)**：本地开单数据实时保存至 SQLite，网络恢复后由 `SyncService` 异步提交至后端 RESTful API。
2. **读写分离与双层存储**：
   - **SQLite (`DatabaseService`)**：存储订单、日志、系统配置等强一致性事务数据。
   - **Hive**：高效缓存菜品（Products）、分类（Categories）、选项组（Option Groups）。
3. **单一职责与低耦合 (SoC & Low Coupling)**：UI 视图（Widgets/Pages）、业务管理者（Managers）、底层服务（Services）严格分离。
4. **模块化快捷键引擎**：基于策略模式（Strategy Pattern）解耦收银快捷键（数字键、导航键、操作键）。

---

## 📁 2. 项目目录结构 (Directory Structure)

```text
lib/
├── config/                  # 配置文件（预设环境变量 fallback）
│   └── env.dart
├── common/                  # 全局跨模块公共层
│   ├── models/              # 数据模型（OrderModel, MenuItem, Category, AppSettings 等）
│   ├── services/            # 核心业务与底层服务
│   │   ├── api_service.dart               # Dio 网络请求基类（单例、统一 BaseURL/Header/错误处理）
│   │   ├── settings_service.dart          # 全局配置与持久化服务（SQLite + Hive 迁移）
│   │   ├── database_service.dart          # SQLite 数据库核心服务
│   │   ├── order_service.dart             # 本地与远程订单处理逻辑
│   │   ├── sync_service.dart              # 后台订单与配置同步服务
│   │   ├── print_service.dart             # ESC/POS 小票打印与队列重试服务
│   │   ├── order_match_service.dart       # 本地与服务器订单比对核对服务
│   │   ├── background_task_manager.dart   # 跨平台后台任务管理器
│   │   ├── language_service.dart          # 全局多语言管理服务（默认英文，支持中英文即时切换）
│   │   └── cache_service.dart             # 本地缓存清理与管理服务
│   └── utils/               # 全局映射与工具类（OrderItemMapper 等）
├── internal/                # POS 服务员端/收银端核心业务
│   ├── internal_app.dart    # POS 界面主入口与路由
│   ├── keyboard_handlers/   # 模块化键盘快捷键处理器（按键策略模式）
│   │   ├── action_key_handler.dart
│   │   ├── digit_key_handler.dart
│   │   ├── enter_key_handler.dart
│   │   └── navigation_key_handler.dart
│   ├── pages/               # POS 核心页面
│   │   ├── order_page.dart                # 点餐主页面
│   │   ├── checkout_page.dart             # 结账付款页面
│   │   ├── order_list_page.dart           # 订单列表与补打页面
│   │   ├── report_page.dart               # 销售报表页面
│   │   └── settings_page.dart             # 系统设置页面
│   ├── services/            # POS 状态与业务管理器
│   │   ├── menu_data_service.dart         # 菜品与选项加载、API全量数据同步
│   │   ├── order_match_manager.dart       # 订单匹配定时器与检查状态管理
│   │   ├── ordered_product_manager.dart   # 已点菜品（加/减/删/复制）逻辑管理
│   │   ├── product_addition_manager.dart  # 菜品添加与选项组组合管理器
│   │   └── admin_dialog_manager.dart      # 管理员模式菜品/选项编辑对话框管理
│   ├── widgets/             # 可复用 UI 视图组件
│   │   ├── menu_grid_widget.dart          # 菜品网格展示组件
│   │   ├── category_sidebar_widget.dart   # 分类侧边栏组件
│   │   ├── ordered_product_list_widget.dart # 已点菜品列表组件
│   │   ├── order_match_ui_builder.dart    # 订单匹配 UI 卡片与标头构建器
│   │   └── service_status_actions.dart    # 顶部打印机/服务器连接状态组件
│   └── utils/               # POS 辅助工具类（KeyboardEventHandler, QuickInputManager 等）
├── customer/                # 预留：顾客端 / 客显屏扩展模块
│   └── customer_app.dart
├── app.dart                 # Flutter OmneasApp 全局入口
└── main.dart                # 系统 main 启动入口（初始化 Hive, DB, 菜品数据同步）
```

---

## 🛠️ 3. 代码开发规范与标准 (Development Standards)

在生成或修改代码时，请严格遵守以下开发标准：

### 3.1 命名与类型规范
- **类名**：使用 `PascalCase` 大驼峰命名（如 `MenuDataService`, `OrderMatchResult`）。
- **变量与方法**：使用 `camelCase` 小驼峰命名（如 `loadMenuData()`, `orderMatchResult`）。
- **枚举定义**：全小写 `camelCase` 成员（如 `OrderStatus.pending`, `SyncStatus.synced`）。
- **禁止隐式 Dynamic**：所有方法的形参、返回值必须使用明确的数据类型（例：使用 `List<SelectedProduct> products` 而非未标注类型的参数）。

### 3.2 架构分层与隔离规范 (Separation of Concerns)
1. **Service 层纯洁性**：`services/` 目录下的业务逻辑服务类**禁止**包含任何 Flutter UI 控件构建代码（如 `Widget`, `BuildContext`）。UI 渲染逻辑必须存放在 `widgets/` 目录中。
2. **统一网络与配置处理**：
   - 所有 HTTP 请求必须使用 `ApiService()` 单例发送，禁止直接在页面或组件中实例化 `Dio()`。
   - 请求 relative path 统一不带前缀斜杠（如：`api.get('products/active')`）。
   - API 服务器基地址通过 `SettingsService` 统一配置和持久化，严禁直接硬编码覆盖 `Env.apiBaseUrl`。
3. **日志与异常处理**：
   - 生产代码中使用 `Logger` 进行日志输出（`_logger.i(...)`, `_logger.e(...)`），避免使用未封装的原生 `print()`。
   - 数据库与网络异常必须进行捕获并写入日志，禁止向上层传播未处理的崩溃异常。

---

## ⚡ 4. 核心功能扩展指南 (How to Extend Features)

### 4.1 新增快捷键处理策略 (Keyboard Handler)
1. 在 `lib/internal/keyboard_handlers/` 下创建新的 Handler 类。
2. 继承或参照现有 Handler，编写对应按键事件的处理逻辑。
3. 在 `lib/internal/utils/keyboard_event_handler.dart` 中注册并路由该 Handle 即可。

### 4.2 新增 API 接口与数据模型
1. 在 `lib/common/models/` 下新建模型文件，提供 `fromJson()`、`toJson()` / `toMap()` 方法。
2. 若涉及 Hive 本地缓存，定义对应的 Hive Adapter 并执行 `build_runner` 绑定。
3. 在 `ApiService` 或对应的 Service 类中封装请求逻辑。

### 4.3 新增硬件/打印机协议 (Printer Adaption)
1. 当前网络打印通过 `PrintService._sendToNetworkPrinter()` 发送 ESC/POS 字节流。
2. 如需扩展 USB、蓝牙或串口打印机，可抽象 `PrinterAdapter` 接口（声明 `sendBytes(List<int> bytes)` 方法），并由 `PrintService` 根据设置路由至对应适配器。

### 4.4 扩展管理员模式 (Admin Mode Extension)
1. 管理员入口触发位于 `OrderPage` AppBar 连续点击 5 次，密码本地校验。
2. 菜品/选项等增删改对话框由 `AdminDialogManager` 统一调度，后端交互遵循 RESTful 风格。
3. 变更生效后调用 `CacheService.clearMenuCaches()` 清理本地 Hive 缓存以同步最新数据。

### 4.5 语言切换与多语言扩展 (Localization & Language Switching)
1. **架构设计**：
   - 采用集中式 `LanguageService` 单例服务配合 `ValueNotifier<Locale>` 监听机制，默认语言为英文（`'en'`）。
   - 用户所选语言持久化保存在 `AppSettings` 中（存储于 SQLite / Hive）。
   - 根组件 `OmneasApp` 在 `app.dart` 中通过 `ValueListenableBuilder` 监听 `LanguageService().localeNotifier`，语言切换时无缝重构整顶 Widget 树。
2. **开发规范**：
   - 所有 Widget UI 界面文本**禁止硬编码**，统一通过 `'key'.tr` 或 `LanguageService().tr('key')` 调用。
3. **新增多语言词条**：
   - 在 `lib/common/services/language_service.dart` 中的 `_localizedValues` 字典内，分别为 `'en'` 与 `'zh'` 键下补全词汇。
   - UI 控件中直接编写 `'new_key'.tr` 即可使用。

---

## 🚀 5. 项目构建与运行 (Getting Started)

1. **安装依赖**：
   ```bash
   flutter pub get
   ```
2. **生成 Hive Adapters（修改 Hive 模型后执行）**：
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
3. **启动应用**：
   ```bash
   flutter run
   ```
