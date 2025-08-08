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
    return Category(
      id: json['id'],
      parentId: json['parent_id'],
      title: json['title'],
    );
  }
}
