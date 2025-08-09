// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_option_adapter.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MenuOptionAdapterAdapter extends TypeAdapter<MenuOptionAdapter> {
  @override
  final int typeId = 3;

  @override
  MenuOptionAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuOptionAdapter(
      id: fields[0] as int,
      name: fields[1] as String,
      type: fields[2] as String,
      extraCost: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, MenuOptionAdapter obj) {
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
      other is MenuOptionAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
