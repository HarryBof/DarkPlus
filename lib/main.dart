import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_brightness/screen_brightness.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
    ),
    home: const HomePage(),
  ));
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // Forces edge-to-edge drawing to cover the bottom navigation gap
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, 
    home: DarkLayerOverlay(),
  ));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    bool active = await FlutterOverlayWindow.isActive();
    setState(() => _isActive = active);
  }

  Future<void> _toggleFilter(bool value) async {
    bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }

    if (value) {
      // Manual size to force coverage of the whole screen
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        flag: OverlayFlag.clickThrough,
        alignment: OverlayAlignment.center,
        height: 3000, 
        width: 3000,
      );
    } else {
      await FlutterOverlayWindow.closeOverlay();
    }
    setState(() => _isActive = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Transform.scale(
          scale: 2.5, // Made the switch larger since it is the only UI element
          child: Switch(
            value: _isActive,
            activeColor: Colors.greenAccent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.redAccent.withOpacity(0.5),
            onChanged: (val) => _toggleFilter(val),
          ),
        ),
      ),
    );
  }
}

class DarkLayerOverlay extends StatefulWidget {
  const DarkLayerOverlay({super.key});
  @override
  State<DarkLayerOverlay> createState() => _DarkLayerOverlayState();
}

class _DarkLayerOverlayState extends State<DarkLayerOverlay> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    ScreenBrightness().onCurrentBrightnessChanged.listen((brightness) {
      if (mounted) {
        setState(() {
          // Adjusts transparency based on system brightness
          _opacity = (1.0 - brightness).clamp(0.0, 1.0);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black.withOpacity(_opacity),
      ),
    );
  }
}