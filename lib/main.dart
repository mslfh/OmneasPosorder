import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'common/models/menu_item_adapter.dart';
import 'common/models/category_adapter.dart';
import 'common/models/menu_option_adapter.dart';
import 'common/models/option_groups_adapter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(MenuItemAdapterAdapter());
  Hive.registerAdapter(CategoryAdapterAdapter());
  Hive.registerAdapter(MenuOptionAdapterAdapter());
  Hive.registerAdapter(OptionGroupsAdapterAdapter());
  runApp(const OmneasApp());
}
