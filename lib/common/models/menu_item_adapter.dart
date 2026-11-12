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
  String? acronym; // 可空类型
  @HiveField(4)
  double sellingPrice;
  @HiveField(5)
  int stock;
  @HiveField(6)
  int sort;
  @HiveField(7)
  List<int> categoryIds; // 分类IDs
  @HiveField(8)
  bool isPrintable; // 是否需要打印到后厨
  @HiveField(9)
  String? kitchenPrintName; // 后厨打印名称
  @HiveField(10)
  bool isSoldOut; // 是否沽清
  @HiveField(11)
  String? soldOutUntil; // 沽清截止时间
  @HiveField(12)
  String? soldOutLabel; // 售罄自定义标签
  @HiveField(13)
  int splitGroupId; // 后厨分单ID

  MenuItemAdapter({
    required this.id,
    required this.code,
    required this.title,
    required this.acronym,
    required this.sellingPrice,
    required this.stock,
    required this.sort,
    required this.categoryIds,
    required this.isPrintable,
    this.kitchenPrintName,
    this.isSoldOut = false,
    this.soldOutUntil,
    this.soldOutLabel,
    this.splitGroupId = 0,
  });

  factory MenuItemAdapter.fromMenuItem(MenuItem item) => MenuItemAdapter(
    id: item.id,
    code: item.code,
    title: item.title,
    acronym: item.acronym,
    sellingPrice: item.sellingPrice,
    stock: item.stock,
    sort: item.sort,
    categoryIds: item.categoryIds,
    isPrintable: item.isPrintable,
    kitchenPrintName: item.kitchenPrintName,
    isSoldOut: item.isSoldOut,
    soldOutUntil: item.soldOutUntil,
    soldOutLabel: item.soldOutLabel,
    splitGroupId: item.splitGroupId,
  );

  MenuItem toMenuItem() => MenuItem(
    id: id,
    code: code,
    title: title,
    kitchenPrintName: kitchenPrintName,
    acronym: acronym,
    sellingPrice: sellingPrice,
    stock: stock,
    sort: sort,
    categoryIds: categoryIds,
    isPrintable: isPrintable,
    isSoldOut: isSoldOut,
    soldOutUntil: soldOutUntil,
    soldOutLabel: soldOutLabel,
    splitGroupId: splitGroupId,
  );
}
