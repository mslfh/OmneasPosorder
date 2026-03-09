# Admin Mode - 实现完成说明文档

## 功能概述

已成功实现了一套完整的管理员模式系统，允许管理员通过验证密码进入特殊操作模式，从而对菜品和选项进行管理。

## 已实现的功能

### 1. 管理员模式激活

#### 触发条件
- 在5秒内快速点击appBar中的"Omneas POS"文字**5次**
- 会自动弹出密码验证对话框

#### 密码验证
- **默认密码**: `12345abc`
- 密码保存在本地Hive数据库 (`authBox` 下的 `adminPassword` 键)
- 首次启动时自动使用默认密码

#### 进入管理模式
验证成功后：
- appBar会显示两个新按钮：
  - **Change Password** (橙色) - 修改管理员密码
  - **Exit Admin** (红色) - 退出管理模式
- OrderPage 会进入管理模式 (`_isAdminMode = true`)

### 2. 菜品管理

#### 编辑菜品
在管理模式下，对菜品进行**长按**操作即可打开编辑对话框：
- 可编辑字段：
  - **菜品代码** (code)
  - **菜品名称** (title)
  - **快捷键** (acronym)
  - **售价** (sellingPrice)
  - **库存** (stock)
  - **分类** (categoryIds)

编辑完成后点击"保存"按钮，会调用后端API进行更新：
```
PUT /products/{productId}
```

### 3. 菜品选项管理

#### 访问选项管理
在管理模式下，Options面板会显示"Manage"按钮，点击即可打开选项管理界面

#### 支持的操作
1. **查看选项组** - 按类型分组展示所有选项
2. **编辑选项** - 修改选项名称和额外费用
3. **删除选项** - 删除指定的选项
4. **添加选项** - 为指定的选项组添加新选项
5. **新增选项组** - 创建全新的选项组

#### 相关API调用
- `POST /attributes` - 添加新选项
- `PUT /attributes/{attributeId}` - 编辑选项
- `DELETE /attributes/{attributeId}` - 删除选项

### 4. 密码管理

#### 修改密码
点击appBar的"Change Password"按钮：
1. 输入当前密码进行身份验证
2. 输入新密码
3. 确认新密码
4. 点击"修改"按钮

验证通过后新密码会保存到本地Hive数据库

#### 密码验证
- 旧密码验证失败会显示错误提示
- 新密码和确认密码不一致也会显示错误提示

### 5. 退出管理模式

#### 方式1 - 手动退出
点击appBar的"Exit Admin"按钮，确认后退出管理模式

#### 方式2 - 自动退出
重启应用会自动退出管理模式（管理模式是一次性的）

## 核心实现文件

### 新增文件

#### 1. `lib/common/services/admin_password_service.dart`
管理员密码服务类，提供：
- `getAdminPassword()` - 获取管理员密码
- `verifyPassword()` - 验证密码
- `changePassword()` - 修改密码
- `resetToDefault()` - 重置为默认密码

### 修改文件

#### 1. `lib/internal/internal_app.dart`
- 添加了管理员模式状态变量：
  - `_isAdminMode` - 管理模式标志
  - `_titleTapCount` - 标题点击计数
  - `_lastTitleTapTime` - 上次点击时间

- 添加了方法：
  - `_onTitleTap()` - 处理标题点击并检测5次快速点击
  - `_showAdminPasswordDialog()` - 显示密码验证对话框
  - `_showChangePasswordDialog()` - 显示修改密码对话框
  - `_exitAdminMode()` - 退出管理模式

- 更新了build方法，传递管理模式状态给OrderPage

#### 2. `lib/internal/pages/order_page.dart`
- 添加了`isAdminMode`参数到OrderPage widget
- 添加了`_isAdminMode`状态变量
- 添加了`didUpdateWidget`方法以响应管理模式变化

- 添加了菜品编辑方法：
  - `_showEditProductDialog()` - 显示编辑菜品对话框

- 添加了选项管理方法：
  - `_showManageOptionsDialog()` - 显示选项管理界面
  - `_showAddOptionDialog()` - 添加新选项
  - `_showEditOptionDialog()` - 编辑现有选项
  - `_showDeleteOptionDialog()` - 删除选项
  - `_showAddOptionGroupDialog()` - 创建新选项组

- 更新MenuGridWidget调用，传递管理模式参数和长按回调

