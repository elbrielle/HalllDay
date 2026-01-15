import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/status_provider.dart';
import '../widgets/physics_layout.dart';
import '../widgets/mobile_list_view.dart';

class DisplayScreen extends StatefulWidget {
  final String token;

  const DisplayScreen({super.key, required this.token});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Connect to status stream/poll
      context.read<StatusProvider>().init(widget.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Default backup color
      body: LayoutBuilder(
        // Add LayoutBuilder to detect screen size
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 600;

          return Consumer<StatusProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.status == null) {
                return const Center(child: CircularProgressIndicator());
              }

              // Show offline error overlay when connection is lost
              if (!provider.isConnected) {
                return Container(
                  color: Colors.grey[900],
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 80,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "Connection Lost",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Reconnecting...",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final status = provider.status;
              if (status == null) {
                return const Center(
                  child: Text(
                    "Connecting to Display...",
                    style: TextStyle(color: Colors.white, fontSize: 32),
                  ),
                );
              }

              // MOBILE VIEW
              if (isSmallScreen) {
                return MobileListView(
                  status: status,
                  getLocalSecondsSincePoll: () =>
                      provider.localSecondsSincePoll,
                );
              }

              return Stack(
                children: [
                  // Rendering Physics Layout in DISPLAY MODE (Big Text, No Inputs)
                  PhysicsLayout(
                    status: status,
                    isDisplay: true,
                    getLocalSecondsSincePoll: () =>
                        provider.localSecondsSincePoll,
                  ),

                  // Waitlist Overlay (Parity with Kiosk)
                  if (status.queue.isNotEmpty)
                    Positioned(
                      // Adaptive positioning
                      bottom: isSmallScreen ? 16 : null,
                      top: isSmallScreen ? null : 24,
                      right: isSmallScreen ? 16 : 24,
                      left: isSmallScreen ? 16 : null,
                      child: Card(
                        elevation: 8,
                        shadowColor: Colors.orange.withValues(alpha: 0.5),
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(
                            color: Colors.orange,
                            width: 2,
                          ),
                        ),
                        child: Container(
                          // Adaptive width
                          width: isSmallScreen ? null : 350,
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
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
                                // Hide detailed list on very small screens if needed, or keep it
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
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              "${status.queue.indexOf(name) + 1}.",
                                              style: TextStyle(
                                                color: Colors.orange.shade300,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                if (status.queue.length > 4)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Center(
                                      child: Text(
                                        "+ ${status.queue.length - 4} more",
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ] else ...[
                                // Compact Mode for small screens
                                const SizedBox(height: 8),
                                Text(
                                  "${status.queue.length} waiting...",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
