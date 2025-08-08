class MenuOption {
  final int id;
  final String name;
  final String type;
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

