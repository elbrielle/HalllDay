import 'dart:ui';
import 'dart:math';
import '../models/session.dart';
import '../models/kiosk_status.dart';
import 'spring_simulation.dart';

enum BubbleType { available, used, banned, suspended, processing }

/// Logic model for a single bubble in the physics system.
class BubbleModel {
  final String id;
  BubbleType type;

  // Physics Springs
  final SpringSimulation xSpring = SpringSimulation(
    stiffness: 100,
    damping: 14,
  );
  final SpringSimulation ySpring = SpringSimulation(
    stiffness: 100,
    damping: 14,
  );
  final SpringSimulation scaleSpring = SpringSimulation(
    stiffness: 120,
    damping: 14,
  );
  final SpringSimulation rotateSpring = SpringSimulation(
    stiffness: 100,
    damping: 12,
  );

  // Content Data
  String name = '';
  String timerText = '';
  bool isOverdue = false;

  // Session reference for timer calculation
  Session? _activeSession;

  BubbleModel({
    required this.id,
    this.type = BubbleType.available,
    double startX = 50.0,
    double startY = 50.0,
  }) {
    // Initialize
    xSpring.set(startX);
    ySpring.set(startY);
    scaleSpring.set(0.0); // Start pop-in
    rotateSpring.set(0.0);
  }

  /// Update physics and timer display
  /// [localSecondsSincePoll] - seconds elapsed since last server data received
  void update(double dt, {int localSecondsSincePoll = 0}) {
    xSpring.update(dt);
    ySpring.update(dt);
    scaleSpring.update(dt);
    rotateSpring.update(dt);

    // Update timer: server elapsed + local seconds since poll
    // This is device-clock-independent (only measures local deltas)
    if (type == BubbleType.used && _activeSession != null) {
      timerText = _activeSession!.getCurrentTimerText(localSecondsSincePoll);
    }
  }

  void settarget({
    required double x,
    required double y,
    required double scale,
    required BubbleType newType,
    Session? sessionData,
  }) {
    xSpring.target = x;
    ySpring.target = y;
    scaleSpring.target = scale;

    final bool typeChanged = type != newType;
    type = newType;

    if (typeChanged) {
      // Add "pop" effect on state change
      scaleSpring.velocity += 15.0;
      rotateSpring.velocity += 10.0;
    }

    // Update Content Data
    if (newType == BubbleType.used && sessionData != null) {
      name = sessionData.name;
      isOverdue = sessionData.overdue;
      _activeSession = sessionData;
      timerText = sessionData.getCurrentTimerText(
        0,
      ); // Will be updated next frame
    } else if (newType == BubbleType.banned) {
      name = "BANNED";
      timerText = "";
      isOverdue = true;
      _activeSession = null;
    } else if (newType == BubbleType.suspended) {
      name = "SUSPENDED";
      timerText = "";
      isOverdue = true;
      _activeSession = null;
    } else {
      name = "Scan ID";
      timerText = "";
      isOverdue = false;
      _activeSession = null;
    }
  }
}

/// Manages the collection of bubbles and their layout
class BubbleSystem {
  List<BubbleModel> bubbles = [];

  /// Update physics and timer display (called at 60fps by Ticker)
  void update(double dt, {required int Function() getLocalSecondsSincePoll}) {
    final int currentSeconds = getLocalSecondsSincePoll();
    for (var b in bubbles) {
      b.update(dt, localSecondsSincePoll: currentSeconds);
    }
  }

  /// Update timer text only (without physics) - for throttled tab fallback
  void updateTimersOnly(int localSecondsSincePoll) {
    for (var b in bubbles) {
      b.update(0, localSecondsSincePoll: localSecondsSincePoll);
    }
  }

  // Viewport size needed for aspect ratio calculations
  Size _viewport = const Size(1920, 1080);

  void updateViewport(Size size) {
    if (_viewport != size) {
      _viewport = size;
      // Re-run layout logic whenever size changes significantly
      // This ensures responsiveness
      refreshLayout();
    }
  }

  void refreshLayout() {
    // Re-calculate targets for existing bubbles based on new viewport
    final int count = bubbles.length;
    if (count == 0) return;

    final List<Map<String, double>> layout = getLayout(count);

    for (int i = 0; i < count; i++) {
      // Only update X/Y targets, preserve type/state
      bubbles[i].xSpring.target = layout[i]['x']!;
      bubbles[i].ySpring.target = layout[i]['y']!;
      bubbles[i].scaleSpring.target = layout[i]['scale']!;
    }
  }

