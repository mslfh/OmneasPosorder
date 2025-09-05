import 'package:hive/hive.dart';
import 'menu_item.dart';

part 'menu_item_adapter.g.dart';

@HiveType(typeId: 1)
class MenuItemAdapter extends HiveObject {
  @HiveField(0)
  int id;
  @HiveField(1)
  String code;
  @HiveField(2)
  String title;
  @HiveField(3)
  String? acronym; // 改为可空类型
  @HiveField(4)
  double sellingPrice;
  @HiveField(5)
  int stock;
  @HiveField(6)
  int sort;
  @HiveField(7)
  List<int> categoryIds; // 新增字段

  MenuItemAdapter({
    required this.id,
    required this.code,
    required this.title,
    required this.acronym, // 可空类型
    required this.sellingPrice,
    required this.stock,
    required this.sort,
    required this.categoryIds, // 新增字段
  });

  factory MenuItemAdapter.fromMenuItem(MenuItem item) => MenuItemAdapter(
    id: item.id,
    code: item.code,
    title: item.title,
    acronym: item.acronym, // 可空类型
    sellingPrice: item.sellingPrice,
    stock: item.stock,
    sort: item.sort,
    categoryIds: item.categoryIds, // 新增字段
  );

  MenuItem toMenuItem() => MenuItem(
    id: id,
    code: code,
    title: title,
    acronym: acronym, // 可空类型
    sellingPrice: sellingPrice,
    stock: stock,
    sort: sort,
    categoryIds: categoryIds, // 新增字段
  );
}
