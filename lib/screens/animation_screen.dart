import 'package:flutter/material.dart';
import 'dart:async';
import 'home_screen.dart';
class AnimationScreen extends StatefulWidget {
  @override
  _AnimationScreenState createState() => _AnimationScreenState();
}
class _AnimationScreenState extends State<AnimationScreen> {
  late Timer _timer;
  int _currentLight = 0; // 0 = red, 1 = yellow, 2 = green
  @override
  void initState() {
    super.initState();
// Timer to switch lights every 0.5 seconds
    _timer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      setState(() {
        _currentLight = (_currentLight + 1) % 3;
      });
    });
// Navigate to HomeScreen after 3 seconds
    Future.delayed(Duration(seconds: 3), () {
      _timer.cancel();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    });
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
            Text(
              "Mase",
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 50), // space between text and lights
// Traffic lights
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLight(Colors.red, _currentLight == 0),
                SizedBox(width: 20),
                _buildLight(Colors.yellow, _currentLight == 1),
                SizedBox(width: 20),
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
      duration: Duration(milliseconds: 300),
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