class MenuItem {
  final int id;
  final String code;
  final String title;
  final String acronym;
  final double sellingPrice;
  final int stock;
  final int sort;

  MenuItem({
    required this.id,
    required this.code,
    required this.title,
    required this.acronym,
    required this.sellingPrice,
    required this.stock,
    required this.sort,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'],
      code: json['code'],
      title: json['title'],
      acronym: json['acronym'],
      sellingPrice: double.tryParse(json['selling_price'].toString()) ?? 0.0,
      stock: json['stock'],
      sort: json['sort'],
    );
  }
}