#### 3. `lib/internal/widgets/menu_grid_widget.dart`
- 添加了`isAdminMode`参数
- 添加了`onLongPress`回调
- 添加了`onReorderStart`回调（预留用于拖拖-排序功能）
- 在GestureDetector中添加了`onLongPress`事件处理

#### 4. `lib/internal/widgets/menu_option_panel_widget.dart`
- 添加了`isAdminMode`参数
- 添加了`onManageOptions`回调
- 在Options面板标题栏添加了"Manage"按钮（仅在管理模式下显示）

## 数据流

```
用户5次快速点击标题
    ↓
_onTitleTap() 检测到5次点击
    ↓
_showAdminPasswordDialog() 弹出密码对话框
    ↓
AdminPasswordService.verifyPassword() 验证密码
    ↓
密码正确 → setState(_isAdminMode = true)
密码错误 → 显示错误提示

---

在管理模式下长按菜品
    ↓
_showEditProductDialog(MenuItem) 打开编辑对话框
    ↓
用户编辑菜品信息
    ↓
点击"保存"
    ↓
API调用: PUT /products/{id}
    ↓
loadData() 刷新数据
    ↓
显示成功提示

---

在管理模式下点击"Manage"按钮
    ↓
_showManageOptionsDialog() 打开选项管理界面
    ↓
用户选择编辑/删除选项或添加新选项
    ↓
API调用相应的操作
    ↓
fetchOptions() 刷新选项数据
    ↓
显示成功或失败提示
```

## API 交互

### 菜品编辑API
```
PUT /products/{productId}

请求体:
{
  "code": "菜品代码",
  "title": "菜品名称",
  "acronym": "快捷键",
  "sellingPrice": 价格,
  "stock": 库存,
  "categoryIds": [分类ID列表]
}
```

### 选项操作API
```
POST /attributes - 添加选项
{
  "type": "选项组类型",
  "name": "选项名称",
  "extraCost": 额外费用
}

PUT /attributes/{attributeId} - 编辑选项
{
  "name": "新名称",
  "extraCost": 新费用
}

DELETE /attributes/{attributeId} - 删除选项
```

## 本地存储

管理员密码存储在Hive数据库中：
- **Box名**: `authBox`
- **Key**: `adminPassword`
- **默认值**: `12345abc`

## 使用流程

### 首次进入管理模式
1. 快速点击appBar标题5次（需在5秒内完成）
2. 弹出密码对话框
3. 输入默认密码 `12345abc`
4. 点击"验证"按钮
5. 成功进入管理模式

### 修改管理密码
1. 点击appBar的"Change Password"按钮
2. 输入当前密码
3. 输入新密码
4. 确认新密码
5. 点击"修改"按钮

### 编辑菜品
1. 在菜品网格中**长按**要编辑的菜品
2. 编辑对话框会打开
3. 修改所需信息
4. 点击"保存"提交修改

### 管理菜品选项
1. 在Options面板点击"Manage"按钮
2. 选项管理界面会打开
3. 根据需要：
   - 点击选项进行编辑/删除
   - 在选项组下添加新选项
   - 创建新的选项组

### 退出管理模式
- **方式1**: 点击appBar的"Exit Admin"按钮
- **方式2**: 重启应用

## 注意事项

1. **管理模式是一次性的** - 退出后需要重新输入密码才能再次进入
2. **密码修改后生效** - 下次进入管理模式需要用新密码
3. **长按编辑** - 普通点击仍然是添加菜品，长按才是编辑
4. **库存格式** - 必须是整数，不能为空
5. **价格格式** - 支持小数点，如 10.50
6. **分类选择** - 下拉列表显示所有可用的分类

## 后续可实现的功能

根据API文档，以下功能可在后续版本中实现：

1. **菜品拖拽排序** - 长按拖动菜品改变sort值
   - 相应API: `PATCH /products/sort`

2. **菜品删除** - 管理模式下删除菜品
   - 相应API: `DELETE /products/{id}`

3. **菜品批量操作** - 同时修改多个菜品的信息

4. **分类管理** - 新增/编辑/删除分类

5. **菜品导入导出** - 批量导入或导出菜品数据

## 故障排除

### 问题：密码验证失败
- 检查是否输入了正确的密码
- 如果遗忘密码，可以卸载应用重新安装（会重置为默认密码）

### 问题：编辑菜品后未生效
- 检查网络连接
- 检查API服务器是否正常
- 查看错误提示信息了解具体原因

### 问题：选项管理打不开
- 确认已进入管理模式
- 检查Options面板是否有"Manage"按钮
- 尝试关闭并重新打开应用


