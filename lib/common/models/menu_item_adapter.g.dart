// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_item_adapter.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MenuItemAdapterAdapter extends TypeAdapter<MenuItemAdapter> {
  @override
  final int typeId = 1;

  @override
  MenuItemAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MenuItemAdapter(
      id: fields[0] as int,
      code: fields[1] as String,
      title: fields[2] as String,
      acronym: fields[3] as String,
      sellingPrice: fields[4] as double,
      stock: fields[5] as int,
      sort: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, MenuItemAdapter obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.acronym)
      ..writeByte(4)
      ..write(obj.sellingPrice)
      ..writeByte(5)
      ..write(obj.stock)
      ..writeByte(6)
      ..write(obj.sort);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MenuItemAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
