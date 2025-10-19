// lib/screens/home_screen2.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin, max, min;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

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
  GoogleMapController? mapController;
  loc.Location location = loc.Location();
  loc.LocationData? currentLocation;
  StreamSubscription<loc.LocationData>? locationSubscription;

  // Destination (initially Ford, same as your original)
  LatLng? destination;
  final Set<Polyline> polylines = {};
  final Set<Marker> markers = {};
  bool isLoading = true;
  String? errorMessage;
  bool hasRoute = false;
  MapType currentMapType = MapType.normal;

  // Search
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  // Google API key - IMPORTANT: replace with your own key and keep it secure.
  final String apiKey = 'AIzaSyCmBKt7V3H3xSjfko7Zso7dTI2SOoisQP8';

  // Traffic light simulation - sample intersection coordinate provided
  // Coordinates decimal: 42°20'39.3"N 83°10'01.4"W -> 42.34425, -83.167056
  late TrafficLight sampleLight;

  // Controls / Navigation
  bool navigationActive = false;
  bool isStoppedAtLight = false; // simulate whether user is currently stopped
  Timer? _trafficTimer; // updates UI for traffic light animation
  FlutterLocalNotificationsPlugin? _localNotifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    _searchController.dispose();
    super.dispose();
  }

  // -------------------
  // Notifications setup
  // -------------------
  Future<void> _initNotifications() async {
    // Ensure timezone database is initialized before scheduling
    try {
      tzdata.initializeTimeZones();
    } catch (e) {
      // ignore if already initialized
    }

    _localNotifications = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(initSettings,
        onDidReceiveNotificationResponse: (response) {
          // handle notification tap if needed
        });
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> _showGreenNotification(String title, String body, DateTime atTime) async {
    // Schedule a notification at atTime (if in the future), otherwise show immediately
    final androidDetails = AndroidNotificationDetails(
      'traffic_channel',
      'Traffic Lights',
      channelDescription: 'Notifications for traffic light changes',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      ticker: 'ticker',
    );
    final iosDetails = DarwinNotificationDetails(presentSound: true);
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final now = DateTime.now();
    if (atTime.isAfter(now)) {
      final scheduledDate = atTime;

      // Ensure timezone package available
      // tzdata.initializeTimeZones(); // already called in _initNotifications; safe to call again
      final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        'Reminder',
        'This is your test notification',
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'channel_id',
            'channel_name',
            channelDescription: 'channel_description',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } else {
      await _localNotifications!.show(0, title, body, details);
    }
  }

  // -------------------
  // Traffic light ticker
  // -------------------
  void _startTrafficLightTicker() {
    _trafficTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        // Nothing heavy; UI will query sampleLight.computeStateAt(DateTime.now())
      });
    });
  }

  // -------------------
  // Location & Map init
  // -------------------
  Future<void> _initLocation() async {
    try {
      // ask permissions explicitly using permission_handler
      final perm.PermissionStatus permissionStatus = await perm.Permission.location.request();
      if (!permissionStatus.isGranted) {
        setState(() {
          errorMessage = 'Location permission is required.';
          isLoading = false;
        });
        return;
      }

      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          setState(() {
            errorMessage = 'GPS service disabled.';
            isLoading = false;
          });
          return;
        }
      }

      await location.changeSettings(accuracy: loc.LocationAccuracy.high, interval: 1000);
      currentLocation = await location.getLocation();
      _updateMarkers();
      _startLocationUpdates();
      _getRoute(); // optional: fetch route to default dest if you set one
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
    });
  }

  void _updateMarkers() {
    if (currentLocation == null) return;
    markers.clear();

    // user marker
    markers.add(Marker(
      markerId: MarkerId('me'),
      position: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      infoWindow: InfoWindow(title: widget.name, snippet: 'Your Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));

    // destination marker
    if (destination != null) {
      markers.add(Marker(
        markerId: MarkerId('destination'),
        position: destination!,
        infoWindow: InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    // sample traffic light marker
    final now = DateTime.now();
    final lightStateNow = sampleLight.computeStateAt(now);
    markers.add(Marker(
      markerId: MarkerId('traffic_sample'),
      position: sampleLight.position,
      infoWindow: InfoWindow(title: 'Traffic Light (sample)'),
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
  // Search (Simple geocode)
  // -------------------
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$apiKey');
    try {
      final resp = await http.get(url).timeout(Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final results = (data['results'] as List).map((r) {
          return {
            'formatted_address': r['formatted_address'],
            'lat': r['geometry']['location']['lat'],
            'lng': r['geometry']['location']['lng'],
          };
        }).toList();
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(results);
        });
      }
    } catch (e) {
      print('Search failed: $e');
    }
  }

  // user taps search result -> set destination
  Future<void> _setDestinationFromSearch(Map<String, dynamic> item) async {
    final lat = (item['lat'] as num).toDouble();
    final lng = (item['lng'] as num).toDouble();
    setState(() {
      destination = LatLng(lat, lng);
      _searchResults = [];
      _searchController.text = item['formatted_address'];
    });
    _updateMarkers();
    await _getRoute(); // fetch route
    _openNavigationPanel(); // show navigation controls
  }

  // -------------------
  // Directions & route
  // -------------------
  Future<void> _getRoute() async {
    if (currentLocation == null || destination == null) return;
    try {
      final String origin = '${currentLocation!.latitude},${currentLocation!.longitude}';
      final String dest = '${destination!.latitude},${destination!.longitude}';
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$dest&key=$apiKey');
      final response = await http.get(url).timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']['points'];
          final coordinates = _decodePolyline(polylinePoints);
          setState(() {
            polylines.clear();
            polylines.add(Polyline(
              polylineId: PolylineId('route'),
              points: coordinates,
              color: Color(0xFF4285F4),
              width: 5,
              geodesic: true,
            ));
            hasRoute = true;
          });
          // Auto-fit map
          Future.delayed(Duration(milliseconds: 800), () {
            if (mounted) _fitMapToRoute();
          });
        }
      }
    } catch (e) {
      print('Route failed: $e');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index) - 63;
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
    var p = 0.017453292519943295;
    var a = 0.5 -
        cos((destination!.latitude - currentLocation!.latitude!) * p) / 2 +
        cos(currentLocation!.latitude! * p) *
            cos(destination!.latitude * p) *
            (1 - cos((destination!.longitude - currentLocation!.longitude!) * p)) /
            2;
    return 7918 * asin(sqrt(a)); // miles (approx)
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

  void _centerOnMe() {
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

  void _openNavigationPanel() {
    // Show bottom navigation panel by setting navigationActive true
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
    });
  }

  // Call when user starts navigation
  Future<void> _startNavigation() async {
    if (destination == null) return;
    setState(() {
      navigationActive = true;
    });

    // If we are near the sample traffic light and it's red, and user is stopped, schedule a notification for green
    final now = DateTime.now();
    final lightState = sampleLight.computeStateAt(now);
    final distanceToLight = _distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      sampleLight.position.latitude,
      sampleLight.position.longitude,
    ); // miles
    // convert miles to meters ~ 1609.34 m / mile
    final meters = distanceToLight * 1609.34;

    const stopThresholdMeters = 30.0; // assume stopped if within 30m of light for demo
    if (meters <= stopThresholdMeters && lightState == TrafficLightState.red) {
      // user is stopped at red light — schedule a green notification if they background while stopped
      final secondsUntilGreen = sampleLight.secondsUntilGreen(now);
      final greenAt = now.add(Duration(seconds: secondsUntilGreen));
      print('Scheduling green notification at $greenAt (in $secondsUntilGreen s)');
      // but only schedule if user backgrounds the app while stopped — we set up scheduling in lifecycle handler
      // store candidate time in state
      _candidateGreenTime = greenAt;
      _candidateGreenLight = sampleLight;
    } else {
      _candidateGreenTime = null;
      _candidateGreenLight = null;
    }
  }

  // state for scheduled notification candidate
  DateTime? _candidateGreenTime;
  TrafficLight? _candidateGreenLight;

  // Call when user "arrives" or leaves intersection
  void _userStoppedAtLight(bool stopped) {
    setState(() {
      isStoppedAtLight = stopped;
    });
    if (!stopped) {
      // cancel candidate
      _candidateGreenTime = null;
      _candidateGreenLight = null;
    }
  }

  // Lifecycle observer - detect app background to schedule notification
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // If we go to background and there is a candidate green time scheduled,
    // schedule a local notification so phone rings when it turns green.
    if (state == AppLifecycleState.paused) {
      // app moved to background (Android). iOS specifics differ.
      if (navigationActive && isStoppedAtLight && _candidateGreenTime != null) {
        _showGreenNotification(
            'Light is green',
            'Your traffic light has turned green — continue driving.',
            _candidateGreenTime!);
        print('Notification scheduled for ${_candidateGreenTime!}');
      }
    }
  }

  // Utility distance calculator (miles)
  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 7918 * asin(sqrt(a));
  }

  // -------------------
  // UI Build
  // -------------------
  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Error'),
          backgroundColor: Color(0xFF008080),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red),
                SizedBox(height: 24),
                Text('Location Error', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                Text(errorMessage!, textAlign: TextAlign.center),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _initLocation,
                  icon: Icon(Icons.refresh),
                  label: Text('Retry'),
                  style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF008080)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isLoading || currentLocation == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Loading Map'), backgroundColor: Color(0xFF008080)),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF008080)),
            SizedBox(height: 16),
            Text('Getting your location...'),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.name}'s Route"),
        backgroundColor: Color(0xFF008080),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () => _showMapInfo(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              mapController = controller;
              Future.delayed(Duration(milliseconds: 1500), () {
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
            padding: EdgeInsets.only(top: 140, bottom: navigationActive ? 220 : 80),
            minMaxZoomPreference: MinMaxZoomPreference(10, 20),
          ),

          // top semi-transparent info card with search bar
          Positioned(
            top: 16,
            left: 12,
            right: 12,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Column(children: [
                  Row(children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(0xFF008080).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.directions_car, color: Color(0xFF008080)),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.vehicle, style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.navigation, size: 14, color: Colors.grey[600]),
                          SizedBox(width: 6),
                          Text('${_calculateDistance().toStringAsFixed(1)} miles',
                              style: TextStyle(fontSize: 13)),
                          if (hasRoute) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.green[100], borderRadius: BorderRadius.circular(4)),
                              child: Text('Route active', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                  ]),
                  SizedBox(height: 10),
                  // Search bar
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search destination',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.search),
                            onPressed: () => _performSearch(_searchController.text),
                          ),
                        ),
                        onSubmitted: (v) => _performSearch(v),
                      ),
                    ),
                    SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'center',
                      onPressed: _centerOnMe,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.my_location, color: Color(0xFF008080)),
                    ),
                  ]),

                  // Search results dropdown
                  if (_searchResults.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Container(
                      height: 120,
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (c, i) {
                          final r = _searchResults[i];
                          return ListTile(
                            title: Text(r['formatted_address']),
                            onTap: () => _setDestinationFromSearch(r),
                          );
                        },
                      ),
                    ),
                  ]
                ]),
              ),
            ),
          ),

          // Traffic light countdown overlay (when close & navigation active & stopped)
          if (navigationActive && _isNearSampleLight() && _isLightRedNow() && isStoppedAtLight)
            Positioned(
              bottom: navigationActive ? 260 : 120,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.black.withOpacity(0.7),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.traffic, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Traffic Light: RED — ${sampleLight.secondsUntilGreen(DateTime.now())}s until green',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            heroTag: 'maptype',
            onPressed: () {
              setState(() {
                if (currentMapType == MapType.normal) currentMapType = MapType.satellite;
                else if (currentMapType == MapType.satellite) currentMapType = MapType.hybrid;
                else currentMapType = MapType.normal;
              });
            },
            backgroundColor: Colors.white,
            child: Icon(
              currentMapType == MapType.normal
                  ? Icons.layers
                  : currentMapType == MapType.satellite
                  ? Icons.satellite_alt
                  : Icons.map,
              color: Color(0xFF008080),
            ),
          ),
          SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'streetview',
            onPressed: () => _showStreetView(),
            backgroundColor: Colors.white,
            child: Icon(Icons.zoom_in, color: Color(0xFF008080)),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'fullroute',
            onPressed: () => _fitMapToRoute(),
            backgroundColor: Color(0xFF008080),
            child: Icon(Icons.route, color: Colors.white),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'center2',
            onPressed: () => _centerOnMe(),
            backgroundColor: Color(0xFF008080),
            child: Icon(Icons.threed_rotation, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationPanel() {
    final distance = _calculateDistance();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      height: 220,
      padding: EdgeInsets.all(16),
      child: Column(children: [
        Row(
          children: [
            Expanded(child: Text(destination != null ? 'Destination set' : 'No destination', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () => _closeNavigationPanel(),
            )
          ],
        ),
        SizedBox(height: 8),
        Row(children: [
          Icon(Icons.map),
          SizedBox(width: 8),
          Expanded(child: Text(destination != null ? '${_searchController.text}' : 'Pick a destination')),
        ]),
        SizedBox(height: 12),
        Row(children: [
          Icon(Icons.timer_outlined),
          SizedBox(width: 8),
          Text('Distance: ${distance.toStringAsFixed(1)} miles'),
          Spacer(),
          if (hasRoute)
            ElevatedButton(
              onPressed: () {
                if (navigationActive) {
                  // Stop navigation
                  setState(() {
                    navigationActive = false;
                    _candidateGreenTime = null;
                    _candidateGreenLight = null;
                  });
                } else {
                  _startNavigation();
                }
              },
              child: Text(navigationActive ? 'Stop' : 'Start'),
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF008080)),
            ),
        ]),
        SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                // For demo: toggle "stopped at light" — in real app you'd detect vehicle speed
                _userStoppedAtLight(!isStoppedAtLight);
              },
              icon: Icon(Icons.pause),
              label: Text(isStoppedAtLight ? 'Mark as moving' : 'Mark as stopped'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
            SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                // Use mock location for testing
                _useMockLocation();
              },
              icon: Icon(Icons.location_searching),
              label: Text('Use Test Location'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            ),
          ],
        ),
      ]),
    );
  }

  void _showMapInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Map Info'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Buildings: Enabled ✅'),
          Text('Traffic: Enabled ✅'),
          Text('Map Type: ${currentMapType.toString()}'),
          SizedBox(height: 10),
          Text('Note: For full background/overlay functionality test on a real device.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))],
      ),
    );
  }

  void _showStreetView() {
    if (mapController == null || currentLocation == null) return;
    mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
      zoom: 17,
      tilt: 0,
      bearing: 0,
    )));
  }

  void _useMockLocation() {
    setState(() {
      currentLocation = loc.LocationData.fromMap({'latitude': 42.3223, 'longitude': -83.1763});
    });
    _updateMarkers();
    _getRoute();
  }

  // helper checks
  bool _isNearSampleLight() {
    if (currentLocation == null) return false;
    final distMiles = _distanceBetween(
      currentLocation!.latitude!,
      currentLocation!.longitude!,
      sampleLight.position.latitude,
      sampleLight.position.longitude,
    );
    final meters = distMiles * 1609.34;
    return meters <= 200; // within 200 meters considered "near"
  }

  bool _isLightRedNow() {
    return sampleLight.computeStateAt(DateTime.now()) == TrafficLightState.red;
  }
}
