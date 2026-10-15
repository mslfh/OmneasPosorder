
class StoreHoursConfig {
  final WeeklySchedule weeklySchedule;
  final List<String> specialClosedDates;
  final List<String> specialOpenDates;

  StoreHoursConfig({
    required this.weeklySchedule,
    this.specialClosedDates = const [],
    this.specialOpenDates = const [],
  });

  factory StoreHoursConfig.fromJson(Map<String, dynamic> json) {
    return StoreHoursConfig(
      weeklySchedule: WeeklySchedule.fromJson(json['weeklySchedule'] ?? {}),
      specialClosedDates: List<String>.from(json['specialClosedDates'] ?? []),
      specialOpenDates: List<String>.from(json['specialOpenDates'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weeklySchedule': weeklySchedule.toJson(),
      'specialClosedDates': specialClosedDates,
      'specialOpenDates': specialOpenDates,
    };
  }

  factory StoreHoursConfig.defaults() {
    final defaultDay = DaySchedule(
      enabled: true,
      ranges: [TimeRange(start: '11:00', end: '21:00')],
    );
    return StoreHoursConfig(
      weeklySchedule: WeeklySchedule(
        monday: defaultDay,
        tuesday: defaultDay,
        wednesday: defaultDay,
        thursday: defaultDay,
        friday: defaultDay,
        saturday: defaultDay,
        sunday: defaultDay,
      ),
    );
  }

  StoreHoursConfig copyWith({
    WeeklySchedule? weeklySchedule,
    List<String>? specialClosedDates,
    List<String>? specialOpenDates,
  }) {
    return StoreHoursConfig(
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      specialClosedDates: specialClosedDates ?? this.specialClosedDates,
      specialOpenDates: specialOpenDates ?? this.specialOpenDates,
    );
  }

  bool isWithin(DateTime time) {
    final dateStr =
        "${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}";

    // 1. 特殊闭店日期优先级最高
    if (specialClosedDates.contains(dateStr)) return false;

    // 2. 获取当天的常规配置
    final daySchedule = weeklySchedule.getDay(time.weekday);

    // 3. 如果当天未启用常规营业且不是特殊开放日，则不营业
    if (!daySchedule.enabled && !specialOpenDates.contains(dateStr)) {
      return false;
    }

    // 4. 检查当前时间是否在任何营业时段内
    if (daySchedule.ranges.isEmpty) {
      // 如果启用了但没设时段，默认全天（或者看业务逻辑，这里暂定没时段就不营业）
      return false;
    }

    final currentMinutes = time.hour * 60 + time.minute;
    for (final range in daySchedule.ranges) {
      final startParts = range.start.split(':');
      final endParts = range.end.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      final startMinutes =
          int.tryParse(startParts[0])! * 60 + int.tryParse(startParts[1])!;
      final endMinutes =
          int.tryParse(endParts[0])! * 60 + int.tryParse(endParts[1])!;

      if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
        return true;
      }
    }

    return false;
  }
}

class WeeklySchedule {
  final DaySchedule monday;
  final DaySchedule tuesday;
  final DaySchedule wednesday;
  final DaySchedule thursday;
  final DaySchedule friday;
  final DaySchedule saturday;
  final DaySchedule sunday;

  WeeklySchedule({
    required this.monday,
    required this.tuesday,
    required this.wednesday,
    required this.thursday,
    required this.friday,
    required this.saturday,
    required this.sunday,
  });

  factory WeeklySchedule.fromJson(Map<String, dynamic> json) {
    return WeeklySchedule(
      monday: DaySchedule.fromJson(json['monday'] ?? {}),
      tuesday: DaySchedule.fromJson(json['tuesday'] ?? {}),
      wednesday: DaySchedule.fromJson(json['wednesday'] ?? {}),
      thursday: DaySchedule.fromJson(json['thursday'] ?? {}),
      friday: DaySchedule.fromJson(json['friday'] ?? {}),
      saturday: DaySchedule.fromJson(json['saturday'] ?? {}),
      sunday: DaySchedule.fromJson(json['sunday'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monday': monday.toJson(),
      'tuesday': tuesday.toJson(),
      'wednesday': wednesday.toJson(),
      'thursday': thursday.toJson(),
      'friday': friday.toJson(),
      'saturday': saturday.toJson(),
      'sunday': sunday.toJson(),
    };
  }

  WeeklySchedule copyWith({
    DaySchedule? monday,
    DaySchedule? tuesday,
    DaySchedule? wednesday,
    DaySchedule? thursday,
    DaySchedule? friday,
    DaySchedule? saturday,
    DaySchedule? sunday,
  }) {
    return WeeklySchedule(
      monday: monday ?? this.monday,
      tuesday: tuesday ?? this.tuesday,
      wednesday: wednesday ?? this.wednesday,
      thursday: thursday ?? this.thursday,
      friday: friday ?? this.friday,
      saturday: saturday ?? this.saturday,
      sunday: sunday ?? this.sunday,
    );
  }

  DaySchedule getDay(int weekday) {
    switch (weekday) {
      case 1: return monday;
      case 2: return tuesday;
      case 3: return wednesday;
      case 4: return thursday;
      case 5: return friday;
      case 6: return saturday;
      case 7: return sunday;
      default: return monday;
    }
  }
}

class DaySchedule {
  final bool enabled;
  final List<TimeRange> ranges;

  DaySchedule({required this.enabled, required this.ranges});

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    return DaySchedule(
      enabled: json['enabled'] ?? false,
      ranges: (json['ranges'] as List? ?? [])
          .map((r) => TimeRange.fromJson(r))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'ranges': ranges.map((r) => r.toJson()).toList(),
    };
  }

  DaySchedule copyWith({
    bool? enabled,
    List<TimeRange>? ranges,
  }) {
    return DaySchedule(
      enabled: enabled ?? this.enabled,
      ranges: ranges ?? this.ranges,
    );
  }
}

class TimeRange {
  final String start;
  final String end;

  TimeRange({required this.start, required this.end});

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(
      start: json['start'] ?? '11:00',
      end: json['end'] ?? '21:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
    };
  }
}
