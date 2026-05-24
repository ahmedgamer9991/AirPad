import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';

class TouchpadScreen extends StatefulWidget {
  const TouchpadScreen({super.key});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  final ConnectionService _connection = ConnectionService();
  
  // Gesture states
  int _pointers = 0;
  int _maxPointersThisGesture = 0;
  bool _hasMovedThisGesture = false;
  bool _isDragging = false;
  DateTime? _lastTapTime;
  
  // Drag and Drop Hold Timer
  Timer? _dragTimer;
  Offset? _dragStartPoint;
  final Map<int, Offset> _pointerStartPoints = {};

  // Touch tracking for drawing glow trail
  Offset? _currentTouchPoint;

  // Keyboard state
  final TextEditingController _textController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _isKeyboardOpen = false;
  bool _isPopping = false;
  String _keyboardInputText = '';

  // Scroll lock states
  String _scrollDirection = 'none'; // 'none', 'vertical', 'horizontal'
  double _scrollAccumulatedDx = 0.0;
  double _scrollAccumulatedDy = 0.0;

  @override
  void initState() {
    super.initState();
    // Add connection listener to auto-pop on disconnection
    _connection.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    _textController.dispose();
    _keyboardFocusNode.dispose();
    _dragTimer?.cancel();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!_connection.isConnected && mounted && !_isPopping) {
      _isPopping = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Disconnected from computer'),
          backgroundColor: Colors.redAccent.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _toggleKeyboard() {
    setState(() {
      _isKeyboardOpen = !_isKeyboardOpen;
    });

    if (_isKeyboardOpen) {
      _textController.text = '\u200B';
      _keyboardInputText = '\u200B';
      _textController.selection = TextSelection.fromPosition(
        const TextPosition(offset: 1),
      );
      _keyboardFocusNode.requestFocus();
    } else {
      _keyboardFocusNode.unfocus();
    }

    if (_connection.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  Widget _buildTouchpadCanvas() {
    return Listener(
      onPointerDown: (event) {
        setState(() {
          _pointers++;
          _currentTouchPoint = event.localPosition;
        });

        // Track starting point for this specific finger
        _pointerStartPoints[event.pointer] = event.localPosition;

        if (_pointers > _maxPointersThisGesture) {
          _maxPointersThisGesture = _pointers;
        }

        if (_pointers == 2) {
          _scrollDirection = 'none';
          _scrollAccumulatedDx = 0.0;
          _scrollAccumulatedDy = 0.0;
          _dragTimer?.cancel();
        }

        if (_pointers == 1) {
          _hasMovedThisGesture = false;
          _dragStartPoint = event.localPosition;

          // Hold-to-Drag (Long Press & Hold) detector
          _dragTimer?.cancel();
          _dragTimer = Timer(const Duration(milliseconds: 350), () {
            if (mounted && _pointers == 1 && !_hasMovedThisGesture) {
              setState(() {
                _isDragging = true;
              });
              _connection.sendDrag(start: true);
              if (_connection.hapticsEnabled) {
                HapticFeedback.mediumImpact();
              }
            }
          });
        }
      },
      onPointerMove: (event) {
        setState(() {
          _currentTouchPoint = event.localPosition;
        });

        final dx = event.delta.dx;
        final dy = event.delta.dy;

        // If the pointer has moved beyond a small threshold, cancel the drag hold timer
        if (!_isDragging && _dragStartPoint != null) {
          final totalMove = (event.localPosition - _dragStartPoint!).distance;
          if (totalMove > 8.0) {
            _dragTimer?.cancel();
          }
        }
        
        // Track overall gesture displacement per finger to evaluate tap vs. swipe movement
        final startPoint = _pointerStartPoints[event.pointer];
        if (!_hasMovedThisGesture && startPoint != null) {
          final totalDisplacement = (event.localPosition - startPoint).distance;
          if (totalDisplacement > 12.0) {
            _hasMovedThisGesture = true;
          }
        } else if (_isDragging) {
          _hasMovedThisGesture = true;
        }

        if (_isDragging) {
          // Dragging with single finger
          _connection.sendMove(dx, dy);
        } else if (_pointers == 1) {
          // Standard cursor move
          _connection.sendMove(dx, dy);
        } else if (_pointers == 2) {
          // Two-finger scroll with axis-locking to prevent horizontal/vertical crosstalk
          final scaledDx = dx * 0.5;
          final scaledDy = dy * 0.5;

          if (_scrollDirection == 'none') {
            _scrollAccumulatedDx += scaledDx;
            _scrollAccumulatedDy += scaledDy;

            // Wait until cumulative movement is enough to decide direction (approx 3 raw pixels)
            if (_scrollAccumulatedDx.abs() > 1.5 || _scrollAccumulatedDy.abs() > 1.5) {
              if (_scrollAccumulatedDx.abs() > _scrollAccumulatedDy.abs() * 1.2) {
                _scrollDirection = 'horizontal';
              } else if (_scrollAccumulatedDy.abs() > _scrollAccumulatedDx.abs() * 1.2) {
                _scrollDirection = 'vertical';
              } else {
                _scrollDirection = 'vertical';
              }
            }
          }

          if (_scrollDirection == 'horizontal') {
            _connection.sendScroll(scaledDx, 0.0);
          } else if (_scrollDirection == 'vertical') {
            _connection.sendScroll(0.0, scaledDy);
          }
        }
      },
      onPointerUp: (event) {
        setState(() {
          _pointers--;
          if (_pointers == 0) {
            _currentTouchPoint = null;
          }
        });

        _dragTimer?.cancel();
        _pointerStartPoints.remove(event.pointer);

        if (_pointers < 2) {
          _scrollDirection = 'none';
          _scrollAccumulatedDx = 0.0;
          _scrollAccumulatedDy = 0.0;
        }

        if (_pointers == 0) {
          // Final finger lifted: evaluate gesture
          if (_isDragging) {
            setState(() {
              _isDragging = false;
            });
            _connection.sendDrag(start: false);
            if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
          } else if (!_hasMovedThisGesture) {
            if (_maxPointersThisGesture == 1) {
              // Tap: Left Click
              _connection.sendClick(left: true);
              if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
            } else if (_maxPointersThisGesture == 2) {
              // Two-finger Tap: Right Click
              _connection.sendClick(left: false);
              if (_connection.hapticsEnabled) HapticFeedback.mediumImpact();
            }
          }
          _maxPointersThisGesture = 0;
          _dragStartPoint = null;
          _pointerStartPoints.clear();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.cyan.withOpacity(0.12), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            children: [
              // Decorative Grid Lines for a premium "tech" feel
              Positioned.fill(
                child: CustomPaint(
                  painter: TouchpadGridPainter(),
                ),
              ),
              // Live Glow Trail under finger
              if (_currentTouchPoint != null)
                Positioned(
                  left: _currentTouchPoint!.dx - 50,
                  top: _currentTouchPoint!.dy - 50,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (_isDragging ? Colors.amber : Colors.cyan).withOpacity(_isDragging ? 0.35 : 0.20),
                          (_isDragging ? Colors.amber : Colors.cyan).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              // Faint Status Indicator inside Canvas
              Center(
                child: Opacity(
                  opacity: _isDragging ? 0.35 : 0.15,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDragging ? Icons.drag_indicator : Icons.touch_app,
                        size: 64,
                        color: _isDragging ? Colors.amber : Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isDragging ? 'DRAGGING ACTIVE (RELEASE TO DROP)' : 'TOUCHPAD ACTIVE',
                        style: TextStyle(
                          color: _isDragging ? Colors.amber : Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.5,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF020617), // Deep space black-blue
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.08),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.08),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),

          // Hidden text field to harvest native keyboard inputs
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                focusNode: _keyboardFocusNode,
                controller: _textController,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                onChanged: (text) {
                  if (text.isEmpty) {
                    // Zero-width space was deleted via backspace on empty input
                    _connection.sendSpecialKey('backspace');
                    _textController.text = '\u200B';
                    _keyboardInputText = '\u200B';
                    _textController.selection = TextSelection.fromPosition(
                      const TextPosition(offset: 1),
                    );
                    return;
                  }

                  if (!text.startsWith('\u200B')) {
                    // Fallback if the dummy character was lost/replaced
                    final oldLen = _keyboardInputText.length;
                    if (oldLen > 1) {
                      for (int i = 0; i < oldLen - 1; i++) {
                        _connection.sendSpecialKey('backspace');
                      }
                    }
                    if (text.isNotEmpty) {
                      _connection.sendText(text);
                    }
                    _textController.text = '\u200B$text';
                    _keyboardInputText = '\u200B$text';
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _textController.text.length),
                    );
                    return;
                  }

                  // If it doesn't start with the previous text, it means
                  // the keyboard autocorrected or selected a prediction/word-replacement.
                  if (!text.startsWith(_keyboardInputText)) {
                    // Delete the entire previous word from the PC
                    final charsToDelete = _keyboardInputText.length - 1;
                    for (int i = 0; i < charsToDelete; i++) {
                      _connection.sendSpecialKey('backspace');
                    }
                    // Send the new full word
                    final newWord = text.substring(1);
                    if (newWord.isNotEmpty) {
                      _connection.sendText(newWord);
                    }
                    _keyboardInputText = text;
                  } else {
                    // Incremental addition or subtraction
                    if (text.length > _keyboardInputText.length) {
                      final added = text.substring(_keyboardInputText.length);
                      if (added == '\n') {
                        _connection.sendSpecialKey('enter');
                      } else if (added == ' ') {
                        _connection.sendSpecialKey('space');
                      } else {
                        _connection.sendText(added);
                      }
                    } else if (text.length < _keyboardInputText.length) {
                      final deletedCount = _keyboardInputText.length - text.length;
                      for (int i = 0; i < deletedCount; i++) {
                        _connection.sendSpecialKey('backspace');
                      }
                    }
                    _keyboardInputText = text;
                  }

                  // If a word is completed (ends in space or newline), reset the composing buffer.
                  // This keeps the sync buffer small (max one word) and prevents huge backspacing lags.
                  if (text.endsWith(' ') || text.endsWith('\n')) {
                    _textController.text = '\u200B';
                    _keyboardInputText = '\u200B';
                    _textController.selection = TextSelection.fromPosition(
                      const TextPosition(offset: 1),
                    );
                  }
                },
                onSubmitted: (_) {
                  _connection.sendSpecialKey('enter');
                  _textController.text = '\u200B';
                  _keyboardInputText = '\u200B';
                  _textController.selection = TextSelection.fromPosition(
                    const TextPosition(offset: 1),
                  );
                },
              ),
            ),
          ),

          // Main client area
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (isLandscape) {
                  // Beautiful horizontal split layout for Landscape mode (maximize trackpad height!)
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column: Touchpad + compact backbar
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tight Landscape Header Bar
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                                    onPressed: () {
                                      if (_connection.hapticsEnabled) HapticFeedback.mediumImpact();
                                      _connection.disconnect();
                                    },
                                  ),
                                  Text(
                                    _connection.connectedName ?? 'Connected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Compact Latency badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _connection.ping < 15
                                                ? Colors.greenAccent
                                                : _connection.ping < 45
                                                    ? Colors.orangeAccent
                                                    : Colors.redAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_connection.ping} ms',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Expanded(
                                child: _buildTouchpadCanvas(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right Column: Slim floating actions strip
                      Container(
                        width: 72,
                        margin: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.04), width: 1.5),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _buildCompactActionButton(
                                icon: _isKeyboardOpen ? Icons.keyboard_hide : Icons.keyboard,
                                label: 'Key',
                                isActive: _isKeyboardOpen,
                                onTap: _toggleKeyboard,
                              ),
                              const SizedBox(height: 12),
                              _buildCompactActionButton(
                                icon: Icons.volume_up,
                                label: 'Vol +',
                                onTap: () {
                                  _connection.sendMedia('volume_up');
                                  if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                },
                              ),
                              _buildCompactActionButton(
                                icon: Icons.play_arrow,
                                label: 'Play',
                                onTap: () {
                                  _connection.sendMedia('play_pause');
                                  if (_connection.hapticsEnabled) HapticFeedback.mediumImpact();
                                },
                              ),
                              _buildCompactActionButton(
                                icon: Icons.volume_down,
                                label: 'Vol -',
                                onTap: () {
                                  _connection.sendMedia('volume_down');
                                  if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                },
                              ),
                              const SizedBox(height: 6),
                              _buildCompactActionButton(
                                icon: Icons.volume_off,
                                label: 'Mute',
                                onTap: () {
                                  _connection.sendMedia('mute');
                                  if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // Standard Column Layout for Portrait Mode
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Status & Control Top Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                              onPressed: () {
                                if (_connection.hapticsEnabled) HapticFeedback.mediumImpact();
                                _connection.disconnect();
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _connection.connectedName ?? 'Connected',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _connection.connectedIp ?? '0.0.0.0',
                                    style: const TextStyle(
                                      color: Colors.cyan,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _connection.ping < 15
                                          ? Colors.greenAccent
                                          : _connection.ping < 45
                                              ? Colors.orangeAccent
                                              : Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_connection.ping} ms',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. Main Touchpad Canvas
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: _buildTouchpadCanvas(),
                        ),
                      ),

                      // 3. Media Dock & Keyboard Button (Bottom controls)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                          border: Border.all(color: Colors.white.withOpacity(0.04), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildActionButton(
                                  icon: _isKeyboardOpen ? Icons.keyboard_hide : Icons.keyboard,
                                  label: 'Keyboard',
                                  isActive: _isKeyboardOpen,
                                  onTap: _toggleKeyboard,
                                ),
                                _buildActionButton(
                                  icon: Icons.volume_down,
                                  label: 'Vol -',
                                  onTap: () {
                                    _connection.sendMedia('volume_down');
                                    if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                  },
                                ),
                                _buildActionButton(
                                  icon: Icons.play_arrow,
                                  label: 'Play/Pause',
                                  onTap: () {
                                    _connection.sendMedia('play_pause');
                                    if (_connection.hapticsEnabled) HapticFeedback.mediumImpact();
                                  },
                                ),
                                _buildActionButton(
                                  icon: Icons.volume_up,
                                  label: 'Vol +',
                                  onTap: () {
                                    _connection.sendMedia('volume_up');
                                    if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                  },
                                ),
                                _buildActionButton(
                                  icon: Icons.volume_off,
                                  label: 'Mute',
                                  onTap: () {
                                    _connection.sendMedia('mute');
                                    if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                  },
                                ),
                              ],
                            ),
                            
                            // Secondary Media Controller drawer: Previous & Next track
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: Colors.white54, size: 28),
                                  onPressed: () {
                                    _connection.sendMedia('prev');
                                    if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                  },
                                ),
                                const SizedBox(width: 40),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: Colors.white54, size: 28),
                                  onPressed: () {
                                    _connection.sendMedia('next');
                                    if (_connection.hapticsEnabled) HapticFeedback.lightImpact();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive ? Colors.cyan : Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive ? Colors.black : Colors.white70,
                size: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.cyan : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive ? Colors.cyan : Colors.white.withOpacity(0.04),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? Colors.cyan : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: Icon(
                  icon,
                  color: isActive ? Colors.black : Colors.white70,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isActive ? Colors.cyan : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class TouchpadGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyan.withOpacity(0.02)
      ..strokeWidth = 1.0;

    const step = 40.0;
    
    // Vertical grid lines
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    
    // Horizontal grid lines
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
