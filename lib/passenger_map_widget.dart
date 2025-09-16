import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'monitoring_service.dart';

class PassengerMapWidget extends StatelessWidget {
  final Position? passengerLocation;
  final DriverStatus? driverStatus;
  final VoidCallback? onMyLocationPressed;

  const PassengerMapWidget({
    super.key,
    this.passengerLocation,
    this.driverStatus,
    this.onMyLocationPressed,
  });

  Color _getDriverMarkerColor(DriverAlertLevel alertLevel) {
    switch (alertLevel) {
      case DriverAlertLevel.none:
        return Colors.green;
      case DriverAlertLevel.mild:
        return Colors.yellow;
      case DriverAlertLevel.moderate:
        return Colors.orange;
      case DriverAlertLevel.severe:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Default center location (Accra, Ghana)
    LatLng center = const LatLng(5.6037, -0.1870);
    double zoom = 13.0;

    // If passenger location is available, center on it
    if (passengerLocation != null) {
      center = LatLng(passengerLocation!.latitude, passengerLocation!.longitude);
      zoom = 15.0;
    }

    List<Marker> markers = [];

    // Add passenger marker
    if (passengerLocation != null) {
      markers.add(
        Marker(
          width: 40.0,
          height: 40.0,
          point: LatLng(passengerLocation!.latitude, passengerLocation!.longitude),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  spreadRadius: 2,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    // Add driver marker
    if (driverStatus?.location != null) {
      markers.add(
        Marker(
          width: 50.0,
          height: 50.0,
          point: LatLng(
            driverStatus!.location!.latitude, 
            driverStatus!.location!.longitude
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _getDriverMarkerColor(driverStatus!.alertLevel),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  spreadRadius: 2,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );

      // If both locations are available, adjust zoom to show both
      if (passengerLocation != null) {
        // Calculate the center point between passenger and driver
        double centerLat = (passengerLocation!.latitude + driverStatus!.location!.latitude) / 2;
        double centerLng = (passengerLocation!.longitude + driverStatus!.location!.longitude) / 2;
        center = LatLng(centerLat, centerLng);

        // Calculate distance to adjust zoom level
        double distance = Geolocator.distanceBetween(
          passengerLocation!.latitude,
          passengerLocation!.longitude,
          driverStatus!.location!.latitude,
          driverStatus!.location!.longitude,
        );

        // Adjust zoom based on distance
        if (distance > 5000) { // > 5km
          zoom = 12.0;
        } else if (distance > 2000) { // > 2km
          zoom = 13.0;
        } else if (distance > 1000) { // > 1km
          zoom = 14.0;
        } else {
          zoom = 15.0;
        }
      }
    }

    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                minZoom: 10.0,
                maxZoom: 18.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.safe_commute',
                  maxNativeZoom: 18,
                ),
                MarkerLayer(markers: markers),
                if (passengerLocation != null && driverStatus?.location != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          LatLng(passengerLocation!.latitude, passengerLocation!.longitude),
                          LatLng(driverStatus!.location!.latitude, driverStatus!.location!.longitude),
                        ],
                        color: _getDriverMarkerColor(driverStatus!.alertLevel),
                        strokeWidth: 3.0,
                       // isDotted: true,
                      ),
                    ],
                  ),
              ],
            ),
            
            // Map controls
            Positioned(
              top: 10,
              right: 10,
              child: Column(
                children: [
                  // My location button
                  if (onMyLocationPressed != null)
                    FloatingActionButton.small(
                      onPressed: onMyLocationPressed,
                      backgroundColor: Colors.white,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                      ),
                    ),
                  
                  const SizedBox(height: 8),
                  
                  // Map type toggle (could be expanded for satellite view)
                  FloatingActionButton.small(
                    onPressed: () {
                      // Could implement map type switching here
                    },
                    backgroundColor: Colors.white,
                    child: const Icon(
                      Icons.layers,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            
            // Location info overlay
            if (passengerLocation != null || driverStatus?.location != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Passenger location info
                      if (passengerLocation != null)
                        Expanded(
                          child: _buildLocationInfo(
                            icon: Icons.person,
                            color: Colors.blue,
                            title: 'You',
                            subtitle: '${passengerLocation!.accuracy.toInt()}m accuracy',
                          ),
                        ),
                      
                      // Distance info
                      if (passengerLocation != null && driverStatus?.location != null)
                        Expanded(
                          child: _buildLocationInfo(
                            icon: Icons.straighten,
                            color: Colors.white,
                            title: '${_calculateDistance().toStringAsFixed(0)}m',
                            subtitle: 'Distance',
                          ),
                        ),
                      
                      // Driver location info
                      if (driverStatus?.location != null)
                        Expanded(
                          child: _buildLocationInfo(
                            icon: Icons.directions_bus,
                            color: _getDriverMarkerColor(driverStatus!.alertLevel),
                            title: 'Bus ${driverStatus!.busNumber}',
                            subtitle: '${(driverStatus!.location!.speed * 3.6).toInt()} km/h',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInfo({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  double _calculateDistance() {
    if (passengerLocation == null || driverStatus?.location == null) {
      return 0.0;
    }

    return Geolocator.distanceBetween(
      passengerLocation!.latitude,
      passengerLocation!.longitude,
      driverStatus!.location!.latitude,
      driverStatus!.location!.longitude,
    );
  }
}