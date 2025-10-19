// lib/screens/home_screen2.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin, max, min;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:geolocator/geolocator.dart';

class HomeScreenTwo extends StatefulWidget {
  final String name;
  final String vehicle;
  const HomeScreenTwo({
    Key? key,
    required this.name,
    required this.vehicle,
  }) : super(key: key);

  @override
  State<HomeScreenTwo> createState() => _HomeScreenTwoState();
}

enum TrafficLightState { red, yellow, green }

class TrafficLight {
  final LatLng position;
  TrafficLightState state;
  // durations in seconds
  int redDuration;
  int yellowDuration;
  int greenDuration;
  DateTime? cycleStart; // time when cycle started (for scheduling)

  TrafficLight({
    required this.position,
    this.state = TrafficLightState.red,
    this.redDuration = 10,
    this.yellowDuration = 3,
    this.greenDuration = 8,
  });

  // total cycle length
  int get totalSeconds => redDuration + yellowDuration + greenDuration;

  // given a DateTime now, compute how many seconds until it becomes green
  int secondsUntilGreen(DateTime now) {
    if (cycleStart == null) {
      // assume started now with current state as red
      return redDuration;
    }
    final elapsed = now.difference(cycleStart!).inSeconds % totalSeconds;
    // cycle order: red -> yellow -> green
    if (elapsed < redDuration) {
      // still in red
      return redDuration - elapsed;
    } else if (elapsed < redDuration + yellowDuration) {
      // in yellow, next green after yellow part
      return redDuration + yellowDuration - elapsed;
    } else {
      // currently green, returns 0
      return 0;
    }
  }

  TrafficLightState computeStateAt(DateTime now) {
    if (cycleStart == null) {
      return state;
    }
    final elapsed = now.difference(cycleStart!).inSeconds % totalSeconds;
    if (elapsed < redDuration) return TrafficLightState.red;
    if (elapsed < redDuration + yellowDuration) return TrafficLightState.yellow;
    return TrafficLightState.green;
  }

  // advance simulated state by updating cycleStart so that computeStateAt(now) changes over time
  void startCycleNow() {
    cycleStart = DateTime.now();
  }
}

class _HomeScreenTwoState extends State<HomeScreenTwo> with WidgetsBindingObserver {
  // Google Maps and Location
  GoogleMapController? mapController;
  loc.Location location = loc.Location();
  loc.LocationData? currentLocation;
  StreamSubscription<loc.LocationData>? locationSubscription;
  
  // Destination and Route
  LatLng? destination;
  final Set<Polyline> polylines = {};
  final Set<Marker> markers = {};
  bool isLoading = true;
  String? errorMessage;
  bool hasRoute = false;
  MapType currentMapType = MapType.normal;
  
  // ETA and Distance
  String estimatedTime = '';
  double routeDistance = 0.0;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool isSearching = false;

  // Google API key - IMPORTANT: Replace with your own key and keep it secure
  final String apiKey = 'AIzaSyCmBKt7V3H3xSjfko7Zso7dTI2SOoisQP8';

  // Traffic light simulation - sample intersection coordinate provided
  // Coordinates: 42°20'39.3"N 83°10'01.4"W -> 42.34425, -83.167056
  late TrafficLight sampleLight;

  // Navigation Controls
  bool navigationActive = false;
  bool isStoppedAtLight = false; // simulate whether user is currently stopped
  Timer? _trafficTimer; // updates UI for traffic light animation
  Timer? _navigationTimer; // updates navigation progress
  
  // Notifications
  FlutterLocalNotificationsPlugin? _localNotifications;
  
  // Floating window state
  bool isInPipMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize sample traffic light at provided coordinates
    sampleLight = TrafficLight(
      position: const LatLng(42.34425, -83.167056),
      state: TrafficLightState.red,
      redDuration: 12,
      yellowDuration: 3,
      greenDuration: 10,
    );
    sampleLight.startCycleNow();

