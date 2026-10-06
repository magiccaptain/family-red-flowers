import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'garden.dart';

class GardenCommand {
  GardenCommand(this.kind, Map<String, Object?> payload, {String? id})
    : id = id ?? const Uuid().v4(),
      payload = Map.unmodifiable(payload);

  final String id;
  final String kind;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {'id': id, 'kind': kind, 'payload': payload};

  factory GardenCommand.fromJson(Map<String, dynamic> json) => GardenCommand(
    json['kind'] as String,
    Map<String, Object?>.from(json['payload'] as Map),
    id: json['id'] as String,
  );

  /// An add-child retry creates a new tentative ID locally. Its original
  /// command and child IDs must still be reused after an ambiguous response.
  bool sameIntent(GardenCommand other) {
    Map<String, Object?> normalized(GardenCommand command) {
      final result = {...command.payload};
      if (command.kind == 'add_child') result.remove('childId');
      return result;
    }

    return kind == other.kind &&
        jsonEncode(normalized(this)) == jsonEncode(normalized(other));
  }
}

abstract interface class CommandGardenRepository {
  Future<GardenData> apply(GardenCommand command);
  Future<GardenData> refresh();
  bool get offline;
  bool get hasPending;
  DateTime? get lastSyncAt;
  String? get notice;
}
