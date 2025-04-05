import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(SmartAttendApp());
}

class SmartAttendApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAttend',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: QRScanPage(),
    );
  }
}

class QRScanPage extends StatefulWidget {
  @override
  _QRScanPageState createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Barcode? result;
  QRViewController? controller;
  bool isLogging = false;

  // In order to get hot reload to work we need to pause the camera if the platform is Android.
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    }
    controller?.resumeCamera();
  }

  // Method to get current location
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    
    // Check if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled, don't continue.
      return null;
    }

    // Check for location permissions.
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied.
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever.
      return null;
    }
    
    return await Geolocator.getCurrentPosition();
  }

  // Method to log attendance to Firestore
  Future<void> _logAttendance(String qrData) async {
    setState(() {
      isLogging = true;
    });

    Position? position = await _getCurrentLocation();
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location not available. Please enable GPS.')),
      );
      setState(() {
        isLogging = false;
      });
      return;
    }

    // Create a record to log
    Map<String, dynamic> attendanceData = {
      'qrData': qrData,
      'timestamp': DateTime.now(),
      'location': {
        'latitude': position.latitude,
        'longitude': position.longitude,
      },
    };

    try {
      await FirebaseFirestore.instance
          .collection('attendances')
          .add(attendanceData);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attendance logged successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to log attendance: $e')),
      );
    }

    setState(() {
      isLogging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SmartAttend'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: (result != null)
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Scanned Data: ${result!.code}',
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: isLogging
                              ? null
                              : () => _logAttendance(result!.code ?? ''),
                          child: isLogging
                              ? CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text('Log Attendance'),
                        ),
                      ],
                    )
                  : Text('Scan a QR code'),
            ),
          )
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (mounted) {
        setState(() {
          result = scanData;
        });
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
