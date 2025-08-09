import 'package:hive/hive.dart';
import 'menu_option.dart';

part 'option_groups_adapter.g.dart';

@HiveType(typeId: 4)
class OptionGroupsAdapter extends HiveObject {
  @HiveField(0)
  Map<String, List<MenuOption>> groups;

  OptionGroupsAdapter({required this.groups});
}
