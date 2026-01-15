import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../physics/bubble_system.dart';
import '../models/kiosk_status.dart';
import 'bubble_widget.dart';

class PhysicsLayout extends StatefulWidget {
  final KioskStatus status;
  final bool isDisplay;
  final int Function()
  getLocalSecondsSincePoll; // Getter for fresh time on each frame

  const PhysicsLayout({
    super.key,
    required this.status,
    required this.getLocalSecondsSincePoll,
    this.isDisplay = false,
  });

  @override
  State<PhysicsLayout> createState() => _PhysicsLayoutState();
}

class _PhysicsLayoutState extends State<PhysicsLayout>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late BubbleSystem _bubbleSystem;
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    // Initialize Bubble System
    _bubbleSystem = BubbleSystem();
    // Sync initial state
    _bubbleSystem.sync(status: widget.status);

    // Create Ticker for physics loop
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(PhysicsLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync when status changes
    if (widget.status != oldWidget.status) {
      _bubbleSystem.sync(status: widget.status);
    }
    // Update timers on every rebuild (1 second from UI tick) - handles throttled tabs
    _bubbleSystem.updateTimersOnly(widget.getLocalSecondsSincePoll());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final double currentTime = elapsed.inMicroseconds / 1000000.0;
    if (_lastTime == 0) _lastTime = currentTime;

    // Calculate delta time
    double dt = currentTime - _lastTime;
    _lastTime = currentTime;

    // Cap dt to prevent huge jumps if tab was backgrounded
    if (dt > 0.05) dt = 0.05;

    // Update Physics with fresh time getter (smooth per-frame timer updates)
    _bubbleSystem.update(
      dt,
      getLocalSecondsSincePoll: widget.getLocalSecondsSincePoll,
    );

    // Trigger rebuild to paint new positions
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 1. Determine Background Color (Interpolated)
    // Material Design 3 Expressive approach:
    // Use a single solid color that shifts based on "tension" or "usage".
    // 0% Used -> Green (Available)
    // 50% Used -> Amber/Yellow (Warning/Busy)
    // 100% Used -> Red (Full)
    // This allows for a smooth, organic heatmap feel without complex gradients.

    final int capacity = widget.status.capacity;
    final int usedCount = widget.status.activeSessions.length;

    final bool isBanned = widget.status.kioskSuspended;

    Color bgColor;

    if (isBanned) {
      bgColor = const Color(0xFFB71C1C); // Red 900
    } else if (usedCount < capacity) {
      bgColor = const Color(0xFF4CAF50); // Green 500 (Available)
    } else {
      bgColor = const Color(0xFFEF5350); // Red 400 (Full/Busy)
    }

    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 1000,
      ), // Slower, more organic color shift
      curve: Curves.linearToEaseOut,
      decoration: BoxDecoration(
        color: bgColor,
      ), // Always use BoxDecoration with color to prevent flash
      width: double.infinity,
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double screenW = constraints.maxWidth;
          final double screenH = constraints.maxHeight;

          // Update Viewport in Physics System
          _bubbleSystem.updateViewport(Size(screenW, screenH));

          // Base size logic based on screen real estate
          // We want bubbles to take up a significant portion of the screen "creatively".
          // The Physics Scale provides the layout factor (0.0 to 1.6+).
          // We apply that to a large base radius derived from the viewport min dimension.

          final double minDim = (screenW < screenH) ? screenW : screenH;
          // Base radius is 40% of the smallest dimension
          final double baseRadius = minDim * 0.40;

          return Stack(
            children: [
              ..._bubbleSystem.bubbles.map((b) {
                // Calculate absolute position based on % coordinates
                // Physics x/y are 0-100 percentages of the viewport.
                final double x = (b.xSpring.current / 100.0) * screenW;
                final double y = (b.ySpring.current / 100.0) * screenH;

                // Apply Scale from Physics (which is now aspect-aware)
                final double currentScale = b.scaleSpring.current;

                if (currentScale < 0.01) return const SizedBox.shrink();

                return Positioned(
                  left:
                      x - baseRadius, // Center origin relative to UNSCALED size
                  top:
                      y - baseRadius, // Center origin relative to UNSCALED size
                  child: Transform.scale(
                    scale: currentScale,
                    child: BubbleWidget(
                      bubble: b,
                      isDisplay: widget.isDisplay,
                      scale:
                          1.0, // Internal scale normalized, size handled by Transform/Radius
                      overrideSize:
                          baseRadius * 2, // Force exact size to match layout
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
