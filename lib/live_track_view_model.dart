import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:fluttertoast/fluttertoast.dart';

class LiveTrackViewModel extends ChangeNotifier {
  bool _locationPermissionGranted = false;
  bool _gpsEnabled = false;
  final Location _location = Location();

  bool get isLocationPermissionGranted => _locationPermissionGranted;
  bool get isGPSEnabled => _gpsEnabled;
//markers map
  final Set<Marker> _markers = {};
  Set<Marker> get markersMap => _markers;

//polyline
  final Set<Polyline> _polyline = {};
  Set<Polyline> get polylinesMap => _polyline;

  final List<LatLng> _visitedPoints = [];
  List<LatLng> get visitedPoints => _visitedPoints;

  Marker? _startMarker;
  Marker? _currentMarker;

  Future<void> checkLocationPermissionAndGPS() async {
    await _checkLocationPermission();
    await _checkGPSEnabled();
    // If permission or GPS is not enabled, try requesting them
    if (!_locationPermissionGranted) {
      await requestLocationPermission();
    }
    if (!_gpsEnabled) {
      await requestGPSEnabled();
    }
    if (_locationPermissionGranted && _gpsEnabled) {
      await getPreviousLocation();
      listenToLocationUpdates();
    }
  }

  Future<void> _checkLocationPermission() async {
    final permissionStatus = await _location.requestPermission();
    _locationPermissionGranted = permissionStatus == PermissionStatus.granted ||
        permissionStatus == PermissionStatus.grantedLimited;
    notifyListeners();
  }

  Future<void> requestLocationPermission() async {
    final permissionStatus = await _location.requestPermission();
    _locationPermissionGranted = permissionStatus == PermissionStatus.granted ||
        permissionStatus == PermissionStatus.grantedLimited;
    notifyListeners();
    if (_locationPermissionGranted) {
      _showToast('Location permission granted!', isSuccess: true);
    } else if (permissionStatus == PermissionStatus.deniedForever) {
      _showToast(
          'Location permission denied permanently. Opening app settings.');
      openAppSettingsForLocation();
    } else if (permissionStatus == PermissionStatus.denied) {
      _showToast('Location permission denied. Please grant permission.');
      // Optionally, you might want to provide a button in your UI to retry.
    }
  }

  Future<void> _checkGPSEnabled() async {
    _gpsEnabled = await _location.serviceEnabled();
    notifyListeners();
  }

