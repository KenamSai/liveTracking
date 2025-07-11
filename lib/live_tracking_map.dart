import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:live_tracking/live_track_view_model.dart';
import 'package:provider/provider.dart';

class LiveTrackingMapBasic extends StatelessWidget {
  const LiveTrackingMapBasic({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LiveTrackViewModel>(
      create: (_) => LiveTrackViewModel(),
      child: const LiveTrackingMap(),
    );
  }
}

class LiveTrackingMap extends StatefulWidget {
  const LiveTrackingMap({super.key});

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap> {
  late LiveTrackViewModel liveTrackViewModel;

  @override
  void initState() {
    super.initState();
    liveTrackViewModel =
        Provider.of<LiveTrackViewModel>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) async {
        await liveTrackViewModel.checkLocationPermissionAndGPS();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    liveTrackViewModel = Provider.of<LiveTrackViewModel>(context);
    return Scaffold(
      body: liveTrackViewModel.visitedPoints.isNotEmpty
          ? GoogleMap(
              onMapCreated: liveTrackViewModel.onMapCreated,
              initialCameraPosition: CameraPosition(
                target: liveTrackViewModel.visitedPoints.last,
                zoom: 14,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              markers: liveTrackViewModel.markersMap,
              polylines: liveTrackViewModel.polylinesMap,
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}
