import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:tracker/modal/data_model.dart';
import 'package:tracker/dialogbox.dart';
import 'package:tracker/recordsStorage/trackingrecord.dart';

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({
    super.key,
    required this.fullName,
    required this.contactNumber,
  });

  final String fullName;
  final String contactNumber;
  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  double _speed = 0.0;
  double _totalDistance = 0.0;
  double _avgSpeed = 0.0;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;
  Position? _startPosition;
  DateTime? _startTime;
  List<LatLng> _routePoints = [];
  bool _isUploading = false;
  bool _isPaused = false;
  final String targetSSID = "//SPECIFIC WIFI NAME PROPERLY";

  @override
  void initState() {
    super.initState();
    _checkWifiAndUpload();
  }

  Future<void> _checkWifiAndUpload() async {
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName();

      if (ssid == null) {
        debugPrint("Not connected to any WiFi network");
        return;
      }

      final cleanedSSID = ssid.replaceAll('"', '').trim();
      debugPrint("Connected to Wi-Fi: $cleanedSSID");

      if (cleanedSSID == targetSSID) {
        final records = await TrackingStorage().getRecords();
        final unuploadedRecords = records
            .where((record) => !record.isUploaded)
            .toList();

        if (unuploadedRecords.isNotEmpty) {
          debugPrint("Found ${unuploadedRecords.length} unuploaded records");
          for (final record in unuploadedRecords) {
            await _uploadToGoogleSheets(record);

            await TrackingStorage().markAsUploaded(record);
          }
        } else {
          debugPrint("No unuploaded records found");
        }
      } else {
        debugPrint("Not connected to target Wi-Fi ($targetSSID)");
      }
    } catch (e) {
      debugPrint("WiFi check/upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WiFi check failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _startTracking() async {
    if (_isPaused) {
      // Resume tracking
      setState(() {
        _isPaused = false;
        _stopwatch.start();
      });
      return;
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse) {
          return;
        }
      }

      _stopwatch.start();
      _startTime = DateTime.now();

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 1,
            ),
          ).listen((Position position) {
            if (mounted) {
              setState(() {
                _speed = position.speed * 3.6;

                if (_lastPosition != null) {
                  _totalDistance +=
                      Geolocator.distanceBetween(
                        _lastPosition!.latitude,
                        _lastPosition!.longitude,
                        position.latitude,
                        position.longitude,
                      ) /
                      1000;

                  _routePoints.add(
                    LatLng(position.latitude, position.longitude),
                  );
                } else {
                  _startPosition = position;
                }

                _lastPosition = position;

                final seconds = _stopwatch.elapsed.inSeconds;
                if (seconds > 0) {
                  _avgSpeed = _totalDistance / (seconds / 3600);
                }
              });
            }
          });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting tracking: $e')));
      }
    }
  }

  Future<void> _uploadToGoogleSheets(TrackingRecord session) async {
    const String scriptURL =
        "https://script.google.com/macros/s/...../exec  //LOOKS LIKE THIS";

    try {
      final client = http.Client();
      final response = await client.post(
        Uri.parse(scriptURL),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'action': 'saveTrackingData',
          'id': session.id,
          'fullName': session.fullName ?? 'N/A',
          'contactNumber': session.contactNumber ?? 'N/A',
          'startTime': session.startTime.toIso8601String(),
          'endTime': session.endTime.toIso8601String(),
          'startLat': session.startLat.toString(),
          'startLng': session.startLng.toString(),
          'endLat': session.endLat.toString(),
          'endLng': session.endLng.toString(),
          'distance': session.distance.toString(),
          'avgSpeed': session.avgSpeed.toString(),
          'durationSeconds': session.duration.inSeconds.toString(),
          'routePolyline': (session.route.isNotEmpty)
              ? session.route
                    .map((p) => '${p.latitude},${p.longitude}')
                    .join('|')
              : '[]',
        },
      );

      debugPrint("Upload response: ${response.statusCode} - ${response.body}");

      if (response.statusCode != 200) {
        throw Exception('Failed to upload: ${response.body}');
      }

      session.isUploaded = true;
      await TrackingStorage().updateRecord(session);

      final responseData = jsonDecode(response.body);
      if (responseData['status'] != 'success') {
        throw Exception(responseData['message'] ?? 'Upload failed');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data uploaded successfully!')),
        );
      }
    } catch (e) {
      debugPrint("Upload error: $e");
    }
  }

  Future<void> _stopTracking({
    bool askToSave = true,
    bool resetValues = true,
  }) async {
    if (!_stopwatch.isRunning) return;

    bool shouldSave = true;

    if (askToSave && mounted) {
      shouldSave =
          await showDialog<bool>(
            context: context,
            builder: (context) => const CustomSaveDialog(
              title: "End Tracking Session?",
              message: "Do you want to save this tracking data?",
            ),
          ) ??
          false;
    }

    await _positionStream?.cancel();
    _positionStream = null;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();

    if (shouldSave &&
        _stopwatch.elapsed.inSeconds > 0 &&
        _startTime != null &&
        _startPosition != null &&
        _lastPosition != null) {
      final session = TrackingRecord(
        startTime: _startTime!,
        endTime: DateTime.now(),
        startLat: _startPosition!.latitude,
        startLng: _startPosition!.longitude,
        endLat: _lastPosition!.latitude,
        endLng: _lastPosition!.longitude,
        distance: _totalDistance,
        avgSpeed: _avgSpeed,
        duration: _stopwatch.elapsed,
        route: List.from(_routePoints),
        contactNumber: widget.contactNumber,
        fullName: widget.fullName,
      );

      await TrackingStorage().saveRecord(session);
      await _checkWifiAndUpload();
    }

    // Only reset values if explicitly requested
    if (resetValues) {
      setState(() {
        _speed = 0.0;
        _totalDistance = 0.0;
        _avgSpeed = 0.0;
        _stopwatch.reset();
        _lastPosition = null;
        _startPosition = null;
        _startTime = null;
      });
    }
  }

  Future<void> _pauseTracking() async {
    if (!_stopwatch.isRunning) return;

    setState(() {
      _isPaused = true;
      _stopwatch.stop();
    });
  }

  String get formattedTime {
    final duration = _stopwatch.elapsed;
    return DateFormat('HH:mm:ss').format(
      DateTime.fromMillisecondsSinceEpoch(duration.inMilliseconds, isUtc: true),
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textcolor = Colors.black;
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 350;
    final isLargeScreen = screenSize.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Speedometer',
          style: TextStyle(
            color: textcolor,
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 20 : 23,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Speedometer Gauge
                      SizedBox(
                        height: isSmallScreen
                            ? screenSize.height * 0.35
                            : isLargeScreen
                            ? screenSize.height * 0.4
                            : screenSize.height * 0.3,
                        child: SfRadialGauge(
                          axes: <RadialAxis>[
                            RadialAxis(
                              minimum: 0,
                              maximum: 120,
                              ranges: <GaugeRange>[
                                GaugeRange(
                                  startValue: 0,
                                  endValue: 60,
                                  color: Colors.green,
                                ),
                                GaugeRange(
                                  startValue: 60,
                                  endValue: 90,
                                  color: Colors.orange,
                                ),
                                GaugeRange(
                                  startValue: 90,
                                  endValue: 120,
                                  color: Colors.red,
                                ),
                              ],
                              pointers: <GaugePointer>[
                                NeedlePointer(value: _speed),
                              ],
                              annotations: <GaugeAnnotation>[
                                GaugeAnnotation(
                                  widget: Text(
                                    '${_speed.toStringAsFixed(1)} km/h',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 18 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: textcolor,
                                    ),
                                  ),
                                  angle: 90,
                                  positionFactor: 0.5,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isSmallScreen ? 10 : 20),

                      // Info Tiles
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 8.0 : 16.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _infoTile(
                              'Time',
                              formattedTime,
                              Colors.green,
                              textcolor,
                              isSmallScreen: isSmallScreen,
                            ),
                            _infoTile(
                              'Distance',
                              '${_totalDistance.toStringAsFixed(2)} km',
                              Colors.blue,
                              textcolor,
                              isSmallScreen: isSmallScreen,
                            ),
                            _infoTile(
                              'Avg Speed',
                              '${_avgSpeed.toStringAsFixed(1)} km/h',
                              Colors.red,
                              textcolor,
                              isSmallScreen: isSmallScreen,
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isSmallScreen ? 20 : 30),

                      // Control Buttons
                      _isUploading
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 8.0 : 16.0,
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: isSmallScreen ? 8.0 : 20.0,
                                runSpacing: isSmallScreen ? 8.0 : 0,
                                children: [
                                  ElevatedButton(
                                    onPressed: _stopwatch.isRunning
                                        ? null
                                        : _startTracking,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(
                                        isSmallScreen ? 80 : 100,
                                        isSmallScreen ? 40 : 48,
                                      ),
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      _isPaused ? 'RESUME' : 'START',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 12 : 14,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async =>
                                        await _stopTracking(),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(
                                        isSmallScreen ? 80 : 100,
                                        isSmallScreen ? 40 : 48,
                                      ),
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      'STOP',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 12 : 14,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: _stopwatch.isRunning
                                        ? _pauseTracking
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(
                                        isSmallScreen ? 80 : 100,
                                        isSmallScreen ? 40 : 48,
                                      ),
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      'PAUSE',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 12 : 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                      // Add some flexible space at the bottom for smaller screens
                      if (isSmallScreen) const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _infoTile(
    String title,
    String value,
    Color color,
    Color textColor, {
    bool isSmallScreen = false,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontSize: isSmallScreen ? 14 : 16),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
