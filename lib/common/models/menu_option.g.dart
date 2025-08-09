// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_option.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MenuOptionAdapter extends TypeAdapter<MenuOption> {
  @override
  final int typeId = 5;

  @override
  MenuOption read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuOption(
      id: fields[0] as int,
      name: fields[1] as String,
      type: fields[2] as String,
      extraCost: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, MenuOption obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.extraCost);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuOptionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
