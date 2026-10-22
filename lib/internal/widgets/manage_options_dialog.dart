import 'package:flutter/material.dart';
import '../../common/models/menu_option.dart';
import '../../common/services/api_service.dart';
import '../utils/ui_helper.dart';

class ManageOptionsDialog {
  static Future<void> show({
    required BuildContext context,
    required Map<String, List<MenuOption>> optionGroups,
    required VoidCallback onOptionsUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('管理菜品选项'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...optionGroups.entries.map((entry) {
                  final groupType = entry.key;
                  final options = entry.value;
                  return ExpansionTile(
                    title: Text(groupType),
                    children: [
                      ...options.map((option) => ListTile(
                            title: Text(option.name),
                            subtitle: Text(
                                '额外费用: \$${option.extraCost.toStringAsFixed(2)}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditOptionDialog(
                                    context: context,
                                    option: option,
                                    groupType: groupType,
                                    onOptionsUpdated: onOptionsUpdated,
                                  );
                                } else if (value == 'delete') {
                                  _showDeleteOptionDialog(
                                    context: context,
                                    option: option,
                                    groupType: groupType,
                                    onOptionsUpdated: onOptionsUpdated,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('编辑'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          )),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('添加选项'),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showAddOptionDialog(
                            context: context,
                            groupType: groupType,
                            onOptionsUpdated: onOptionsUpdated,
                          );
                        },
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _showAddOptionGroupDialog(
                      context: context,
                      onOptionsUpdated: onOptionsUpdated,
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新增选项组'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showAddOptionDialog({
    required BuildContext context,
    required String groupType,
    required VoidCallback onOptionsUpdated,
  }) {
    final nameController = TextEditingController();
    final costController = TextEditingController(text: '0');

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('添加选项 - $groupType'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '选项名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: const InputDecoration(
                labelText: '额外费用',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text) ?? 0;
              try {
                final api = ApiService();
                await api.post('attributes', data: {
                  'type': groupType,
                  'name': nameController.text,
                  'extra_cost': cost,
                });

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                onOptionsUpdated();

                UIHelper.showSnackBar(context, '选项已添加',
                    backgroundColor: Colors.green);
              } catch (e) {
                if (!dialogContext.mounted) return;
                UIHelper.showSnackBar(context, '添加失败: $e',
                    backgroundColor: Colors.red);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showEditOptionDialog({
    required BuildContext context,
    required MenuOption option,
    required String groupType,
    required VoidCallback onOptionsUpdated,
  }) {
    final nameController = TextEditingController(text: option.name);
    final costController =
        TextEditingController(text: option.extraCost.toString());

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑选项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '选项名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costController,
              decoration: const InputDecoration(
                labelText: '额外费用',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text) ?? 0;
              try {
                final api = ApiService();
                await api.put('attributes/${option.id}', data: {
                  'name': nameController.text,
                  'extra_cost': cost,
                });

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                onOptionsUpdated();

                UIHelper.showSnackBar(context, '选项已更新',
                    backgroundColor: Colors.green);
              } catch (e) {
                if (!dialogContext.mounted) return;
                UIHelper.showSnackBar(context, '更新失败: $e',
                    backgroundColor: Colors.red);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showDeleteOptionDialog({
    required BuildContext context,
    required MenuOption option,
    required String groupType,
    required VoidCallback onOptionsUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除选项'),
        content: Text('确认要删除选项 "${option.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final api = ApiService();
                await api.delete('attributes/${option.id}');

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                onOptionsUpdated();

                UIHelper.showSnackBar(context, '选项已删除',
                    backgroundColor: Colors.green);
              } catch (e) {
                if (!dialogContext.mounted) return;
                UIHelper.showSnackBar(context, '删除失败: $e',
                    backgroundColor: Colors.red);
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showAddOptionGroupDialog({
    required BuildContext context,
    required VoidCallback onOptionsUpdated,
  }) {
    final groupNameController = TextEditingController();

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新增选项组'),
        content: TextField(
          controller: groupNameController,
          decoration: const InputDecoration(
            labelText: '选项组名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (groupNameController.text.isEmpty) {
                UIHelper.showSnackBar(context, '请输入选项组名称',
                    backgroundColor: Colors.orange);
                return;
              }

              try {
                final api = ApiService();
                await api.post('attributes', data: {
                  'type': groupNameController.text,
                  'name': '新选项',
                  'extra_cost': 0,
                });

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                onOptionsUpdated();

                UIHelper.showSnackBar(context, '选项组已创建',
                    backgroundColor: Colors.green);
              } catch (e) {
                if (!dialogContext.mounted) return;
                UIHelper.showSnackBar(context, '创建失败: $e',
                    backgroundColor: Colors.red);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
