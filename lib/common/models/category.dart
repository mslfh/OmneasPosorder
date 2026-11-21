class Category {
  final int id;
  final int? parentId;
  final String title;

  Category({
    required this.id,
    this.parentId,
    required this.title,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    int? parseParentId(dynamic val) {
      if (val == null) return null;
      if (val is int) return val == 0 ? null : val;
      if (val is String) {
        final parsed = int.tryParse(val);
        return (parsed == 0) ? null : parsed;
      }
      return null;
    }

    return Category(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '') ?? 0),
      parentId: parseParentId(json['parent_id']),
      title: json['title']?.toString() ?? '',
    );
  }
}
