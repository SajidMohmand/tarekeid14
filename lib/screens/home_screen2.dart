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
  static DateTime? sharedCycleStart;

  TrafficLight({
    required this.position,
  });

  // Updated timing: Horizontal (Warren Ave): Green 60s, Yellow 3s, Red 30s, All-Red 2s
  // Vertical (Miller Rd): Red 60s, Green 30s, Yellow 3s, All-Red 2s
  // Total cycle: 95 seconds
  static TrafficLightState computeStateAt(DateTime now, bool isHorizontal) {
    if (sharedCycleStart == null) {
      sharedCycleStart = DateTime.now();
    }
    final elapsed = now.difference(sharedCycleStart!).inSeconds % 95;

    if (isHorizontal) {
      // Horizontal (Warren Ave)
      if (elapsed < 60) return TrafficLightState.green;  // 0-59: Green
      if (elapsed < 63) return TrafficLightState.yellow; // 60-62: Yellow
      return TrafficLightState.red;                      // 63-94: Red (includes 2s all-red)
    } else {
      // Vertical (Miller Rd)
      if (elapsed < 65) return TrafficLightState.red;    // 0-64: Red (includes 2s all-red at end of horizontal)
      if (elapsed < 95) return TrafficLightState.green;  // 65-94: Green
      return TrafficLightState.red;                      // Should not reach here
    }
  }

  static int secondsUntilGreen(DateTime now, bool isHorizontal) {
    if (sharedCycleStart == null) {
      sharedCycleStart = DateTime.now();
    }
    final elapsed = now.difference(sharedCycleStart!).inSeconds % 95;

    if (isHorizontal) {
      if (elapsed < 63) return 0; // Already green or yellow
      return 95 - elapsed; // Time until next green
    } else {
      if (elapsed < 65) return 65 - elapsed; // Wait for green
      if (elapsed < 95) return 0; // Already green
      return 65; // Next cycle
    }
  }
}

class TrafficLightAnimationScreen extends StatefulWidget {
  final bool isHorizontal;
  final LatLng lightPosition;

  const TrafficLightAnimationScreen({
    Key? key,
    required this.isHorizontal,
    required this.lightPosition,
  }) : super(key: key);

  @override
  _TrafficLightAnimationScreenState createState() => _TrafficLightAnimationScreenState();
}

