import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/modal/data_model.dart';

class TrackingStorage {
  static const String _recordsKey = 'tracking_records';

  Future<List<TrackingRecord>> getRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_recordsKey);
      if (jsonString == null) {
        return [];
      }
      final List list = json.decode(jsonString);

      return list.map((e) => TrackingRecord.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> updateRecord(TrackingRecord record) async {
    final records = await getRecords();
    final index = records.indexWhere((r) => r.id == record.id);

    if (index != -1) {
      records[index] = record.copyWith();
      await _saveAllRecords(records);
    }
  }

  Future<void> saveRecord(TrackingRecord record) async {
    final records = await getRecords();
    if (!records.any((r) => r.id == record.id)) {
      records.add(record);
      await _saveAllRecords(records);
    }
  }

  Future<void> markAsUploaded(TrackingRecord record) async {
    final updatedRecord = record.copyWith(isUploaded: true);
    await updateRecord(updatedRecord);
  }

  Future<void> _saveAllRecords(List<TrackingRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(records.map((e) => e.toMap()).toList());
    await prefs.setString(_recordsKey, jsonString);
  }
}
