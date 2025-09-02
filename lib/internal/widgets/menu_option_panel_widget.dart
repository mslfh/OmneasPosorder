import 'package:flutter/material.dart';
import '../../common/models/menu_option.dart';
import '../utils/order_selected.dart';

class MenuOptionPanelWidget extends StatelessWidget {
  final Map<String, List<MenuOption>> optionGroups;
  final List<SelectedProduct> orderedProducts;
  final void Function(String type) onOptionTap;

  const MenuOptionPanelWidget({
    Key? key,
    required this.optionGroups,
    required this.orderedProducts,
    required this.onOptionTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (optionGroups.isEmpty) {
      return SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[100]!, Colors.grey[200]!],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[300]!, Colors.blue[400]!],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'Options',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.all(2),
              child: ListView(
                children: optionGroups.keys.map((type) {
                  final options = optionGroups[type]!;
                  return Container(
                    margin: EdgeInsets.only(bottom: 1),
                    child: ElevatedButton(
                      onPressed: orderedProducts.isEmpty ? null : () => onOptionTap(type),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue[800],
                        elevation: 1,
                        shadowColor: Colors.blue[100],
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.blue[200]!),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.tune, size: 16, color: Colors.blue[400]),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              type,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          Text('(${options.length})', style: TextStyle(fontSize: 11, color: Colors.blue[300])),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
