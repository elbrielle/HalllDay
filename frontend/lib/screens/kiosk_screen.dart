import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'dart:async'; // For Timer
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/status_provider.dart';
import '../widgets/physics_layout.dart';

import '../widgets/mobile_list_view.dart';

class KioskScreen extends StatefulWidget {
  final String token;

  const KioskScreen({super.key, required this.token});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  AnimationController? _shakeController;
  Timer? _focusTimer; // Periodic check

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Listen to lifecycle
    _shakeController = AnimationController(vsync: this, duration: 500.ms);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatusProvider>().init(widget.token);
      _requestFocus();
    });

    // Kiosk Mode: Force focus every 2 seconds if lost
    _focusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_focusNode.hasFocus) {
        debugPrint("Lost focus - reclaiming for generic input");
        _requestFocus();
      }
    });
  }

  void _requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
      // SystemChannels.textInput.invokeMethod('TextInput.show'); // Optional: ensure soft keyboard doesn't hide functionality if needed, though usually distinct
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestFocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _shakeController?.dispose();
    _scanController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _processScan(String code) async {
    if (code.trim().isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<StatusProvider>();

    // Clear immediately
    _scanController.clear();
    _requestFocus();

    final result = await provider.scanCode(code.trim());

    if (result['ok'] == true) {
      if (result['action'] == 'ended_auto_started') {
        _showSnack(
          scaffoldMessenger,
          "Returned: ${result['name']}. Next Up: ${result['next_student'] ?? 'Next Student'}",
          Colors.orange,
        );
      } else if (result['action'] == 'ended_banned') {
        HapticFeedback.heavyImpact();
        _shakeController?.forward(from: 0);
        _showSnack(
          scaffoldMessenger,
          result['message'] ?? "Student Auto-Banned",
          Colors.red,
        );
      } else if (result['action'] == 'queued') {
        HapticFeedback.lightImpact();
        _showSnack(
          scaffoldMessenger,
          result['message'] ?? "Added to Waitlist",
          Colors.orange,
        );
        context.read<StatusProvider>().fetchStatus();
      } else {
        _showSnack(
          scaffoldMessenger,
          "Success: ${result['action']} for ${result['name']}",
          Colors.green,
        );
      }
    } else {
      HapticFeedback.heavyImpact();
      _shakeController?.forward(from: 0);
      _showSnack(scaffoldMessenger, result['message'] ?? "Error", Colors.red);
    }
  }

  void _showSnack(ScaffoldMessengerState messenger, String msg, Color color) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: GestureDetector(
        behavior: HitTestBehavior.translucent, // Catch taps on empty space
        onTap: _requestFocus,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0,
              child: TextField(
                controller: _scanController,
                focusNode: _focusNode,
                autofocus: true,
                onSubmitted: _processScan,
              ),
            ),

            LayoutBuilder(
              builder: (context, constraints) {
                final isSmallScreen = constraints.maxWidth < 600;

                return Consumer<StatusProvider>(
                  builder: (context, provider, child) {
                    if (provider.isLoading && provider.status == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final status = provider.status;
                    if (status == null) {
                      return const Center(
                        child: Text(
                          "Error: No Status",
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    // MOBILE VIEW (List)
                    if (isSmallScreen) {
                      return MobileListView(
                        status: status,
                        getLocalSecondsSincePoll: () =>
                            provider.localSecondsSincePoll,
                      );
                    }

                    // DESKTOP/KIOSK VIEW (Physics)
                    return Stack(
                      children: [
                        // Main Layout
                        PhysicsLayout(
                              status: status,
                              getLocalSecondsSincePoll: () =>
                                  provider.localSecondsSincePoll,
                            )
                            .animate(
                              controller: _shakeController,
                              autoPlay: false,
                            )
                            .shakeX(duration: 500.ms, hz: 4, amount: 10),

                        // Waitlist Overlay (Prominent & Adaptive)
                        if (status.queue.isNotEmpty)
                          Positioned(
                            top: 24,
                            right: 24,
                            left: isSmallScreen ? 24 : null, // Stretch on small
                            child:
                                Card(
                                      elevation: 8,
                                      shadowColor: Colors.orange.withValues(
                                        alpha: 0.5,
                                      ),
                                      color: Colors.grey[900],
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(
                                          color: Colors.orange,
                                          width: 2,
                                        ),
                                      ),
                                      child: Container(
                                        width: isSmallScreen ? null : 300,
                                        padding: const EdgeInsets.all(24.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.orange,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: const Icon(
                                                    Icons.people,
                                                    color: Colors.black,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                const Text(
                                                  "WAITLIST",
                                                  style: TextStyle(
                                                    color: Colors.orange,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 24,
                                                    letterSpacing: 1.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (!isSmallScreen) ...[
                                              const SizedBox(height: 24),
                                              const Text(
                                                "NEXT UP:",
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              ...status.queue
                                                  .take(4)
                                                  .map(
                                                    (name) => Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            12,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.05,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Text(
                                                            "${status.queue.indexOf(name) + 1}.",
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .orange
                                                                  .shade300,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontFamily:
                                                                  'monospace',
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 12,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              name, // Using name from queue list
                                                              style: const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                              if (status.queue.length > 4)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                  child: Center(
                                                    child: Text(
                                                      "+ ${status.queue.length - 4} more",
                                                      style: TextStyle(
                                                        color: Colors.grey[500],
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ] else ...[
                                              // Compact Mode
                                              const SizedBox(height: 12),
                                              Text(
                                                "${status.queue.length} students waiting...",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    )
                                    .animate(
                                      onPlay: (c) => c.repeat(reverse: true),
                                    )
                                    .shimmer(
                                      duration: 3.seconds,
                                      color: Colors.orange.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
