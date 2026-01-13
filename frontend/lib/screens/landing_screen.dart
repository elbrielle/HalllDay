import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:web/web.dart' as web;
import '../widgets/app_nav_drawer.dart';
import 'dart:ui' as ui; // ignore: library_prefixes
import 'dart:ui_web' as ui_web;

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _faqKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Register YouTube view factory for Web
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory('youtube-video', (
      int viewId,
    ) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.src =
          'https://www.youtube.com/embed/L8NvFc-F5EU?si=Xu21FymPx2G17ppY';
      iframe.style.border = 'none';
      iframe.setAttribute(
        'allow',
        'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share',
      );
      iframe.setAttribute('allowfullscreen', 'true');
      return iframe;
    });
  }

  void _scrollToFAQ() {
    final context = _faqKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const AppNavDrawer(currentRoute: '/'),
      body: Stack(
        children: [
          // Background Blobs
          Positioned(
            top: -100,
            left: -100,
            child: _BlurBlob(color: Colors.green.shade200, size: 400),
          ),
          Positioned(
            top: 200,
            right: -150,
            child: _BlurBlob(color: Colors.orange.shade200, size: 500),
          ),
          Positioned(
            bottom: -100,
            left: 100,
            child: _BlurBlob(color: Colors.blue.shade100, size: 300),
          ),

          // Content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar.large(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "IDK Can You?",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "BETA",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                centerTitle: true,
                backgroundColor: Colors.white.withValues(alpha: 0.5),
                surfaceTintColor: Colors.transparent,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: TextButton.icon(
                      onPressed: () {
                        web.window.location.href = '/admin/login';
                      },
                      icon: const Icon(Icons.login),
                      label: const Text("Log In"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 48.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Hero Section
                      Column(
                            children: [
                              // Prefer a real logo if it exists at the server root.
                              // Bundled as a Flutter asset for reliability (web + mobile).
                              // SVG Logo for perfect scaling
                              Image.asset(
                                    'assets/brand/logo.png',
                                    height: 100, // Adjusted height for balance
                                    fit: BoxFit
                                        .contain, // Ensure it's never cut off
                                  )
                                  .animate(
                                    onPlay: (controller) =>
                                        controller.repeat(reverse: true),
                                  )
                                  .moveY(
                                    begin: 0,
                                    end: -10,
                                    duration: 3.seconds,
                                    curve: Curves.easeInOut,
                                  ),
                              const SizedBox(height: 28),
                              Text(
                                "Fixing the part of classroom management everyone hates dealing with.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                  letterSpacing: -2.0,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 600,
                                ),
                                child: const Text(
                                  "Track time, manage queues, and see who’s out.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Colors.black54,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 48),

                              // CTA Buttons (clear hierarchy)
                              Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () {
                                      web.window.location.href = '/admin/login';
                                    },
                                    icon: const Icon(Icons.dashboard_rounded),
                                    label: const Text("Teacher Dashboard"),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.onPrimary,
                                      textStyle: const TextStyle(fontSize: 18),
                                      elevation: 2,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _scrollToFAQ,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.black87,
                                      textStyle: const TextStyle(fontSize: 18),
                                    ),
                                    child: const Text("How it works"),
                                  ),
                                ],
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 520.ms, curve: Curves.easeOutCubic)
                          .slideY(
                            begin: 0.06,
                            end: 0,
                            duration: 520.ms,
                            curve: Curves.easeOutCubic,
                          ),

                      const SizedBox(height: 64),

                      // Video Embed
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 30,
                                  offset: Offset(0, 15),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: const AspectRatio(
                              aspectRatio: 16 / 9,
                              child: HtmlElementView(viewType: 'youtube-video'),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 96),

                      // Room Entry Card (more sculptural + accent for focus/action)
                      ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    "Enter your room",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Type the room code your teacher gives you.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _TokenInput(accent: cs.primary),
                                ],
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 220.ms, duration: 520.ms)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            delay: 220.ms,
                            duration: 520.ms,
                            curve: Curves.easeOutCubic,
                          ),

                      const SizedBox(height: 128),

                      // FAQ Section
                      Container(key: _faqKey),
                      const Text(
                        "Before you ask",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          children: [
                            _FAQItem(
                              icon: Icons.app_registration_rounded,
                              accent: cs.primary,
                              "1. Set up Admin",
                              "Sign in as a teacher. Create your room slug (e.g. 'mr-smith'), set your rules, and upload your roster if you want.",
                            ),
                            _FAQItem(
                              icon: Icons.devices_other_rounded,
                              accent: cs.secondary,
                              "2. Launch Kiosk",
                              "Open the Kiosk URL (/kiosk/your-slug) on a dedicated device (iPad, Chromebook). Students use this to scan or type their ID to leave.",
                            ),
                            _FAQItem(
                              icon: Icons.tv_rounded,
                              accent: cs.tertiary,
                              "3. Launch Display (Optional)",
                              "Open the Display URL (/display/your-slug) on your projector or a second screen. This shows the live list of who is out and the waitlist.",
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 96),
                      const Divider(),
                      const SizedBox(height: 24),
                      const Text(
                        "© 2025 IDK Can You? • Elisha Lucero",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlurBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(
              alpha: 0.0,
            ), // Transparent container to clip blur?
          ),
        ),
      ),
    );
  }
}

class _TokenInput extends StatefulWidget {
  final Color accent;

  const _TokenInput({required this.accent});

  @override
  State<_TokenInput> createState() => _TokenInputState();
}

class _TokenInputState extends State<_TokenInput> {
  final _ctrl = TextEditingController();

  void _go() {
    final token = _ctrl.text.trim();
    if (token.isNotEmpty) {
      web.window.location.href = '/kiosk/$token';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: "e.g. 101 or B-204",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            onSubmitted: (_) => _go(),
          ),
        ),
        const SizedBox(width: 12),
        _PressableIconButton(
          onPressed: _go,
          backgroundColor: widget.accent,
          foregroundColor: Colors.white,
          icon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }
}

class _FAQItem extends StatefulWidget {
  final String question;
  final String answer;
  final Color accent;
  final IconData icon;

  const _FAQItem(
    this.question,
    this.answer, {
    required this.accent,
    required this.icon,
  });

  @override
  State<_FAQItem> createState() => _FAQItemState();
}

class _FAQItemState extends State<_FAQItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _open ? widget.accent.withValues(alpha: 0.22) : Colors.black12,
          width: _open ? 1.5 : 1,
        ),
        boxShadow: [
          if (_open)
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: widget.accent, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.question,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: _open
                            ? widget.accent.withValues(alpha: 0.9)
                            : Colors.black45,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Animate(
                            effects: [
                              FadeEffect(
                                duration: 220.ms,
                                curve: Curves.easeOutCubic,
                              ),
                              SlideEffect(
                                duration: 220.ms,
                                curve: Curves.easeOutCubic,
                                begin: const Offset(0, 0.02),
                                end: Offset.zero,
                              ),
                            ],
                            child: Text(
                              widget.answer,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PressableIconButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;

  const _PressableIconButton({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
  });

  @override
  State<_PressableIconButton> createState() => _PressableIconButtonState();
}

class _PressableIconButtonState extends State<_PressableIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              if (!_pressed)
                BoxShadow(
                  color: widget.backgroundColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
            ],
          ),

          child: Icon(widget.icon, color: widget.foregroundColor),
        ),
      ),
    );
  }
}
