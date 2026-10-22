import 'package:flutter/material.dart';
import '../../common/models/menu_option.dart';

class OptionSelectionDialog {
  static Future<void> show({
    required BuildContext context,
    required String type,
    required List<MenuOption> options,
    required void Function(MenuOption) onOptionSelected,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('选择 $type', style: const TextStyle(fontSize: 16)),
          contentPadding: const EdgeInsets.all(16),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1.8,
              ),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () {
                      onOptionSelected(option);
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            option.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (option.extraCost > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                '+\$${option.extraCost.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }
}
