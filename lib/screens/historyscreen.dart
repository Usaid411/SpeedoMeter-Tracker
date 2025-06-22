import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/modal/data_model.dart';
import 'package:tracker/recordsStorage/trackingrecord.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<TrackingRecord>> _recordsFuture;
  final Map<int, bool> _expandedCards = {};
  final Set<String> _uploadingIds = {};
  final String targetSSID = "//SPECIFIC WIFI NAME PROPERLY";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _recordsFuture = loadRecords();
    });
    _checkWifiAndUpload();
  }

  Future<List<TrackingRecord>> loadRecords() async {
    final allRecords = await TrackingStorage().getRecords();

    // For debugging, print all records
    debugPrint("All records: ${allRecords.length}");
    for (var record in allRecords) {
      debugPrint(
        "Record: ${record.id}, ${record.fullName}, ${record.startTime}",
      );
    }

    // Sort records by startTime in descending order (newest first)
    allRecords.sort((a, b) => b.startTime.compareTo(a.startTime));

    // Get current user info
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('fullName') ?? '';
    final contactNumber = prefs.getString('contactNumber') ?? '';

    // If user info is empty, return all records
    if (fullName.isEmpty && contactNumber.isEmpty) {
      return allRecords;
    }

    // Otherwise filter by user info
    return allRecords
        .where(
          (record) =>
              record.fullName == fullName &&
              record.contactNumber == contactNumber,
        )
        .toList();
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
          // Refresh the data after upload
          if (mounted) {
            _loadData();
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
          SnackBar(content: Text('Upload error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _uploadToGoogleSheets(TrackingRecord session) async {
    const String scriptURL =
        "https://script.google.com/macros/s/...../exec  //LOOKS LIKE THIS";

    try {
      setState(() {
        _uploadingIds.add(session.id);
      });

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}')),
        );
      }
      rethrow;
    } finally {
      setState(() {
        _uploadingIds.remove(session.id);
      });
    }
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Widget _buildMapPreview(TrackingRecord record, BuildContext context) {
    try {
      final startPoint = LatLng(record.startLat, record.startLng);
      final endPoint = LatLng(record.endLat, record.endLng);

      final CameraPosition initialCameraPosition = CameraPosition(
        target: LatLng(
          (record.startLat + record.endLat) / 2,
          (record.startLng + record.endLng) / 2,
        ),
        zoom: 12,
      );

      final Set<Marker> markers = {
        Marker(
          markerId: const MarkerId('start'),
          position: startPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: endPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };

      final Set<Polyline> polylines = {
        if (record.route.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('route'),
            points: record.route,
            color: Colors.blue.withOpacity(0.7),
            width: 4,
          ),
      };

      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.25, // Responsive height
        child: GoogleMap(
          initialCameraPosition: initialCameraPosition,
          markers: markers,
          polylines: polylines,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          scrollGesturesEnabled: false,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
          zoomGesturesEnabled: false,
          liteModeEnabled: false,
          onMapCreated: (controller) {},
        ),
      );
    } catch (e) {
      debugPrint('Error building map preview: $e');
      return Container(
        height: MediaQuery.of(context).size.height * 0.25,
        color: Colors.grey[200],
        child: Center(
          child: Text(
            'Map unavailable',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    BuildContext context,
  ) {
    final scaleFactor = MediaQuery.of(context).textScaleFactor;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0 * scaleFactor),
      child: Row(
        children: [
          Icon(icon, size: 18 * scaleFactor, color: Colors.blueGrey),
          SizedBox(width: 8 * scaleFactor),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14 * scaleFactor,
            ),
          ),
          SizedBox(width: 4 * scaleFactor),
          Text(value, style: TextStyle(fontSize: 14 * scaleFactor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = MediaQuery.of(context).textScaleFactor;
        final isSmallScreen = constraints.maxWidth < 350;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text(
              'Trip History',
              style: TextStyle(
                fontSize: isSmallScreen ? 20 : 23,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.bug_report, size: 24 * scaleFactor),
                onPressed: () async {
                  final records = await TrackingStorage().getRecords();
                  debugPrint("Current records in storage: ${records.length}");
                  for (var record in records) {
                    debugPrint(
                      "ID: ${record.id}, Name: ${record.fullName}, Start: ${record.startTime}",
                    );
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${records.length} records in storage'),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 24 * scaleFactor),
                onPressed: _loadData,
              ),
            ],
          ),
          body: FutureBuilder<List<TrackingRecord>>(
            future: _recordsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error,
                        size: 60 * scaleFactor,
                        color: Colors.red,
                      ),
                      SizedBox(height: 16 * scaleFactor),
                      Text(
                        'Error loading trips: ${snapshot.error}',
                        style: TextStyle(
                          fontSize: 18 * scaleFactor,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8 * scaleFactor),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text(
                          'Retry',
                          style: TextStyle(fontSize: 16 * scaleFactor),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 60 * scaleFactor,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16 * scaleFactor),
                      Text(
                        'No trips recorded yet',
                        style: TextStyle(
                          fontSize: 18 * scaleFactor,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8 * scaleFactor),
                      TextButton(
                        onPressed: _loadData,
                        child: Text(
                          'Refresh',
                          style: TextStyle(fontSize: 16 * scaleFactor),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final records = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async {
                  _loadData();
                  return;
                },
                child: ListView.builder(
                  padding: EdgeInsets.all(8 * scaleFactor),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final isExpanded = _expandedCards[index] ?? false;
                    final date = DateFormat(
                      'MMM d, yyyy',
                    ).format(record.startTime);
                    final startTime = DateFormat(
                      'HH:mm',
                    ).format(record.startTime);
                    final endTime = DateFormat('HH:mm').format(record.endTime);
                    final isUploading = _uploadingIds.contains(record.id);

                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.symmetric(
                        vertical: 8 * scaleFactor,
                        horizontal: isSmallScreen ? 4 : 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * scaleFactor),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _expandedCards[index] = !isExpanded;
                          });
                        },
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                radius: 20 * scaleFactor,
                                backgroundColor: Colors.blue[100],
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16 * scaleFactor,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Trip on $date',
                                style: TextStyle(fontSize: 16 * scaleFactor),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$startTime - $endTime',
                                    style: TextStyle(
                                      fontSize: 14 * scaleFactor,
                                    ),
                                  ),
                                  if (isUploading)
                                    Text(
                                      'Uploading...',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12 * scaleFactor,
                                      ),
                                    )
                                  else if (record.isUploaded)
                                    Text(
                                      'Uploaded',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12 * scaleFactor,
                                      ),
                                    )
                                  else
                                    Text(
                                      'Not uploaded',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12 * scaleFactor,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Icon(
                                isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 24 * scaleFactor,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16 * scaleFactor,
                                vertical: 8 * scaleFactor,
                              ),
                            ),
                            if (isExpanded) ...[
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16 * scaleFactor,
                                ),
                                child: Column(
                                  children: [
                                    _buildMapPreview(record, context),
                                    SizedBox(height: 16 * scaleFactor),
                                    _buildInfoRow(
                                      Icons.timer,
                                      'Duration:',
                                      _formatDuration(record.duration),
                                      context,
                                    ),
                                    _buildInfoRow(
                                      Icons.directions_car,
                                      'Distance:',
                                      '${record.distance.toStringAsFixed(2)} km',
                                      context,
                                    ),
                                    _buildInfoRow(
                                      Icons.speed,
                                      'Avg Speed:',
                                      '${record.avgSpeed.toStringAsFixed(1)} km/h',
                                      context,
                                    ),
                                    SizedBox(height: 8 * scaleFactor),
                                    if (!record.isUploaded && !isUploading)
                                      ElevatedButton(
                                        onPressed: () async {
                                          await _uploadToGoogleSheets(record);
                                          _loadData();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          minimumSize: Size(
                                            double.infinity,
                                            40 * scaleFactor,
                                          ),
                                        ),
                                        child: Text(
                                          'Upload Now',
                                          style: TextStyle(
                                            fontSize: 16 * scaleFactor,
                                          ),
                                        ),
                                      ),
                                    SizedBox(height: 8 * scaleFactor),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
