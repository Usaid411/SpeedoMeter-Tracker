import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:tracker/modal/data_model.dart';
import 'package:tracker/dialogbox.dart';
import 'package:tracker/recordsStorage/trackingrecord.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.fullName,
    required this.contactNumber,
  });

  final String fullName;
  final String contactNumber;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final String targetSSID = "//SPECIFIC WIFI NAME PROPERLY";

  late GoogleMapController _mapController;
  LatLng? _currentPosition;
  LatLng? _destinationPosition;
  final List<LatLng> _route = [];
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  double _speed = 0.0;
  double _totalDistance = 0.0;
  double _avgSpeed = 0.0;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  Position? _lastPosition;
  Position? _startPosition;
  DateTime? _startTime;
  double _zoomLevel = 15.0;
  bool _isPaused = false;
  bool isUploading = false;

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _placePredictions = [];
  bool _showSearchResults = false;

  static const String googleApiKey = "//GOOGLE API KEY HERE";

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInit();
  }

  Future<void> _checkPermissionsAndInit() async {
    var status = await Permission.location.status;
    if (!status.isGranted) {
      status = await Permission.location.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    await _getInitialPosition();
  }

  Future<void> _getInitialPosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _route.add(_currentPosition!);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting initial position: ${e.toString()}'),
        ),
      );
    }
  }

  Future<void> _searchPlace(String input) async {
    if (input.isEmpty) {
      setState(() {
        _placePredictions = [];
        _showSearchResults = false;
      });
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$googleApiKey';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        setState(() {
          _placePredictions = data['predictions'];
          _showSearchResults = true;
        });
      } else {
        setState(() {
          _placePredictions = [];
          _showSearchResults = false;
        });
      }
    }
  }

  Future<LatLng?> _getPlaceLatLng(String placeId) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleApiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        final location = data['result']['geometry']['location'];
        return LatLng(location['lat'], location['lng']);
      }
    }
    return null;
  }

  Future<List<LatLng>> _getDirections(LatLng origin, LatLng destination) async {
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleApiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if ((data['routes'] as List).isNotEmpty) {
        final polylinePoints = data['routes'][0]['overview_polyline']['points'];
        return _decodePolyline(polylinePoints);
      }
    }
    return [];
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      polyline.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return polyline;
  }

  Future<void> _onPlaceSelected(dynamic prediction) async {
    _searchController.text = prediction['description'];
    setState(() {
      _placePredictions = [];
      _showSearchResults = false;
    });
    FocusScope.of(context).unfocus();

    final placeId = prediction['place_id'];
    final destinationLatLng = await _getPlaceLatLng(placeId);
    if (destinationLatLng != null && _currentPosition != null) {
      setState(() {
        _destinationPosition = destinationLatLng;
      });

      final routePoints = await _getDirections(
        _currentPosition!,
        destinationLatLng,
      );
      setState(() {
        _route.clear();
        _route.addAll(routePoints);
      });

      _mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
          _boundsFromLatLngList([_currentPosition!, destinationLatLng]),
          100,
        ),
      );
    }
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double x0 = list[0].latitude,
        x1 = list[0].latitude,
        y0 = list[0].longitude,
        y1 = list[0].longitude;

    for (LatLng latLng in list) {
      if (latLng.latitude > x1) x1 = latLng.latitude;
      if (latLng.latitude < x0) x0 = latLng.latitude;
      if (latLng.longitude > y1) y1 = latLng.longitude;
      if (latLng.longitude < y0) y0 = latLng.longitude;
    }

    return LatLngBounds(northeast: LatLng(x1, y1), southwest: LatLng(x0, y0));
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
            // Mark as uploaded after successful upload
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
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
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
                _route.add(LatLng(position.latitude, position.longitude));
              } else {
                _startPosition = position;
                _route.clear();
                _route.add(LatLng(position.latitude, position.longitude));
              }

              _lastPosition = position;
              final seconds = _stopwatch.elapsed.inSeconds;
              if (seconds > 0) {
                _avgSpeed = _totalDistance / (seconds / 3600);
              }

              _currentPosition = LatLng(position.latitude, position.longitude);
              _mapController.animateCamera(
                CameraUpdate.newLatLng(_currentPosition!),
              );
            });
          }
        });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 350;
    final buttonPadding = isSmallScreen ? 8.0 : 12.0;
    final infoCardFontSize = isSmallScreen ? 10.0 : 12.0;
    final valueFontSize = isSmallScreen ? 12.0 : 14.0;
    final buttonFontSize = isSmallScreen ? 12.0 : 14.0;
    final searchBarTopPadding = isSmallScreen ? 5.0 : 10.0;
    final controlsBottomPadding = isSmallScreen ? 10.0 : 20.0;
    final controlsHorizontalPadding = isSmallScreen ? 10.0 : 20.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Map Tracker',
          style: TextStyle(
            fontSize: screenSize.width < 400 ? 20 : 23,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Map Container
          if (_currentPosition == null)
            const Center(child: CircularProgressIndicator())
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition!,
                zoom: _zoomLevel,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('current'),
                  position: _currentPosition!,
                  infoWindow: const InfoWindow(title: "You"),
                ),
                if (_destinationPosition != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: _destinationPosition!,
                    infoWindow: const InfoWindow(title: "Destination"),
                  ),
              },
              polylines: {
                if (_route.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    color: Colors.blue,
                    width: 4,
                    points: _route,
                  ),
              },
              onCameraMove: (CameraPosition position) {
                setState(() {
                  _zoomLevel = position.zoom;
                });
              },
            ),

          // Search Bar
          Positioned(
            top: searchBarTopPadding,
            left: searchBarTopPadding,
            right: searchBarTopPadding,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _searchPlace,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 8 : 12,
                        horizontal: isSmallScreen ? 12 : 16,
                      ),
                      hintText: 'Search destination...',
                      border: InputBorder.none,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: isSmallScreen ? 18 : 24,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _placePredictions = [];
                                  _showSearchResults = false;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                  if (_showSearchResults && _placePredictions.isNotEmpty)
                    Container(
                      height: screenSize.height * 0.3,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _placePredictions.length,
                        itemBuilder: (context, index) {
                          final prediction = _placePredictions[index];
                          return ListTile(
                            title: Text(
                              prediction['description'],
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                            ),
                            onTap: () => _onPlaceSelected(prediction),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Tracking Controls
          Positioned(
            bottom: controlsBottomPadding,
            left: controlsHorizontalPadding,
            right: controlsHorizontalPadding,
            child: Container(
              padding: EdgeInsets.all(buttonPadding),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCard(
                        'Speed',
                        '${_speed.toStringAsFixed(1)} km/h',
                        fontSize: infoCardFontSize,
                        valueSize: valueFontSize,
                      ),
                      _buildInfoCard(
                        'Distance',
                        '${_totalDistance.toStringAsFixed(2)} km',
                        fontSize: infoCardFontSize,
                        valueSize: valueFontSize,
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCard(
                        'Avg Speed',
                        '${_avgSpeed.toStringAsFixed(1)} km/h',
                        fontSize: infoCardFontSize,
                        valueSize: valueFontSize,
                      ),
                      _buildInfoCard(
                        'Time',
                        formattedTime,
                        fontSize: infoCardFontSize,
                        valueSize: valueFontSize,
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(
                        child: ElevatedButton(
                          onPressed: _stopwatch.isRunning
                              ? null
                              : _startTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            textStyle: TextStyle(fontSize: buttonFontSize),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 12,
                              vertical: isSmallScreen ? 8 : 10,
                            ),
                          ),
                          child: Text(
                            _isPaused ? 'Resume' : 'Start',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 4 : 8),
                      Flexible(
                        child: ElevatedButton(
                          onPressed: _stopwatch.isRunning
                              ? _stopTracking
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            textStyle: TextStyle(fontSize: buttonFontSize),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 12,
                              vertical: isSmallScreen ? 8 : 10,
                            ),
                          ),
                          child: const Text(
                            'Stop',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 4 : 8),
                      Flexible(
                        child: ElevatedButton(
                          onPressed: _stopwatch.isRunning
                              ? _pauseTracking
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            textStyle: TextStyle(fontSize: buttonFontSize),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 12,
                              vertical: isSmallScreen ? 8 : 10,
                            ),
                          ),
                          child: const Text(
                            'Pause',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value, {
    required double fontSize,
    required double valueSize,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
