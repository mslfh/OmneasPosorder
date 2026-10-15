class MenuItemLayoutConfig {
  final int menuItemId;
  final int col;
  final int row;
  final int spanX;
  final int spanY;

  const MenuItemLayoutConfig({
    required this.menuItemId,
    required this.col,
    required this.row,
    this.spanX = 2,
    this.spanY = 2,
  });

  MenuItemLayoutConfig copyWith({
    int? menuItemId,
    int? col,
    int? row,
    int? spanX,
    int? spanY,
  }) {
    return MenuItemLayoutConfig(
      menuItemId: menuItemId ?? this.menuItemId,
      col: col ?? this.col,
      row: row ?? this.row,
      spanX: spanX ?? this.spanX,
      spanY: spanY ?? this.spanY,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'menuItemId': menuItemId,
      'col': col,
      'row': row,
      'spanX': spanX,
      'spanY': spanY,
    };
  }

  factory MenuItemLayoutConfig.fromJson(Map<String, dynamic> json) {
    return MenuItemLayoutConfig(
      menuItemId: json['menuItemId'] as int,
      col: json['col'] as int,
      row: json['row'] as int,
      spanX: json['spanX'] as int? ?? 2,
      spanY: json['spanY'] as int? ?? 2,
    );
  }
}