    _initNotifications();
    _initLocation();
    _startTrafficLightTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    locationSubscription?.cancel();
    mapController?.dispose();
    _trafficTimer?.cancel();
    _navigationTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------
  // Notifications setup
  // -------------------
  Future<void> _initNotifications() async {
    // Initialize timezone data
    try {
      tzdata.initializeTimeZones();
    } catch (e) {
      // Ignore if already initialized
    }

    _localNotifications = FlutterLocalNotificationsPlugin();
    
    // Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS settings
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap if needed
        print('Notification tapped: ${response.payload}');
      },
    );

    // Request notification permissions
    await _requestNotificationPermissions();
  }

  Future<void> _requestNotificationPermissions() async {
    final status = await perm.Permission.notification.request();
    if (status.isDenied) {
      print('Notification permission denied');
    }
  }

  Future<void> _showGreenNotification(String title, String body, DateTime? atTime) async {
    const androidDetails = AndroidNotificationDetails(
      'traffic_channel',
      'Traffic Lights',
      channelDescription: 'Notifications for traffic light changes',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      ticker: 'Traffic Light Alert',
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      sound: 'default',
    );
    
    const details = NotificationDetails(
      android: androidDetails, 
      iOS: iosDetails,
    );

    if (atTime != null && atTime.isAfter(DateTime.now())) {
      // Schedule notification
      final tzDate = tz.TZDateTime.from(atTime, tz.local);
      await _localNotifications!.zonedSchedule(
        0,
        title,
        body,
        tzDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } else {
      // Show immediately
      await _localNotifications!.show(0, title, body, details);
    }
  }

  // -------------------
  // Traffic light ticker
  // -------------------
  void _startTrafficLightTicker() {
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        // Update UI for traffic light state changes
        _updateMarkers();
      });
    });
  }

  // -------------------
  // Location & Map initialization
  // -------------------
  Future<void> _initLocation() async {
    try {
      // Request location permissions
      final permissionStatus = await perm.Permission.location.request();
      if (!permissionStatus.isGranted) {
        setState(() {
          errorMessage = 'Location permission is required to show your position on the map.';
          isLoading = false;
        });
        return;
      }

      // Check if location service is enabled
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          setState(() {
            errorMessage = 'GPS service is disabled. Please enable location services.';
            isLoading = false;
          });
          return;
        }
      }

      // Configure location settings for high accuracy
      await location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 5,
      );

      // Get current location
      currentLocation = await location.getLocation();
      _updateMarkers();
      _startLocationUpdates();
      
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error getting location: $e';
      });
    }
  }

  void _startLocationUpdates() {
    locationSubscription = location.onLocationChanged.listen((loc.LocationData locData) {
      if (!mounted) return;
      setState(() {
        currentLocation = locData;
      });
      _updateMarkers();
      
      // Update route if navigation is active
      if (navigationActive && destination != null) {
        _updateNavigationProgress();
      }
    });
  }

  void _updateMarkers() {
    if (currentLocation == null) return;
    markers.clear();

    // Current location marker (blue dot)
    markers.add(Marker(
      markerId: const MarkerId('current_location'),
      position: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      infoWindow: InfoWindow(title: widget.name, snippet: 'Your Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));

    // Destination marker
    if (destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination!,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    // Sample traffic light marker with dynamic color
    final now = DateTime.now();
    final lightStateNow = sampleLight.computeStateAt(now);
    markers.add(Marker(
      markerId: const MarkerId('traffic_sample'),
      position: sampleLight.position,
      infoWindow: InfoWindow(
        title: 'Traffic Light',
        snippet: 'State: ${lightStateNow.name.toUpperCase()}',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        lightStateNow == TrafficLightState.red
            ? BitmapDescriptor.hueRed
            : lightStateNow == TrafficLightState.yellow
            ? BitmapDescriptor.hueOrange
            : BitmapDescriptor.hueGreen,
      ),
    ));

    setState(() {});
  }

  // -------------------
  // Search functionality using Google Places/Geocoding API
  // -------------------
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    
    setState(() {
      isSearching = true;
    });

    try {
      // Use Google Geocoding API for address search
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$apiKey'
      );
      
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK') {
          final results = (data['results'] as List).map((result) {
            return {
              'formatted_address': result['formatted_address'],
              'lat': result['geometry']['location']['lat'],
              'lng': result['geometry']['location']['lng'],
              'place_id': result['place_id'],
            };
          }).toList();
          
          setState(() {
            _searchResults = List<Map<String, dynamic>>.from(results);
            isSearching = false;
          });
        } else {
          setState(() {
            _searchResults = [];
            isSearching = false;
          });
        }
      }
    } catch (e) {
      print('Search failed: $e');
      setState(() {
        isSearching = false;
        _searchResults = [];
      });
    }
  }

  // Set destination from search result
  Future<void> _setDestinationFromSearch(Map<String, dynamic> item) async {
    final lat = (item['lat'] as num).toDouble();
    final lng = (item['lng'] as num).toDouble();
    
    setState(() {
      destination = LatLng(lat, lng);
      _searchResults = [];
      _searchController.text = item['formatted_address'];
    });
    
    _updateMarkers();
    await _getRoute();
    _openNavigationPanel();
  }

  // -------------------
  // Directions & Route using Google Directions API
  // -------------------
  Future<void> _getRoute() async {
    if (currentLocation == null || destination == null) return;
    
    try {
      final String origin = '${currentLocation!.latitude},${currentLocation!.longitude}';
      final String dest = '${destination!.latitude},${destination!.longitude}';
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$dest&key=$apiKey'
      );
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          // Extract route information
          final polylinePoints = route['overview_polyline']['points'];
          final coordinates = _decodePolyline(polylinePoints);
          
          // Get distance and duration
          routeDistance = leg['distance']['value'] / 1609.34; // Convert meters to miles
          estimatedTime = leg['duration']['text'];
          
          setState(() {
            polylines.clear();
            polylines.add(Polyline(
              polylineId: const PolylineId('route'),
              points: coordinates,
              color: const Color(0xFF4285F4),
              width: 5,
              geodesic: true,
              patterns: [], // Solid line
            ));
            hasRoute = true;
          });
          
          // Auto-fit map to show route
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _fitMapToRoute();
          });
        }
      }
    } catch (e) {
      print('Route failed: $e');
    }
  }

  // Decode Google polyline algorithm
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  double _calculateDistance() {
    if (currentLocation == null || destination == null) return 0.0;
    return routeDistance > 0 ? routeDistance : _calculateDirectDistance();
  }

  double _calculateDirectDistance() {
    if (currentLocation == null || destination == null) return 0.0;
    
    return Geolocator.distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      destination!.latitude,
      destination!.longitude,
    ) / 1609.34; // Convert meters to miles
  }

  void _fitMapToRoute() {
    if (mapController == null || currentLocation == null || destination == null) return;
    
    double minLat = min(currentLocation!.latitude!, destination!.latitude);
    double maxLat = max(currentLocation!.latitude!, destination!.latitude);
    double minLng = min(currentLocation!.longitude!, destination!.longitude);
    double maxLng = max(currentLocation!.longitude!, destination!.longitude);

    double latPadding = (maxLat - minLat) * 0.20;
    double lngPadding = (maxLng - minLng) * 0.20;
    
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );
    
    mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _centerOnCurrentLocation() {
    if (mapController == null || currentLocation == null) return;
    
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
          zoom: 18,
          tilt: 45,
          bearing: 0,
        ),
      ),
    );
  }

  // -------------------
  // Navigation functionality
  // -------------------
  void _openNavigationPanel() {
    setState(() {
      navigationActive = true;
    });
  }

  void _closeNavigationPanel() {
    setState(() {
      navigationActive = false;
      polylines.clear();
      destination = null;
      hasRoute = false;
      estimatedTime = '';
      routeDistance = 0.0;
      _searchController.clear();
    });
    _stopNavigation();
  }

  Future<void> _startNavigation() async {
    if (destination == null) return;
    
    setState(() {
      navigationActive = true;
    });

    // Start navigation timer for updates
    _navigationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateNavigationProgress();
    });

    // Check if near traffic light and schedule notification if needed
    _checkTrafficLightProximity();
  }

  void _stopNavigation() {
    _navigationTimer?.cancel();
    setState(() {
      navigationActive = false;
      _candidateGreenTime = null;
      _candidateGreenLight = null;
    });
  }

  void _updateNavigationProgress() {
    if (currentLocation != null && destination != null) {
      // Recalculate route with current position
      _getRoute();
      
      // Check traffic light proximity
      _checkTrafficLightProximity();
    }
  }

  // -------------------
  // Traffic Light Logic
  // -------------------
  DateTime? _candidateGreenTime;
  TrafficLight? _candidateGreenLight;

  void _checkTrafficLightProximity() {
    if (currentLocation == null) return;
    
    final now = DateTime.now();
    final lightState = sampleLight.computeStateAt(now);
    final distanceToLight = Geolocator.distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      sampleLight.position.latitude,
      sampleLight.position.longitude,
    ); // meters

    const stopThresholdMeters = 50.0; // Within 50m considered "at light"
    
    if (distanceToLight <= stopThresholdMeters && lightState == TrafficLightState.red) {
      // User is near red light - prepare notification
      final secondsUntilGreen = sampleLight.secondsUntilGreen(now);
      final greenAt = now.add(Duration(seconds: secondsUntilGreen));
      
      _candidateGreenTime = greenAt;
      _candidateGreenLight = sampleLight;
      
      // Auto-mark as stopped if very close
      if (distanceToLight <= 20.0 && !isStoppedAtLight) {
        setState(() {
          isStoppedAtLight = true;
        });
      }
    } else {
      _candidateGreenTime = null;
      _candidateGreenLight = null;
      
      if (isStoppedAtLight) {
        setState(() {
          isStoppedAtLight = false;
        });
      }
    }
  }

  void _userStoppedAtLight(bool stopped) {
    setState(() {
      isStoppedAtLight = stopped;
    });
    
    if (!stopped) {
      _candidateGreenTime = null;
      _candidateGreenLight = null;
    }
  }

  // -------------------
  // App Lifecycle Management for Notifications
  // -------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // App moved to background
      if (navigationActive && isStoppedAtLight && _candidateGreenTime != null) {
        _showGreenNotification(
          'Traffic Light Alert 🚦',
          'The light has turned green! You can continue driving.',
          _candidateGreenTime!,
        );
        print('Green light notification scheduled for ${_candidateGreenTime!}');
      }
      
      // Simulate floating window mode
      _enterFloatingMode();
    } else if (state == AppLifecycleState.resumed) {
      // App returned to foreground
      _exitFloatingMode();
    }
  }

  // -------------------
  // Floating Window/PiP Mode Simulation
  // -------------------
  void _enterFloatingMode() {
    if (navigationActive) {
      setState(() {
        isInPipMode = true;
      });
      print('Entered floating window mode (simulated)');
      // In a real app, you would use flutter_pip_mode or system_alert_window here
    }
  }

  void _exitFloatingMode() {
    setState(() {
      isInPipMode = false;
    });
    print('Exited floating window mode');
  }

  // -------------------
  // Helper Methods
  // -------------------
  bool _isNearSampleLight() {
    if (currentLocation == null) return false;
    
    final distanceMeters = Geolocator.distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      sampleLight.position.latitude,
      sampleLight.position.longitude,
    );
    
    return distanceMeters <= 200; // Within 200 meters
  }

  bool _isLightRedNow() {
    return sampleLight.computeStateAt(DateTime.now()) == TrafficLightState.red;
  }

  void _useMockLocation() {
    // Use a location near the sample traffic light for testing
    setState(() {
      currentLocation = loc.LocationData.fromMap({
        'latitude': 42.3443, // Close to traffic light
        'longitude': -83.1671,
        'accuracy': 5.0,
        'altitude': 0.0,
        'speed': 0.0,
        'speedAccuracy': 0.0,
        'heading': 0.0,
        'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
    });
    _updateMarkers();
    if (destination != null) {
      _getRoute();
    }
  }

  // -------------------
  // UI Build Method
  // -------------------
  @override
  Widget build(BuildContext context) {
    // Error state
    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Location Error'),
          backgroundColor: const Color(0xFF008080),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Location Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      errorMessage = null;
                      isLoading = true;
                    });
                    _initLocation();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF008080),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading state
    if (isLoading || currentLocation == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading Map'),
          backgroundColor: const Color(0xFF008080),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF008080)),
              SizedBox(height: 16),
              Text('Getting your location...'),
            ],
          ),
        ),
      );
    }

    // Main map interface
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.name}'s Navigation"),
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
        actions: [
          if (isInPipMode)
            const Icon(Icons.picture_in_picture_alt, color: Colors.orange),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showMapInfo(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
              // Auto-fit route after map is ready
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && hasRoute) _fitMapToRoute();
              });
            },
            initialCameraPosition: CameraPosition(
              target: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
              zoom: 17.5,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomGesturesEnabled: true,
            tiltGesturesEnabled: true,
            compassEnabled: true,
            trafficEnabled: true,
            mapType: currentMapType,
            padding: EdgeInsets.only(
              top: 140,
              bottom: navigationActive ? 240 : 80,
            ),
            minMaxZoomPreference: const MinMaxZoomPreference(10, 20),
          ),

          // Search bar and info card
          Positioned(
            top: 16,
            left: 12,
            right: 12,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // Vehicle info row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF008080).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.directions_car, color: Color(0xFF008080)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.vehicle,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.navigation, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_calculateDistance().toStringAsFixed(1)} miles',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (hasRoute) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Route active',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                  if (estimatedTime.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'ETA: $estimatedTime',
                                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Search bar
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search destination address...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              suffixIcon: isSearching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.search),
                                      onPressed: () => _performSearch(_searchController.text),
                                    ),
                            ),
                            onSubmitted: (value) => _performSearch(value),
                            onChanged: (value) {
                              if (value.length > 2) {
                                // Auto-search as user types
                                Future.delayed(const Duration(milliseconds: 500), () {
                                  if (_searchController.text == value) {
                                    _performSearch(value);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'center_location',
                          onPressed: _centerOnCurrentLocation,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.my_location, color: Color(0xFF008080)),
                        ),
                      ],
                    ),

                    // Search results dropdown
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, color: Color(0xFF008080)),
                              title: Text(
                                result['formatted_address'],
                                style: const TextStyle(fontSize: 14),
                              ),
                              onTap: () => _setDestinationFromSearch(result),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Traffic light countdown overlay
          if (navigationActive && _isNearSampleLight() && _isLightRedNow() && isStoppedAtLight)
            Positioned(
              bottom: navigationActive ? 280 : 120,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.black.withOpacity(0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.traffic, color: Colors.red, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'RED LIGHT - ${sampleLight.secondsUntilGreen(DateTime.now())}s until GREEN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Navigation panel
          if (navigationActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildNavigationPanel(),
            ),
        ],
      ),

      // Floating action buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Map type toggle
          FloatingActionButton.small(
            heroTag: 'map_type',
            onPressed: () {
              setState(() {
                switch (currentMapType) {
                  case MapType.normal:
                    currentMapType = MapType.satellite;
                    break;
                  case MapType.satellite:
                    currentMapType = MapType.hybrid;
                    break;
                  case MapType.hybrid:
                    currentMapType = MapType.normal;
                    break;
                  default:
                    currentMapType = MapType.normal;
                }
              });
            },
            backgroundColor: Colors.white,
            child: Icon(
              currentMapType == MapType.normal
                  ? Icons.layers
                  : currentMapType == MapType.satellite
                      ? Icons.satellite_alt
                      : Icons.map,
              color: const Color(0xFF008080),
            ),
          ),
          const SizedBox(height: 8),
          
          // Fit route to screen
          if (hasRoute)
            FloatingActionButton.small(
              heroTag: 'fit_route',
              onPressed: _fitMapToRoute,
              backgroundColor: Colors.white,
              child: const Icon(Icons.zoom_out_map, color: Color(0xFF008080)),
            ),
          if (hasRoute) const SizedBox(height: 8),
          
          // Center on current location
          FloatingActionButton(
            heroTag: 'center_main',
            onPressed: _centerOnCurrentLocation,
            backgroundColor: const Color(0xFF008080),
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // Navigation panel widget
  Widget _buildNavigationPanel() {
    final distance = _calculateDistance();
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black26,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  destination != null ? 'Navigation Active' : 'No Destination',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _closeNavigationPanel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Destination info
          if (destination != null) ...[
            Row(
              children: [
                const Icon(Icons.place, color: Color(0xFF008080)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _searchController.text.isNotEmpty 
                        ? _searchController.text 
                        : 'Selected destination',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Distance and time info
            Row(
              children: [
                const Icon(Icons.straighten, size: 16),
                const SizedBox(width: 4),
                Text('${distance.toStringAsFixed(1)} miles'),
                const SizedBox(width: 16),
                if (estimatedTime.isNotEmpty) ...[
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 4),
                  Text(estimatedTime),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          
          // Control buttons
          Row(
            children: [
              // Start/Stop Navigation
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasRoute
                      ? () {
                          if (navigationActive) {
                            _stopNavigation();
                          } else {
                            _startNavigation();
                          }
                        }
                      : null,
                  icon: Icon(navigationActive ? Icons.stop : Icons.navigation),
                  label: Text(navigationActive ? 'Stop Navigation' : 'Start Navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navigationActive ? Colors.red : const Color(0xFF008080),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Debug controls (for testing)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _userStoppedAtLight(!isStoppedAtLight),
                  icon: Icon(isStoppedAtLight ? Icons.play_arrow : Icons.pause),
                  label: Text(isStoppedAtLight ? 'Mark Moving' : 'Mark Stopped'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _useMockLocation,
                  icon: const Icon(Icons.location_searching),
                  label: const Text('Test Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Map info dialog
  void _showMapInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigation Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✅ Live Location Tracking'),
            const Text('✅ Google Maps Integration'),
            const Text('✅ Address Search'),
            const Text('✅ Turn-by-turn Directions'),
            const Text('✅ Traffic Light Simulation'),
            const Text('✅ Background Notifications'),
            Text('Map Type: ${currentMapType.name}'),
            const SizedBox(height: 10),
            const Text(
              'Note: For full background notifications and floating window features, test on a real device.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}