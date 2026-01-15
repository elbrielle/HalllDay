import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'providers/status_provider.dart';
import 'screens/display_screen.dart';
import 'screens/kiosk_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/dev_screen.dart';
import 'screens/landing_screen.dart';

void main() {
  setUrlStrategy(PathUrlStrategy());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandSeed = Color(0xFF00C853); // Brand accent (used intentionally)

    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => StatusProvider())],
      child: MaterialApp(
        title: 'IDK Can You?',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: brandSeed,
            brightness: Brightness.light,
          ),
          fontFamily: 'Inter',
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.grey[900],
            contentTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade800),
            ),
            insetPadding: const EdgeInsets.all(24),
            elevation: 8,
          ),
        ),
        // Simple manual routing for now
        onGenerateRoute: (settings) {
          final uri = Uri.parse(settings.name ?? '/');

          // Handle Root Path (Landing Page)
          if (uri.pathSegments.isEmpty) {
            return MaterialPageRoute(builder: (_) => const LandingScreen());
          }

          if (uri.pathSegments.isNotEmpty) {
            final first = uri.pathSegments[0];

            // Handle /kiosk/<token> or /k/<token>
            if (first == 'kiosk' || first == 'k') {
              if (uri.pathSegments.length > 1) {
                final token = uri.pathSegments[1];
                return MaterialPageRoute(
                  builder: (_) => KioskScreen(token: token),
                );
              }
            }

            // Handle /display/<token> or /d/<token>
            if (first == 'display' || first == 'd') {
              if (uri.pathSegments.length > 1) {
                final token = uri.pathSegments[1];
                return MaterialPageRoute(
                  builder: (_) => DisplayScreen(token: token),
                );
              }
            }

            // Handle /admin (No token, uses Session)
            if (first == 'admin') {
              return MaterialPageRoute(builder: (_) => const AdminScreen());
            }

            // Handle /dev (No token, internal auth)
            if (first == 'dev') {
              return MaterialPageRoute(builder: (_) => const DevScreen());
            }
          }

          // Default fallback (e.g. landing page or error)
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Text(
                  "Invalid URL\nUse /kiosk/<token>",
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
