class MenuItem {
  final int id;
  final String code;
  final String title;
  final String? kitchenPrintName; // 后厨打印名称
  final String? acronym; // 可空类型
  final double sellingPrice;
  final int stock;
  final int sort;
  final List<int> categoryIds; // 分类IDs
  final bool isPrintable; // 是否需要打印到后厨
  final bool isSoldOut; // 是否沽清/售罄
  final String? soldOutUntil; // 沽清截止时间
  final String? soldOutLabel; // 自定义售罄标签 (如 "今日售罄", "Sold Out")
  final int splitGroupId; // 后厨分单ID (0表示不分单)

  MenuItem({
    required this.id,
    required this.code,
    required this.title,
    this.kitchenPrintName,
    required this.acronym,
    required this.sellingPrice,
    required this.stock,
    required this.sort,
    required this.categoryIds,
    required this.isPrintable,
    this.isSoldOut = false,
    this.soldOutUntil,
    this.soldOutLabel,
    this.splitGroupId = 0,
  });

  /// 格式化显示的售罄标签
  String get displaySoldOutLabel {
    if (soldOutLabel != null && soldOutLabel!.trim().isNotEmpty) {
      return soldOutLabel!.trim();
    }
    return 'SOLDOUT / 已售罄';
  }

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
      kitchenPrintName: json['kitchen_print_name'] as String?,
      acronym: json['acronym'] as String?,
      sellingPrice: double.tryParse(json['selling_price'].toString()) ?? 0.0,
      stock: json['stock'] ?? 0,
      sort: json['sort'] ?? 0,
      categoryIds: categoryIds,
      isPrintable: json['is_printable'] ?? true,
      isSoldOut: json['is_sold_out'] == true || json['is_sold_out'] == 1,
      soldOutUntil: json['sold_out_until'] as String?,
      soldOutLabel: json['sold_out_label'] as String?,
      splitGroupId: json['split_group_id'] as int? ?? json['splitGroupId'] as int? ?? 0,
    );
  }

  /// 复制并更新售罄状态与分单信息
  MenuItem copyWith({
    bool? isSoldOut,
    String? soldOutUntil,
    String? soldOutLabel,
    int? splitGroupId,
  }) {
    return MenuItem(
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
      isSoldOut: isSoldOut ?? this.isSoldOut,
      soldOutUntil: soldOutUntil ?? this.soldOutUntil,
      soldOutLabel: soldOutLabel ?? this.soldOutLabel,
      splitGroupId: splitGroupId ?? this.splitGroupId,
    );
  }
}
