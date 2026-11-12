class KitchenSplitGroup {
  final int id;
  final String name;
  final List<int> productIds;

  KitchenSplitGroup({
    required this.id,
    required this.name,
    required this.productIds,
  });

  factory KitchenSplitGroup.fromJson(Map<String, dynamic> json) {
    return KitchenSplitGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      productIds: (json['product_ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'product_ids': productIds,
    };
  }

  KitchenSplitGroup copyWith({
    int? id,
    String? name,
    List<int>? productIds,
  }) {
    return KitchenSplitGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      productIds: productIds ?? List.from(this.productIds),
    );
  }
}
