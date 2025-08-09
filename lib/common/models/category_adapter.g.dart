// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_adapter.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CategoryAdapterAdapter extends TypeAdapter<CategoryAdapter> {
  @override
  final int typeId = 2;

  @override
  CategoryAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CategoryAdapter(
      id: fields[0] as int,
      parentId: fields[1] as int?,
      title: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, CategoryAdapter obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.parentId)
      ..writeByte(2)
      ..write(obj.title);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