  void sync({required KioskStatus status}) {
    if (status.kioskSuspended) {
      ensureBubbleCount(1);
      bubbles[0].settarget(
        x: 50,
        y: 50,
        scale: 1.0,
        newType: BubbleType.suspended,
      );
      return;
    }

    final int usedCount = status.activeSessions.length;
    final bool showAvailable = usedCount < status.capacity;
    final int totalBubbles = usedCount + (showAvailable ? 1 : 0);

    ensureBubbleCount(totalBubbles);

    final List<Map<String, double>> layout = getLayout(totalBubbles);

    // Sync Used Sessions (timer handled in update loop with fresh time)
    for (int i = 0; i < usedCount; i++) {
      final pos = layout[i];
      bubbles[i].settarget(
        x: pos['x']!,
        y: pos['y']!,
        scale: pos['scale']!,
        newType: BubbleType.used,
        sessionData: status.activeSessions[i],
      );
    }

    // Sync Available Bubble (if exists)
    if (showAvailable) {
      final int idx = usedCount;
      final pos = layout[idx];
      bubbles[idx].settarget(
        x: pos['x']!,
        y: pos['y']!,
        scale: pos['scale']!,
        newType: BubbleType.available,
      );
    }
  }

  void ensureBubbleCount(int count) {
    // Add if needed
    while (bubbles.length < count) {
      final String id =
          DateTime.now().millisecondsSinceEpoch.toString() +
          Random().nextInt(1000).toString();

      double startX = 50.0;
      double startY = 50.0;

      // "Cell Division": Spawn from last bubble position
      if (bubbles.isNotEmpty) {
        final last = bubbles.last;
        startX = last.xSpring.current;
        startY = last.ySpring.current;
      }

      bubbles.add(BubbleModel(id: id, startX: startX, startY: startY));
    }

    // Remove if too many (simple pop for now, could animate out later)
    while (bubbles.length > count) {
      bubbles.removeLast();
    }
  }

