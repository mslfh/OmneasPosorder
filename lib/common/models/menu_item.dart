class MenuItem {
  final int id;
  final String code;
  final String title;
  final String? acronym; // 改为可空类型
  final double sellingPrice;
  final int stock;
  final int sort;
  final List<int> categoryIds; // 新增字段
  final bool isPrintable; // 是否需要打印到后厨

  MenuItem({
    required this.id,
    required this.code,
    required this.title,
    required this.acronym, // 可空类型
    required this.sellingPrice,
    required this.stock,
    required this.sort,
    required this.categoryIds, // 新增字段
    required this.isPrintable,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    List<int> categoryIds = [];
    final categories = json['categories'];
    if (categories is List) {
      categoryIds = categories
        .where((cat) => cat is Map && cat.containsKey('id'))
        .map((cat) => cat['id'] as int)
        .toList();
    } else {
      categoryIds = [];
    }
    return MenuItem(
      id: json['id'],
      code: json['code'],
      title: json['title'],
      acronym: json['acronym'] as String?, // 兼容null
      sellingPrice: double.tryParse(json['selling_price'].toString()) ?? 0.0,
      stock: json['stock'],
      sort: json['sort'],
      categoryIds: categoryIds,
      isPrintable: json['is_printable'],
    );
  }
}
