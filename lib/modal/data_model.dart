import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:uuid/uuid.dart';

class TrackingRecord {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final double distance;
  final double avgSpeed;
  final Duration duration;
  final List<LatLng> route;
  final String? fullName;
  final String? contactNumber;
  bool isUploaded;

  TrackingRecord({
    String? id,
    required this.startTime,
    required this.endTime,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.distance,
    required this.avgSpeed,
    required this.duration,
    required this.route,
    this.contactNumber,
    this.fullName,
    this.isUploaded = false,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName ?? 'N/A',
      'contactNumber': contactNumber ?? 'N/A',
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'startLat': startLat,
      'startLng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'distance': distance,
      'avgSpeed': avgSpeed,
      'durationSeconds': duration.inSeconds,
      'routePolyline': route.isNotEmpty
          ? route.map((p) => '${p.latitude},${p.longitude}').join('|')
          : '',
      'isUploaded': isUploaded,
    };
  }

  factory TrackingRecord.fromMap(Map<String, dynamic> map) {
    return TrackingRecord(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      startLat: map['startLat'],
      startLng: map['startLng'],
      endLat: map['endLat'],
      endLng: map['endLng'],
      distance: map['distance'],
      avgSpeed: map['avgSpeed'],
      duration: Duration(seconds: map['durationSeconds'] ?? map['duration']),
      route: _parseRouteData(map['routePolyline']),
      fullName: map['fullName'],
      contactNumber: map['contactNumber'],
      isUploaded: map['isUploaded'] ?? false,
    );
  }

  static List<LatLng> _parseRouteData(dynamic routeData) {
    if (routeData == null) return [];

    // Handle case when routeData is already a List<LatLng>
    if (routeData is List) {
      return routeData.whereType<LatLng>().toList();
    }

    // Handle case when routeData is a string (pipe-separated coordinates)
    if (routeData is String) {
      if (routeData.isEmpty || routeData == '[]') return [];

      try {
        return routeData.split('|').map((point) {
          final coords = point.split(',');
          return LatLng(double.parse(coords[0]), double.parse(coords[1]));
        }).toList();
      } catch (e) {
        return [];
      }
    }

    return [];
  }

  TrackingRecord copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    double? distance,
    double? avgSpeed,
    Duration? duration,
    List<LatLng>? route,
    String? fullName,
    String? contactNumber,
    bool? isUploaded,
  }) {
    return TrackingRecord(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      distance: distance ?? this.distance,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      duration: duration ?? this.duration,
      route: route ?? this.route,
      fullName: fullName ?? this.fullName,
      contactNumber: contactNumber ?? this.contactNumber,
      isUploaded: isUploaded ?? this.isUploaded,
    );
  }
}