class _TrafficLightAnimationScreenState extends State<TrafficLightAnimationScreen> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});

      // Auto-close when light turns green
      final now = DateTime.now();
      final state = TrafficLight.computeStateAt(now, widget.isHorizontal);
      if (state == TrafficLightState.green) {
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Widget _buildLight(Color color, bool isOn) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isOn ? color : color.withOpacity(0.3),
        shape: BoxShape.circle,
        boxShadow: isOn ? [
          BoxShadow(
            color: color.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ] : [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final state = TrafficLight.computeStateAt(now, widget.isHorizontal);
    final seconds = TrafficLight.secondsUntilGreen(now, widget.isHorizontal);

    String direction = widget.isHorizontal ? "Warren Ave (Horizontal)" : "Miller Rd (Vertical)";

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Traffic Light",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      direction,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 50),

                    // Traffic Light Display
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          _buildLight(Colors.red, state == TrafficLightState.red),
                          SizedBox(height: 15),
                          _buildLight(Colors.yellow, state == TrafficLightState.yellow),
                          SizedBox(height: 15),
                          _buildLight(Colors.green, state == TrafficLightState.green),
                        ],
                      ),
                    ),

                    SizedBox(height: 40),

                    // Status Display
                    if (state == TrafficLightState.red) ...[
                      Text(
                        'RED LIGHT',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '$seconds seconds until GREEN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ] else if (state == TrafficLightState.yellow) ...[
                      Text(
                        'YELLOW LIGHT',
                        style: TextStyle(
                          color: Colors.yellow,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Prepare to stop',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'GREEN LIGHT',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'You can go!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreenTwoState extends State<HomeScreenTwo> with WidgetsBindingObserver {
  // Google Maps and Location
  GoogleMapController? mapController;
  loc.Location location = loc.Location();
  loc.LocationData? currentLocation;
  StreamSubscription<loc.LocationData>? locationSubscription;
  List<TrafficLight> trafficLights = [];
  int? candidateLightIndex;
  bool? candidateIsHorizontal;

  // Track which lights user has already triggered
  Set<int> triggeredLights = {};

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

  // Google API key
  final String apiKey = 'AIzaSyCmBKt7V3H3xSjfko7Zso7dTI2SOoisQP8';

  // Navigation Controls
  bool navigationActive = false;
  bool isStoppedAtLight = false;
  bool isShowingAnimation = false;
  Timer? _trafficTimer;
  Timer? _navigationTimer;

  // Notifications
  FlutterLocalNotificationsPlugin? _localNotifications;

  // Floating window state
  bool isInPipMode = false;

  // Turn-by-turn
  List<Map<String, dynamic>> routeSteps = [];
  int currentStepIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    try {
      tzdata.initializeTimeZones();
    } catch (e) {
      // Ignore if already initialized
    }

    _localNotifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

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
        print('Notification tapped: ${response.payload}');
      },
    );

    await _requestNotificationPermissions();
  }

  Future<void> _requestNotificationPermissions() async {
    final status = await perm.Permission.notification.request();
    if (status.isDenied) {
      print('Notification permission denied');
    }
  }

  Future<void> _showGreenNotification(String title, String body, DateTime? atTime, int lightIndex) async {
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
      final tzDate = tz.TZDateTime.from(atTime, tz.local);
      await _localNotifications!.zonedSchedule(
        lightIndex,
        title,
        body,
        tzDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );


    } else {
      await _localNotifications!.show(lightIndex, title, body, details);
    }
  }

  // -------------------
  // Traffic light ticker
  // -------------------
  void _startTrafficLightTicker() {
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _updateMarkers();
      });

      // Check for traffic light proximity every second
      _checkTrafficLightProximity();
    });
  }

  // -------------------
  // Location & Map initialization
  // -------------------
  Future<void> _initLocation() async {
    try {
      final permissionStatus = await perm.Permission.location.request();
      if (!permissionStatus.isGranted) {
        setState(() {
          errorMessage = 'Location permission is required to show your position on the map.';
          isLoading = false;
        });
        return;
      }

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

      await location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 5,
      );

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
      _updateCurrentStep();

      if (navigationActive && destination != null) {
        _updateNavigationProgress();
      }
    });
  }

  void _updateMarkers() {
    if (currentLocation == null) return;
    markers.clear();

    markers.add(Marker(
      markerId: const MarkerId('current_location'),
      position: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      infoWindow: InfoWindow(title: widget.name, snippet: 'Your Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));

    if (destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination!,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    final now = DateTime.now();
    for (int i = 0; i < trafficLights.length; i++) {
      final light = trafficLights[i];
      // For marker color, assume horizontal direction
      final lightStateNow = TrafficLight.computeStateAt(now, true);
      markers.add(Marker(
        markerId: MarkerId('traffic_light_$i'),
        position: light.position,
        infoWindow: InfoWindow(
          title: 'Traffic Light ${i + 1}',
          snippet: 'Tap to view details',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          lightStateNow == TrafficLightState.red
              ? BitmapDescriptor.hueRed
              : lightStateNow == TrafficLightState.yellow
              ? BitmapDescriptor.hueOrange
              : BitmapDescriptor.hueGreen,
        ),
      ));
    }

    setState(() {});
  }

  // -------------------
  // Search functionality
  // -------------------
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      isSearching = true;
    });

    try {
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
    if (hasRoute) _fitMapToRoute();
    _openNavigationPanel();
  }

  // -------------------
  // Directions & Route
  // -------------------
  Future<void> _getRoute() async {
    if (currentLocation == null || destination == null) return;

    setState(() {
      errorMessage = null;
    });

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

          final polylinePoints = route['overview_polyline']['points'];
          final coordinates = _decodePolyline(polylinePoints);

          routeDistance = leg['distance']['value'] / 1609.34;
          estimatedTime = leg['duration']['text'];

          routeSteps = List<Map<String, dynamic>>.from(leg['steps']);
          currentStepIndex = 0;

          setState(() {
            polylines.clear();
            polylines.add(Polyline(
              polylineId: const PolylineId('route'),
              points: coordinates,
              color: const Color(0xFF4285F4),
              width: 5,
              geodesic: true,
              patterns: [],
            ));
            hasRoute = true;
          });

          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _fitMapToRoute();
          });
        } else {
          setState(() {
            polylines.clear();
            hasRoute = false;
            routeDistance = 0.0;
            estimatedTime = '';
            errorMessage = 'No route found. Please try a different destination.';
          });
        }
      } else {
        setState(() {
          polylines.clear();
          hasRoute = false;
          routeDistance = 0.0;
          estimatedTime = '';
          errorMessage = 'Failed to fetch route. Please check your network or API key.';
        });
      }
    } catch (e) {
      print('Route failed: $e');
      setState(() {
        polylines.clear();
        hasRoute = false;
        routeDistance = 0.0;
        estimatedTime = '';
        errorMessage = 'Error fetching route: $e';
      });
    }
  }

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
    ) / 1609.34;
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
      routeSteps = [];
      currentStepIndex = -1;
      triggeredLights.clear();
    });
    _stopNavigation();
  }

  Future<void> _startNavigation() async {
    if (destination == null) return;

    setState(() {
      navigationActive = true;
      triggeredLights.clear();
    });

    _navigationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateNavigationProgress();
    });

    _checkTrafficLightProximity();
  }

  void _stopNavigation() {
    _navigationTimer?.cancel();
    setState(() {
      navigationActive = false;
      triggeredLights.clear();
    });
  }

  void _updateNavigationProgress() {
    if (currentLocation != null && destination != null) {
      _getRoute();
      _checkTrafficLightProximity();
    }
  }

  void _updateCurrentStep() {
    if (routeSteps.isEmpty || currentStepIndex >= routeSteps.length || currentLocation == null) return;

    final currentStep = routeSteps[currentStepIndex];
    final endLat = currentStep['end_location']['lat'] as double;
    final endLng = currentStep['end_location']['lng'] as double;

    final distance = Geolocator.distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      endLat,
      endLng,
    );

    if (distance < 50) {
      currentStepIndex++;
      if (currentStepIndex >= routeSteps.length) {
        _stopNavigation();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You have arrived!')));
      }
    }
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>', multiLine: true), '');
  }

  // -------------------
  // Traffic Light Logic - ENHANCED
  // -------------------
  DateTime? _candidateGreenTime;
  TrafficLight? _candidateGreenLight;

  bool _determineDirection(double heading) {
    // Normalize heading to 0-360
    double normalizedHeading = heading % 360;
    if (normalizedHeading < 0) normalizedHeading += 360;

    // Horizontal: East (45-135°) or West (225-315°)
    // Vertical: North (315-45°) or South (135-225°)
    return (normalizedHeading >= 45 && normalizedHeading < 135) ||
        (normalizedHeading >= 225 && normalizedHeading < 315);
  }

  void _checkTrafficLightProximity() {
    if (currentLocation == null) return;

    final now = DateTime.now();
    const detectionRadius = 50.0; // meters

    for (int i = 0; i < trafficLights.length; i++) {
      // Skip if already triggered this light
      if (triggeredLights.contains(i)) continue;

      final light = trafficLights[i];
      final distanceToLight = Geolocator.distanceBetween(
        currentLocation!.latitude!,
        currentLocation!.longitude!,
        light.position.latitude,
        light.position.longitude,
      );

      // Check if user is within detection radius
      if (distanceToLight <= detectionRadius) {
        // Determine direction based on heading
        double heading = currentLocation?.heading ?? 0.0;
        bool isHorizontal = _determineDirection(heading);

        final lightState = TrafficLight.computeStateAt(now, isHorizontal);

        setState(() {
          candidateLightIndex = i;
          candidateIsHorizontal = isHorizontal;
          _candidateGreenLight = light;
        });

        // If light is red, show animation and mark as triggered
        if (lightState == TrafficLightState.red && !isShowingAnimation) {
          triggeredLights.add(i); // Mark this light as triggered

          final secondsUntilGreen = TrafficLight.secondsUntilGreen(now, isHorizontal);
          final greenAt = now.add(Duration(seconds: secondsUntilGreen));
          _candidateGreenTime = greenAt;

          // Show animation overlay
          _showTrafficLightAnimation(light.position, isHorizontal);

          // Schedule notification for when light turns green
          _showGreenNotification(
            'Traffic Light Alert 🚦',
            'The light will turn green in $secondsUntilGreen seconds!',
            greenAt,
            i,
          );
        }

        break; // Handle only the closest light
      } else {
        // User moved away from this light, allow re-trigger
        if (distanceToLight > detectionRadius * 2) {
          triggeredLights.remove(i);
        }
      }
    }
  }

  void _showTrafficLightAnimation(LatLng lightPosition, bool isHorizontal) {
    if (isShowingAnimation) return;

    setState(() {
      isShowingAnimation = true;
      isStoppedAtLight = true;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrafficLightAnimationScreen(
          isHorizontal: isHorizontal,
          lightPosition: lightPosition,
        ),
      ),
    ).then((_) {
      setState(() {
        isShowingAnimation = false;
        isStoppedAtLight = false;
      });
    });
  }

  void _userStoppedAtLight(bool stopped) {
    setState(() {
      isStoppedAtLight = stopped;
    });

    if (!stopped) {
      _candidateGreenTime = null;
      _candidateGreenLight = null;
      candidateLightIndex = null;
    }
  }

  // -------------------
  // App Lifecycle Management
  // -------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (navigationActive && isStoppedAtLight && _candidateGreenTime != null) {
        _showGreenNotification(
          'Traffic Light Alert 🚦',
          'The light has turned green! You can continue driving.',
          _candidateGreenTime!,
          candidateLightIndex!,
        );
        print('Green light notification scheduled for ${_candidateGreenTime!}');
      }

      _enterFloatingMode();
    } else if (state == AppLifecycleState.resumed) {
      _exitFloatingMode();
    }
  }

  // -------------------
  // Floating Window/PiP Mode
  // -------------------
  void _enterFloatingMode() {
    if (navigationActive) {
      setState(() {
        isInPipMode = true;
      });
      print('Entered floating window mode (simulated)');
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
  void _useMockLocation() {
    setState(() {
      currentLocation = loc.LocationData.fromMap({
        'latitude': 31.5205,
        'longitude': 74.3588,
        'accuracy': 5.0,
        'altitude': 0.0,
        'speed': 0.0,
        'speedAccuracy': 0.0,
        'heading': 90.0, // East heading (horizontal)
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
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && hasRoute) _fitMapToRoute();
              });
            },
            onLongPress: (LatLng position) {
              setState(() {
                trafficLights.removeWhere((light) =>
                (light.position.latitude - position.latitude).abs() < 0.0001 &&
                    (light.position.longitude - position.longitude).abs() < 0.0001);
              });
              _updateMarkers();
            },
            onTap: (LatLng position) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Map Action'),
                  content: const Text('Do you want to add a traffic light or set this as destination?'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          final newLight = TrafficLight(
                            position: position,
                          );
                          trafficLights.add(newLight);
                        });
                        _updateMarkers();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Traffic light added! Drive near it to see the animation.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                      child: const Text('Add Traffic Light'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          destination = position;
                          _searchController.text = 'Custom Location';
                        });
                        _updateMarkers();
                        _getRoute();
                        if (hasRoute) _fitMapToRoute();
                        _openNavigationPanel();
                        Navigator.pop(context);
                      },
                      child: const Text('Set Destination'),
                    ),
                  ],
                ),
              );
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
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Text(
                                          '${_calculateDistance().toStringAsFixed(1)} miles',
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
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
                                          Flexible(
                                            child: Text(
                                              'ETA: $estimatedTime',
                                              style: const TextStyle(fontSize: 11, color: Colors.blue),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

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

          // Turn-by-turn instruction
          if (navigationActive && currentStepIndex >= 0 && currentStepIndex < routeSteps.length)
            Positioned(
              top: 200,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.blue[50],
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.turn_right, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _stripHtml(routeSteps[currentStepIndex]['html_instructions'] ?? ''),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Traffic light status indicator
          if (isStoppedAtLight && candidateLightIndex != null)
            Positioned(
              top: 260,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.red[50],
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.traffic, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stopped at traffic light - ${candidateIsHorizontal! ? "Warren Ave" : "Miller Rd"}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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

          if (hasRoute)
            FloatingActionButton.small(
              heroTag: 'fit_route',
              onPressed: _fitMapToRoute,
              backgroundColor: Colors.white,
              child: const Icon(Icons.zoom_out_map, color: Color(0xFF008080)),
            ),
          if (hasRoute) const SizedBox(height: 8),

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

          Row(
            children: [
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

          Row(
            children: [
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

          if (trafficLights.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${trafficLights.length} traffic light(s) on map',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  void _showMapInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigation Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✅ Live Location Tracking'),
              const Text('✅ Google Maps Integration'),
              const Text('✅ Address Search'),
              const Text('✅ Turn-by-turn Directions'),
              const Text('✅ Auto Traffic Light Detection'),
              const Text('✅ Background Notifications'),
              const SizedBox(height: 10),
              const Text('Traffic Light Timing:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('• Warren Ave (Horizontal): 60s Green, 3s Yellow, 30s Red'),
              const Text('• Miller Rd (Vertical): 30s Green, 3s Yellow, 60s Red'),
              const Text('• 2s All-Red transition'),
              const SizedBox(height: 10),
              const Text('How to use:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('1. Tap map to add traffic lights'),
              const Text('2. Drive within 50m to trigger animation'),
              const Text('3. Direction detected automatically'),
              const SizedBox(height: 10),
              Text('Map Type: ${currentMapType.name}'),
            ],
          ),
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