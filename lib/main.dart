import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'screens/school_code_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'services/update_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'widgets/web_phone_mockup.dart';

// Conditional import for HTTP overrides (only on native platforms)
import 'services/http_client_stub.dart'
    if (dart.library.io) 'services/http_client_native.dart'
    if (dart.library.html) 'services/http_client_web.dart';

// Global theme service instance
final themeService = ThemeService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system UI overlay style for Material 3
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  // Enable edge-to-edge mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // Setup HTTP overrides (only does something on native platforms)
  setupHttpOverrides();
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Cache the session future to prevent re-fetching on theme change
  late Future<Map<String, dynamic>?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = ApiService().getSession();
    WidgetsBinding.instance.addObserver(this);
    themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Attempt to clean any pending APK after returning to the app
      try {
        // Only run on native platforms (no-op on web)
        if (!kIsWeb) {
          UpdateService().cleanPendingApk();
        }
      } catch (e) {
        debugPrint('⚠️ Error during lifecycle cleanup: $e');
      }
    }
  }

  void _onThemeChanged() {
    setState(() {});
    // Update system UI based on theme
    final isDark = themeService.themeMode == ThemeMode.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScholarDesk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeService.themeMode,
      // Use clamping scroll physics on web (better iOS Safari performance)
      // and bouncing physics on native mobile for natural feel
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      ),
      builder: (context, child) {
        // Wrap in phone mockup for web
        return WebPhoneMockup(
          child: child ?? const SizedBox(),
        );
      },
      home: FutureBuilder<Map<String, dynamic>?>(
        future: _sessionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator.adaptive(),
              ),
            );
          } else if (snapshot.hasData && snapshot.data != null) {
            final session = snapshot.data!;
            return HomeScreen(
              clientDetails: session['clientDetails'],
              userData: session['userData'],
            );
          } else {
            return const SchoolCodeScreen();
          }
        },
      ),
    );
  }
}