  List<Map<String, double>> getLayout(int count) {
    // Determine screen metrics
    final bool isPortrait = _viewport.height > _viewport.width;
    final double minDim = isPortrait ? _viewport.width : _viewport.height;

    // Bubble Base Logic:
    // Diameter = minDim * 0.40 * 2 (because baseRadius is 0.4*minDim) = 0.8 * minDim.
    // For Count=2, we used scale 0.8 -> Actual Width = 0.8 * 0.8 * minDim = 0.64 * minDim.
    // We want to pack them with a gap.

    // Normalized dimensions (0-100 logic handled by conversions, but here we need absolute to determine centering)

    if (count <= 1) {
      return [
        {'x': 50.0, 'y': 50.0, 'scale': 1.0},
      ];
    }

    if (count == 2) {
      final double scale = 0.8;
      final double bubbleSizePx = minDim * 0.8 * scale; // ~0.64 * minDim
      final double gapPx = minDim * 0.05; // 5% of min dimension as gap

      final double groupSizePx = (bubbleSizePx * 2) + gapPx;

      if (isPortrait) {
        // Vertical Stack
        // Center vertically in Height
        final double startYPx = (_viewport.height - groupSizePx) / 2;

        final double y1Px = startYPx + (bubbleSizePx / 2);
        final double y2Px = y1Px + bubbleSizePx + gapPx;

        // Convert to %
        final double y1 = (y1Px / _viewport.height) * 100;
        final double y2 = (y2Px / _viewport.height) * 100;

        return [
          {'x': 50.0, 'y': y1, 'scale': scale},
          {'x': 50.0, 'y': y2, 'scale': scale},
        ];
      } else {
        // Horizontal Stack
        // Center horizontally in Width
        final double startXPx = (_viewport.width - groupSizePx) / 2;

        final double x1Px = startXPx + (bubbleSizePx / 2);
        final double x2Px = x1Px + bubbleSizePx + gapPx;

        // Convert to %
        final double x1 = (x1Px / _viewport.width) * 100;
        final double x2 = (x2Px / _viewport.width) * 100;

        return [
          {'x': x1, 'y': 50.0, 'scale': scale},
          {'x': x2, 'y': 50.0, 'scale': scale},
        ];
      }
    }

    // Three Bubbles
    // Three Bubbles
    if (count == 3) {
      final double scale = 0.65;
      final double bubbleSizePx = minDim * 0.8 * scale;
      // Use slightly looser layout for 3 to avoid clutter? No, keep tight.

      // Pyramid / Triangle Logic requires row-based packing.
      // Top Row: 1 item. Bottom Row: 2 items.

      if (isPortrait) {
        // Portrait: Pyramid
        // Row 1 Y: Top 30%? No, calculate.
        // Row 2 Y: Bottom 70%?

        // Let's stick to % for Y vertical distribution to match "Triangle" look,
        // BUT horizontally center them nicely.

        // Row 1 (1 item): Center X.
        // Row 2 (2 items): Pack Center X.

        // Row 2 Width
        final double gapPx = minDim * 0.05;
        final double row2Width = (bubbleSizePx * 2) + gapPx;
        final double startX2 = (_viewport.width - row2Width) / 2;

        final double x2_1 =
            ((startX2 + bubbleSizePx / 2) / _viewport.width) * 100;
        final double x2_2 =
            ((startX2 + bubbleSizePx + gapPx + bubbleSizePx / 2) /
                _viewport.width) *
            100;

        return [
          {'x': 50.0, 'y': 25.0, 'scale': scale}, // Top Center
          {'x': x2_1, 'y': 70.0, 'scale': scale}, // Bottom Left
          {'x': x2_2, 'y': 70.0, 'scale': scale}, // Bottom Right
        ];
      } else {
        // Landscape: Triangle
        // Row 1 (1 item)
        // Row 2 (2 items)
        // Same logic for X centering on Row 2
        final double gapPx = minDim * 0.05;
        final double row2Width = (bubbleSizePx * 2) + gapPx;
        final double startX2 = (_viewport.width - row2Width) / 2;

        final double x2_1 =
            ((startX2 + bubbleSizePx / 2) / _viewport.width) * 100;
        final double x2_2 =
            ((startX2 + bubbleSizePx + gapPx + bubbleSizePx / 2) /
                _viewport.width) *
            100;

        return [
          {'x': 50.0, 'y': 30.0, 'scale': scale}, // Top Center
          {'x': x2_1, 'y': 70.0, 'scale': scale}, // Bottom Left
          {'x': x2_2, 'y': 70.0, 'scale': scale}, // Bottom Right
        ];
      }
    }

    // Dynamic Grid (4+)
    final List<Map<String, double>> result = [];

    // Determine rows/cols based on aspect ratio to minimize empty space
    int cols, rows;

    if (isPortrait) {
      // Taller: more rows
      cols = sqrt(count).floor();
      if (cols < 1) cols = 1;
      rows = (count / cols).ceil();
    } else {
      // Wider: more cols
      cols = sqrt(count).ceil();
      rows = (count / cols).ceil();
    }

    final double scale = 1.6 / max(cols, rows);
    final double gapPx = minDim * 0.05 * scale; // Gap scales with bubbles
    final double bubbleSizePx = minDim * 0.8 * scale;

    // Grid Height Calculation
    // Total Height = rows * bubbleSize + (rows-1) * gap
    final double totalGridHeightPx =
        (rows * bubbleSizePx) + ((rows - 1) * gapPx);
    final double startYPx = (_viewport.height - totalGridHeightPx) / 2;

    for (int i = 0; i < count; i++) {
      final int r = (i / cols).floor();
      final int c = i % cols;

      // Determine items in THIS row (for centering)
      // First, how many rows total? 'rows'.
      // Is this the last row?
      bool isLastRow = (r == rows - 1);
      int itemsInThisRow = cols;
      if (isLastRow) {
        itemsInThisRow = count % cols;
        if (itemsInThisRow == 0) itemsInThisRow = cols;
      }

      // Calculate Row Width
      final double rowWidthPx =
          (itemsInThisRow * bubbleSizePx) + ((itemsInThisRow - 1) * gapPx);
      // Start X for this row
      final double rowStartXPx = (_viewport.width - rowWidthPx) / 2;

      // Calculate Item X
      final double itemXPx =
          rowStartXPx + (c * (bubbleSizePx + gapPx)) + (bubbleSizePx / 2);

      // Calculate Item Y
      final double itemYPx =
          startYPx + (r * (bubbleSizePx + gapPx)) + (bubbleSizePx / 2);

      // Convert to %
      final double x = (itemXPx / _viewport.width) * 100;
      final double y = (itemYPx / _viewport.height) * 100;

      result.add({'x': x, 'y': y, 'scale': scale});
    }
    return result;
  }
}
