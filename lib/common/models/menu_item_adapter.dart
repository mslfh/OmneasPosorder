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
  String acronym;
  @HiveField(4)
  double sellingPrice;
  @HiveField(5)
  int stock;
  @HiveField(6)
  int sort;

  MenuItemAdapter({
    required this.id,
    required this.code,
    required this.title,
    required this.acronym,
    required this.sellingPrice,
    required this.stock,
    required this.sort,
  });

  factory MenuItemAdapter.fromMenuItem(MenuItem item) => MenuItemAdapter(
    id: item.id,
    code: item.code,
    title: item.title,
    acronym: item.acronym,
    sellingPrice: item.sellingPrice,
    stock: item.stock,
    sort: item.sort,
  );

  MenuItem toMenuItem() => MenuItem(
    id: id,
    code: code,
    title: title,
    acronym: acronym,
    sellingPrice: sellingPrice,
    stock: stock,
    sort: sort,
  );
}

