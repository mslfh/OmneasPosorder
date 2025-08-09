import 'package:hive/hive.dart';

part 'menu_option.g.dart';

@HiveType(typeId: 5)
class MenuOption {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String type;
  @HiveField(3)
  final double extraCost;

  MenuOption({
    required this.id,
    required this.name,
    required this.type,
    required this.extraCost,
  });

  factory MenuOption.fromJson(Map<String, dynamic> json) {
    return MenuOption(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      extraCost: double.tryParse(json['extra_cost'].toString()) ?? 0.0,
    );
  }
}
