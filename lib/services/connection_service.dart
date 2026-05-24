import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiscoveredServer {
  final String name;
  final String ip;
  final int port;
  DateTime lastSeen;

  DiscoveredServer({
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredServer &&
          runtimeType == other.runtimeType &&
          ip == other.ip;

  @override
  int get hashCode => ip.hashCode;
}

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  RawDatagramSocket? _udpSocket;
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;
  
  final List<DiscoveredServer> _discoveredServers = [];
  List<DiscoveredServer> get discoveredServers => List.unmodifiable(_discoveredServers);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _connectedIp;
  String? get connectedIp => _connectedIp;

  String? _connectedName;
  String? get connectedName => _connectedName;

  Timer? _cleanupTimer;
  Timer? _pingTimer;
  int _ping = 0;
  int get ping => _ping;

  // Settings
  double _sensitivity = 1.0;
  double get sensitivity => _sensitivity;

  double _scrollSpeed = 1.0;
  double get scrollSpeed => _scrollSpeed;

  bool _hapticsEnabled = true;
  bool get hapticsEnabled => _hapticsEnabled;

  bool _naturalScroll = true;
  bool get naturalScroll => _naturalScroll;

  Future<void> initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _sensitivity = prefs.getDouble('sensitivity') ?? 1.0;
    _scrollSpeed = prefs.getDouble('scrollSpeed') ?? 1.0;
    _hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
    _naturalScroll = prefs.getBool('naturalScroll') ?? true;
    notifyListeners();
  }

  Future<void> setSensitivity(double val) async {
    _sensitivity = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sensitivity', val);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool val) async {
    _hapticsEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticsEnabled', val);
    notifyListeners();
  }

  Future<void> setNaturalScroll(bool val) async {
    _naturalScroll = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('naturalScroll', val);
    notifyListeners();
  }

  Future<void> setScrollSpeed(double val) async {
    _scrollSpeed = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('scrollSpeed', val);
    notifyListeners();
  }

  /// Start listening for UDP broadcasts from servers on the local network.
  void startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredServers.clear();
    notifyListeners();

    try {
      // Bind to wildcard address, port 8769 for incoming broadcasts
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8769);
      _udpSocket!.broadcastEnabled = true;
      
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            try {
              final rawStr = utf8.decode(datagram.data);
              final payload = json.decode(rawStr) as Map<String, dynamic>;
              
              final name = payload['server_name'] as String? ?? 'Unknown Computer';
              final ip = payload['ip'] as String? ?? datagram.address.address;
              final port = payload['port'] as int? ?? 8765;

              final server = DiscoveredServer(
                name: name,
                ip: ip,
                port: port,
                lastSeen: DateTime.now(),
              );

              final index = _discoveredServers.indexOf(server);
              if (index != -1) {
                // Update timestamp for existing server
                _discoveredServers[index].lastSeen = DateTime.now();
              } else {
                // Add new discovered server
                _discoveredServers.add(server);
                notifyListeners();
              }
            } catch (e) {
              debugPrint('Failed to parse discovery packet: $e');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to bind UDP socket: $e');
    }

    // Clean up servers that haven't been seen for 6 seconds
    _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final now = DateTime.now();
      final beforeCount = _discoveredServers.length;
      _discoveredServers.removeWhere((s) => now.difference(s.lastSeen).inSeconds > 6);
      if (_discoveredServers.length != beforeCount) {
        notifyListeners();
      }
    });
  }

  /// Stop scanning for servers
  void stopScanning() {
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    _isScanning = false;
    notifyListeners();
  }

  /// Connect to the desktop server via WebSockets
  Future<bool> connect(String ip, int port, {String? serverName}) async {
    stopScanning();
    await disconnect();

    try {
      // Connect to WebSocket with connection timeout of 4 seconds
      final wsUrl = Uri.parse('ws://$ip:$port');
      _webSocket = await WebSocket.connect(wsUrl.toString()).timeout(const Duration(seconds: 4));
      
      _isConnected = true;
      _connectedIp = ip;
      _connectedName = serverName ?? 'Connected Computer';
      notifyListeners();

      // Listen for latency tests (pongs) or disconnections
      _wsSubscription = _webSocket!.listen(
        (message) {
          if (message is String && message.startsWith('p:')) {
            try {
              final sendTime = int.parse(message.substring(2));
              final receiveTime = DateTime.now().millisecondsSinceEpoch;
              _ping = receiveTime - sendTime;
              notifyListeners();
            } catch (_) {}
          }
        },
        onDone: () {
          disconnect();
        },
        onError: (err) {
          debugPrint('WebSocket error: $err');
          disconnect();
        },
        cancelOnError: true,
      );

      // Start periodic latency tracker (ping) every 1.5 seconds
      _pingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
        if (_isConnected && _webSocket != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          sendRaw('p:$now');
        }
      });

      return true;
    } catch (e) {
      debugPrint('Connection failed: $e');
      disconnect();
      return false;
    }
  }

  /// Disconnect from the desktop server
  Future<void> disconnect() async {
    if (!_isConnected && _webSocket == null) return;

    _isConnected = false;
    _pingTimer?.cancel();

    await _wsSubscription?.cancel();
    _wsSubscription = null;

    await _webSocket?.close();
    _webSocket = null;
    _connectedIp = null;
    _connectedName = null;
    _ping = 0;
    notifyListeners();
    startScanning(); // resume scanning automatically
  }

  /// Send a raw command packet to the server
  void sendRaw(String data) {
    if (_isConnected && _webSocket != null && _webSocket!.readyState == WebSocket.open) {
      _webSocket!.add(data);
    }
  }

  /// Send relative cursor move event: m:dx:dy
  void sendMove(double dx, double dy) {
    // Apply sensitivity scaling
    final scaledDx = dx * _sensitivity;
    final scaledDy = dy * _sensitivity;
    // Format double to 2 decimal places to minimize payload size
    sendRaw('m:${scaledDx.toStringAsFixed(2)}:${scaledDy.toStringAsFixed(2)}');
  }

  /// Send mouse click: c:l (left) or c:r (right)
  void sendClick({required bool left}) {
    sendRaw(left ? 'c:l' : 'c:r');
  }

  /// Send scroll events: s:dx:dy
  void sendScroll(double dx, double dy) {
    final direction = _naturalScroll ? 1.0 : -1.0;
    final scaledDx = dx * _scrollSpeed;
    final scaledDy = dy * _scrollSpeed;
    sendRaw('s:${(scaledDx * -direction).toStringAsFixed(2)}:${(scaledDy * direction).toStringAsFixed(2)}');
  }

  /// Send drag events: d:s (start) or d:e (end)
  void sendDrag({required bool start}) {
    sendRaw(start ? 'd:s' : 'd:e');
  }

  /// Send media events: a:ACTION
  void sendMedia(String action) {
    sendRaw('a:$action');
  }

  /// Send keyboard special key: k:k:KEY
  void sendSpecialKey(String keyName) {
    sendRaw('k:k:$keyName');
  }

  /// Send keyboard typed text: k:t:TEXT
  void sendText(String text) {
    sendRaw('k:t:$text');
  }

  @override
  void dispose() {
    stopScanning();
    _pingTimer?.cancel();
    _webSocket?.close();
    super.dispose();
  }
}
