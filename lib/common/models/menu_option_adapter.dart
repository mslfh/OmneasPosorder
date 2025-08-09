import 'package:hive/hive.dart';
import 'menu_option.dart';

part 'menu_option_adapter.g.dart';

@HiveType(typeId: 3)
class MenuOptionAdapter extends HiveObject {
  @HiveField(0)
  int id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String type;
  @HiveField(3)
  double extraCost;

  MenuOptionAdapter({
    required this.id,
    required this.name,
    required this.type,
    required this.extraCost,
  });

  factory MenuOptionAdapter.fromMenuOption(MenuOption option) => MenuOptionAdapter(
    id: option.id,
    name: option.name,
    type: option.type,
    extraCost: option.extraCost,
  );

  MenuOption toMenuOption() => MenuOption(
    id: id,
    name: name,
    type: type,
    extraCost: extraCost,
  );
}

