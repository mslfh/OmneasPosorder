// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'option_groups_adapter.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OptionGroupsAdapterAdapter extends TypeAdapter<OptionGroupsAdapter> {
  @override
  final int typeId = 4;

  @override
  OptionGroupsAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OptionGroupsAdapter(
      groups: (fields[0] as Map).map((dynamic k, dynamic v) =>
          MapEntry(k as String, (v as List).cast<MenuOption>())),
    );
  }

  @override
  void write(BinaryWriter writer, OptionGroupsAdapter obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.groups);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OptionGroupsAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