  Future<void> requestGPSEnabled() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      final enabled = await _location.requestService();
      _gpsEnabled = enabled;
      notifyListeners();
      if (_gpsEnabled) {
        _showToast('GPS enabled!', isSuccess: true);
      } else {
        // GPS enabling failed on the first attempt, try one more time
        final enabledSecondAttempt = await _location.requestService();
        _gpsEnabled = enabledSecondAttempt;
        notifyListeners();
        if (_gpsEnabled) {
          _showToast('GPS enabled!', isSuccess: true);
        } else {
          // GPS still couldn't be enabled, show a toast indicating it's required
          _showToast(
              'GPS is required for this feature. Please enable it in your device settings.');
          // Optionally, you could still provide a button in your UI to open settings.
          // openAppSettingsForLocation();
        }
      }
    } else {
      _gpsEnabled = true;
      notifyListeners();
      _showToast('GPS is already enabled.', isSuccess: true);
    }
  }

  Future<void> openAppSettingsForLocation() async {
    final bool opened = await perm.openAppSettings();
    if (opened) {
      _showToast('Opened app settings.');
      // The user will manually change settings. You'll need to re-check
      // permissions and GPS when they return to the app.
    } else {
      _showToast('Could not open app settings.');
    }
  }

  void _showToast(String message, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: isSuccess ? Colors.green : Colors.redAccent,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Future<BitmapDescriptor> _getCustomMarker(String path) async {
    return await BitmapDescriptor.asset(
        const ImageConfiguration(
            size: Size(48.0, 48.0)), // Adjust size as needed
        path);
  }

  GoogleMapController? mapController;
  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    notifyListeners();
  }

  void listenToLocationUpdates() {
    FirebaseFirestore.instance
        .collection('users')
        .doc('default_user')
        .collection("location_logs")
        .orderBy('timestamp',
            descending: true) // Sort by timestamp in descending order
        .limit(1) // Only fetch the most recent document
        .snapshots()
        .listen((querySnapshot) async {
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot
            .docs.first; // Only take the first document (most recent)
        final data = doc.data();
        final double lat = data['latitude'];
        final double lng = data['longitude'];
        final LatLng newPoint = LatLng(lat, lng);

        // Add the new location to the visited points
        _visitedPoints.add(newPoint);

        // Optionally, update your polyline with this new point
        _polyline.clear(); // Clear the existing polyline
        _polyline.add(Polyline(
          polylineId: const PolylineId('path'),
          points: _visitedPoints,
          color: Colors.red,
          width: 5,
        ));
        final currentIcon = await _getCustomMarker('assets/pin.png');
        // Optionally, update your markers
        _currentMarker = Marker(
          markerId: const MarkerId('current_marker'),
          position: newPoint,
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: currentIcon, // Or use a custom icon
        );

        // Update markers and polyline
        _markers.add(_currentMarker!);
        mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _visitedPoints.last,
              zoom: 14,
            ),
          ),
        );

        notifyListeners(); // Notify listeners to refresh the UI
      }
    });
  }

  getPreviousLocation() async {
    var querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc("default_user") // Use the passed userId instead of "default_user"
        .collection('location_logs')
        .orderBy(
            'timestamp') // Optional: Ensure you get the logs in order of timestamp
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      _visitedPoints.clear();
      // Iterate through all the documents
      for (var doc in querySnapshot.docs) {
        var data = doc.data();
        double lat = data['latitude']; // Assuming 'latitude' is the field name
        double lng =
            data['longitude']; // Assuming 'longitude' is the field name
        _visitedPoints.add(LatLng(lat, lng)); // Add each location to the list
      }
      debugPrint("-------$_visitedPoints");
      final customIcon = await _getCustomMarker('assets/start.png');
      _startMarker = Marker(
          markerId: const MarkerId('start_marker'),
          position: _visitedPoints.first,
          infoWindow: const InfoWindow(title: 'Start Location'),
          icon: customIcon);
      final currentIcon = await _getCustomMarker('assets/pin.png');
      _currentMarker = Marker(
          markerId: const MarkerId('current_marker'),
          position: _visitedPoints.last,
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: currentIcon);
      _polyline.clear();
      _polyline.add(Polyline(
        polylineId: const PolylineId('path'),
        points: _visitedPoints,
        color: Colors.red,
        width: 5,
      ));
      // Update markers
      _markers.clear();
      _markers.add(_startMarker!);
      _markers.add(_currentMarker!);
    } else {
      // Return an empty list if no data is found
      print("No location logs found.");
    }
    debugPrint(
        "Polyline Length: ${_polyline.length}, -------------${_visitedPoints.length}");
    notifyListeners();
  }
}




// void _startUpdatingMarker() async {
//     _pointIndex = 0;
//     final customIcon = await _getCustomMarker('assets/pin.png');

//     _markerUpdateTimer =
//         Timer.periodic(const Duration(seconds: 1), (Timer timer) async {
//       if (_pointIndex < visitedPoints.length) {
//         _markers.removeWhere(
//           (marker) => marker.markerId.value == "live_marker",
//         );
//         mapController?.animateCamera(CameraUpdate.newCameraPosition(
//           CameraPosition(target: visitedPoints[_pointIndex], zoom: 18 // Mumbai
//               ),
//         ));
//         _markers.add(
//           Marker(
//             markerId: const MarkerId('live_marker'),
//             position: visitedPoints[_pointIndex],
//             infoWindow: const InfoWindow(title: 'Moving Point'),
//             icon: customIcon,
//           ),
//         );
//         _visitedPoints.add(visitedPoints[_pointIndex]);
//         _pointIndex++;
//         polylinesMap.add(
//           Polyline(
//             polylineId: const PolylineId('visited_path'),
//             points: List.from(_visitedPoints),
//             color: Colors.red,
//             width: 3,
//           ),
//         );

//         notifyListeners();
//       } else {
//         _markerUpdateTimer
//             ?.cancel(); // Stop the timer when all points are shown
//         _showToast('Movement sequence complete.');
//       }
//     });
//   }


  // @override
  // void dispose() {
  //   _markerUpdateTimer
  //       ?.cancel(); // Cancel the timer when the ViewModel is disposed
  //   super.dispose();
  // }