// lib/screens/animation_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'home_screen.dart';
import 'home_screen2.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnimationScreen extends StatefulWidget {
  @override
  _AnimationScreenState createState() => _AnimationScreenState();
}

class _AnimationScreenState extends State<AnimationScreen> {
  late Timer _timer;
  int _currentLight = 0;

  @override
  void initState() {
    super.initState();

    // Start traffic light animation
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _currentLight = (_currentLight + 1) % 3;
        });
      }
    });

    // Delay before navigation
    Future.delayed(const Duration(seconds: 3), () {
      _navigateNext();
    });
  }

  /// Function to handle navigation safely after delay
  Future<void> _navigateNext() async {
    // Fetch user details
    final details = await _getStoredDetails();

    if (!mounted) return; // Ensure widget still exists

    _timer.cancel(); // Stop the animation timer before navigating

    // Use addPostFrameCallback to ensure navigation happens
    // *after* the current frame, preventing animation freeze
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (details != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreenTwo(
              name: details['name']!,
              vehicle: details['vehicle']!,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
        );
      }
    });
  }

  Future<Map<String, String>?> _getStoredDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name');
    final vehicle = prefs.getString('vehicle');
    if (name != null && vehicle != null) {
      return {'name': name, 'vehicle': vehicle};
    }
    return null;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App title
            const Text(
              "Mase",
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 50),
            // Traffic lights
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLight(Colors.red, _currentLight == 0),
                const SizedBox(width: 20),
                _buildLight(Colors.yellow, _currentLight == 1),
                const SizedBox(width: 20),
                _buildLight(Colors.green, _currentLight == 2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLight(Color color, bool isOn) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isOn ? 1.0 : 0.3,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
