import 'package:hive/hive.dart';
import 'category.dart';

part 'category_adapter.g.dart';

@HiveType(typeId: 2)
class CategoryAdapter extends HiveObject {
  @HiveField(0)
  int id;
  @HiveField(1)
  int? parentId;
  @HiveField(2)
  String title;

  CategoryAdapter({
    required this.id,
    this.parentId,
    required this.title,
  });

  factory CategoryAdapter.fromCategory(Category cat) => CategoryAdapter(
    id: cat.id,
    parentId: cat.parentId,
    title: cat.title,
  );

  Category toCategory() => Category(
    id: id,
    parentId: parentId,
    title: title,
  );
}

