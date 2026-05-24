import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import 'touchpad_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> with SingleTickerProviderStateMixin {
  final ConnectionService _connectionService = ConnectionService();
  late AnimationController _radarController;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8765');
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _connectionService.initSettings();
    _connectionService.startScanning();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _handleConnect(String ip, int port, String name) async {
    setState(() {
      _isConnecting = true;
    });

    if (_connectionService.hapticsEnabled) {
      HapticFeedback.mediumImpact();
    }

    final success = await _connectionService.connect(ip, port, serverName: name);

    if (mounted) {
      setState(() {
        _isConnecting = false;
      });

      if (success) {
        if (_connectionService.hapticsEnabled) {
          HapticFeedback.heavyImpact();
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TouchpadScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.withOpacity(0.9),
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 10),
                Text('Could not connect. Ensure server is running.', style: TextStyle(color: Colors.white)),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showManualConnectDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyan.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.settings_ethernet, color: Colors.cyan),
                    SizedBox(width: 10),
                    Text(
                      'Manual Connect',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'IP Address',
                    labelStyle: TextStyle(color: Colors.cyan.withOpacity(0.7)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.cyan),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: 'e.g. 192.168.1.15',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.laptop, color: Colors.cyan),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Port',
                    labelStyle: TextStyle(color: Colors.cyan.withOpacity(0.7)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.cyan),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.power, color: Colors.cyan),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final ip = _ipController.text.trim();
                        final port = int.tryParse(_portController.text) ?? 8765;
                        if (ip.isNotEmpty) {
                          Navigator.pop(context);
                          _handleConnect(ip, port, 'Manual Device');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettingsDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ListenableBuilder(
          listenable: _connectionService,
          builder: (context, _) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(color: Colors.cyan.withOpacity(0.2), width: 1.5),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Icon(Icons.tune, color: Colors.cyan),
                        SizedBox(width: 10),
                        Text(
                          'Touchpad Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Sensitivity
                    const Text('Sensitivity', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    Row(
                      children: [
                        const Icon(Icons.slow_motion_video, color: Colors.white54, size: 18),
                        Expanded(
                          child: Slider(
                            value: _connectionService.sensitivity,
                            min: 0.2,
                            max: 3.0,
                            activeColor: Colors.cyan,
                            inactiveColor: Colors.white12,
                            onChanged: (val) {
                              _connectionService.setSensitivity(val);
                            },
                          ),
                        ),
                        Text(
                          _connectionService.sensitivity.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Scroll Speed
                    const Text('Scroll Speed', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    Row(
                      children: [
                        const Icon(Icons.swap_vert, color: Colors.white54, size: 18),
                        Expanded(
                          child: Slider(
                            value: _connectionService.scrollSpeed,
                            min: 0.2,
                            max: 3.0,
                            activeColor: Colors.cyan,
                            inactiveColor: Colors.white12,
                            onChanged: (val) {
                              _connectionService.setScrollSpeed(val);
                            },
                          ),
                        ),
                        Text(
                          _connectionService.scrollSpeed.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    // Haptics Toggle
                    SwitchListTile(
                      title: const Text('Haptic Feedback', style: TextStyle(color: Colors.white70)),
                      subtitle: const Text('Vibrate on taps and gestures', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      value: _connectionService.hapticsEnabled,
                      activeColor: Colors.cyan,
                      activeTrackColor: Colors.cyan.withOpacity(0.3),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        _connectionService.setHapticsEnabled(val);
                        if (val) HapticFeedback.lightImpact();
                      },
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    // Natural Scroll Toggle
                    SwitchListTile(
                      title: const Text('Natural Scrolling', style: TextStyle(color: Colors.white70)),
                      subtitle: const Text('Scroll direction matches finger movement', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      value: _connectionService.naturalScroll,
                      activeColor: Colors.cyan,
                      activeTrackColor: Colors.cyan.withOpacity(0.3),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        _connectionService.setNaturalScroll(val);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617), // Premium ultra dark blue-black
      body: ListenableBuilder(
        listenable: _connectionService,
        builder: (context, _) {
          return Stack(
            children: [
              // Neon Ambient Glow backdrops
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withOpacity(0.12),
                        blurRadius: 100,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: -150,
                left: -100,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.15),
                        blurRadius: 120,
                      ),
                    ],
                  ),
                ),
              ),
              // Main content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                      
                      // 1. Header widget
                      Widget buildHeader() {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AirPad',
                                  style: TextStyle(
                                    fontSize: isLandscape ? 24 : 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                                if (!isLandscape)
                                  const Text(
                                    'Mobile Touchpad Client',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.cyan,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.tune, color: Colors.white70),
                                  onPressed: _showSettingsDrawer,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
                                  onPressed: _showManualConnectDialog,
                                ),
                              ],
                            )
                          ],
                        );
                      }

                      // 2. Animated Radar widget
                      Widget buildRadarSection() {
                        final size = isLandscape ? 120.0 : 280.0;
                        final iconSize = isLandscape ? 24.0 : 44.0;
                        final fontSize = isLandscape ? 10.0 : 12.0;

                        return Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _radarController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    size: Size(size, size),
                                    painter: RadarPainter(_radarController.value),
                                  );
                                },
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isConnecting ? Icons.sync : Icons.radar,
                                    size: iconSize,
                                    color: Colors.cyan,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _isConnecting
                                        ? 'CONNECTING...'
                                        : (isLandscape ? 'SCANNING...' : 'SCANNING NETWORK...'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: fontSize,
                                      letterSpacing: isLandscape ? 1.0 : 2.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      // 3. Device Discovery List widget
                      Widget buildDeviceListSection() {
                        return _isConnecting
                            ? const Center(
                                child: CircularProgressIndicator(color: Colors.cyan),
                              )
                            : _connectionService.discoveredServers.isEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.wifi_find, size: 40, color: Colors.white24),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Run server.py on your computer\nto auto-discover it here',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white30, height: 1.4, fontSize: isLandscape ? 11 : 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _connectionService.discoveredServers.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final server = _connectionService.discoveredServers[index];
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.04),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.cyan.withOpacity(0.15)),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.cyan.withOpacity(0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.desktop_windows, color: Colors.cyan, size: 20),
                                            ),
                                            title: Text(
                                              server.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 2.0),
                                              child: Text(
                                                'IP: ${server.ip}:${server.port}',
                                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                                              ),
                                            ),
                                            trailing: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.cyan,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.black),
                                            ),
                                            onTap: () => _handleConnect(server.ip, server.port, server.name),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                      }

                      if (isLandscape) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Column: Header + Radar animation
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  buildHeader(),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: buildRadarSection(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Right Column: Available computers text list
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'AVAILABLE COMPUTERS',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: buildDeviceListSection(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Original Column Layout for Portrait Mode
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildHeader(),
                            const SizedBox(height: 20),
                            Expanded(
                              flex: 4,
                              child: buildRadarSection(),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'AVAILABLE COMPUTERS',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              flex: 5,
                              child: buildDeviceListSection(),
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double animationVal;

  RadarPainter(this.animationVal);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    // Background circles
    final circlePaint = Paint()
      ..color = Colors.cyan.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * (i / 4), circlePaint);
    }

    // Grid lines
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), circlePaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), circlePaint);

    // Pulsing circle
    final pulsePaint = Paint()
      ..color = Colors.cyan.withOpacity(0.2 * (1 - animationVal))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius * animationVal, pulsePaint);

    // Radar sweep line
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.cyan.withOpacity(0.4),
          Colors.cyan.withOpacity(0.0),
        ],
        stops: const [0.0, 0.25],
        transform: GradientRotation(animationVal * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
