import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// A screen that loads the Chitkara University website inside a WebView.
/// Handles the login → captcha → OTP → dashboard flow entirely within the WebView.
class WebLoginScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const WebLoginScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  String _currentUrl = '';
  String _pageTitle = 'Website';
  double _progress = 0;

  /// Build the login URL from client details
  String get _loginUrl {
    final clientAbbr = widget.clientDetails['client_abbr'];
    final baseUrl = widget.clientDetails['baseUrl'];
    return 'https://$clientAbbr.$baseUrl/loginManager/load';
  }

  /// CSS to inject to force the captcha to show immediately and make the login page look like the native app
  String get _loginPageCSS => '''
    (function() {
      var style = document.createElement('style');
      style.innerHTML = `
        body {
          margin: 0 !important;
          padding: 0 !important;
          background: #f5f7fa !important;
          min-height: 100vh !important;
          font-family: 'Outfit', 'Inter', Arial, sans-serif !important;
        }
        table[width="990px"], table[width="100%"] {
          width: 100vw !important;
          max-width: 100vw !important;
        }
        /* Hide the left spacer div, show only login form */
        div[style*="width:685px"] {
          display: none !important;
        }
        div[style*="width:285px"] {
          width: 100vw !important;
          max-width: 100vw !important;
          float: none !important;
          margin: 0 auto !important;
          border: none !important;
          height: auto !important;
          padding: 0 !important;
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          min-height: 100vh !important;
        }
        /* Card style for login */
        form[action*="checkLogin"] {
          background: #fff !important;
          border-radius: 24px !important;
          box-shadow: 0 6px 32px 0 rgba(23,62,135,0.10), 0 1.5px 6px 0 rgba(23,62,135,0.08) !important;
          padding: 32px 20px 28px 20px !important;
          max-width: 340px !important;
          margin: 0 auto !important;
          display: flex !important;
          flex-direction: column !important;
          align-items: center !important;
        }
        /* Headings */
        form[action*="checkLogin"] td[colspan="2"] {
          font-size: 22px !important;
          font-weight: 700 !important;
          color: #173e87 !important;
          text-align: center !important;
          padding-bottom: 18px !important;
        }
        /* Inputs */
        input[type="text"], input[type="password"], select {
          width: 100% !important;
          max-width: 260px !important;
          height: 44px !important;
          font-size: 16px !important;
          border-radius: 10px !important;
          border: 1.5px solid #e0e7ef !important;
          margin-bottom: 16px !important;
          padding: 0 14px !important;
          background: #f8fafc !important;
          color: #173e87 !important;
          box-sizing: border-box !important;
        }
        input[type="text"]:focus, input[type="password"]:focus {
          border-color: #173e87 !important;
          outline: none !important;
        }
        /* Login button */
        input[type="image"] {
          width: 100% !important;
          max-width: 260px !important;
          height: 44px !important;
          border-radius: 10px !important;
          background: #173e87 !important;
          box-shadow: 0 2px 8px 0 rgba(23,62,135,0.08) !important;
          margin-top: 8px !important;
          margin-bottom: 8px !important;
          object-fit: contain !important;
        }
        /* Hide the top red bar and app store links  */
        div[style*="height:6px"], div[style*="App Store"], div[style*="Google Play"] {
          display: none !important;
        }
        /* Hide privacy policy, powered by, and mobile app code area */
        a[href*="privacy"], a[href*="Privacy"], a[onclick*="privacy"],
        div[style*="privacy"], div[style*="Privacy"],
        div[style*="powered by"], div[style*="Powered by"],
        div[style*="app icon"], div[style*="App Icon"],
        div[style*="mobile app"], div[style*="Mobile App"],
        div[style*="download the app"], div[style*="Download the App"],
        div[style*="code area"], div[style*="Code Area"],
        div[style*="badge"], div[style*="Badge"],
        img[alt*="app icon"], img[alt*="App Icon"],
        img[alt*="powered by"], img[alt*="Powered by"],
        img[alt*="badge"], img[alt*="Badge"] {
          display: none !important;
        }
        /* Hide any links or text mentioning privacy, powered by, or mobile app */
        span:contains('Privacy'), span:contains('privacy'),
        span:contains('Powered by'), span:contains('powered by'),
        span:contains('Mobile App'), span:contains('mobile app'),
        td:contains('Privacy'), td:contains('privacy'),
        td:contains('Powered by'), td:contains('powered by'),
        td:contains('Mobile App'), td:contains('mobile app') {
          display: none !important;
        }
        /* Captcha always visible and styled */
        #showRecaptcha {
          display: table-row !important;
        }
        .g-recaptcha {
          transform: scale(0.95);
          transform-origin: 0 0;
          margin: 0 auto 10px auto !important;
        }
        /* Hide Code Brigade top-right/left icon */
        div[style*="position:absolute"][style*="right:10px"],
        div[style*="position:absolute"][style*="left:10px"] {
          display: none !important;
        }
        /* Error message styling */
        .alert-danger, .alert {
          background: #ffeaea !important;
          color: #dc2626 !important;
          border-radius: 8px !important;
          padding: 10px 14px !important;
          margin-bottom: 12px !important;
          font-size: 15px !important;
        }
        /* Remove all table borders */
        table, tr, td {
          border: none !important;
        }
      `;
      document.head.appendChild(style);
    })();
  ''';

  /// CSS to inject for the OTP page to make it match the native app style
  String get _otpPageCSS => '''
    (function() {
      var style = document.createElement('style');
      style.innerHTML = `
        body {
          margin: 0 !important;
          padding: 0 !important;
          background: #f5f7fa !important;
          min-height: 100vh !important;
          font-family: 'Outfit', 'Inter', Arial, sans-serif !important;
        }
        #mainTable, table[width="100%"] {
          width: 100vw !important;
          max-width: 100vw !important;
        }
        table.corner_curves {
          height: auto !important;
          min-height: 400px !important;
          background: none !important;
        }
        /* Card style for OTP */
        form[name="form1"] {
          background: #fff !important;
          border-radius: 24px !important;
          box-shadow: 0 6px 32px 0 rgba(23,62,135,0.10), 0 1.5px 6px 0 rgba(23,62,135,0.08) !important;
          padding: 32px 20px 28px 20px !important;
          max-width: 340px !important;
          margin: 0 auto !important;
          display: flex !important;
          flex-direction: column !important;
          align-items: center !important;
        }
        /* OTP heading */
        form[name="form1"] td[colspan="2"] {
          font-size: 22px !important;
          font-weight: 700 !important;
          color: #173e87 !important;
          text-align: center !important;
          padding-bottom: 18px !important;
        }
        /* OTP input */
        input[name="OTPText"] {
          width: 180px !important;
          height: 44px !important;
          font-size: 22px !important;
          border-radius: 12px !important;
          border: 1.5px solid #e0e7ef !important;
          background: #f8fafc !important;
          color: #173e87 !important;
          text-align: center !important;
          letter-spacing: 10px !important;
          margin-bottom: 18px !important;
        }
        input[name="OTPText"]:focus {
          border-color: #173e87 !important;
          outline: none !important;
        }
        /* OTP submit button */
        input[type="submit"], .submitBtn, .button_wide {
          width: 100% !important;
          max-width: 220px !important;
          height: 44px !important;
          font-size: 16px !important;
          border-radius: 10px !important;
          background: #173e87 !important;
          color: #fff !important;
          font-weight: 600 !important;
          box-shadow: 0 2px 8px 0 rgba(23,62,135,0.08) !important;
          margin-top: 8px !important;
          margin-bottom: 8px !important;
          border: none !important;
        }
        /* Timer, resend, parent OTP links */
        #timer, #resendOtp, #parentOtp {
          font-size: 15px !important;
          color: #173e87 !important;
          margin-bottom: 10px !important;
        }
        /* Hide privacy policy, powered by, and mobile app code area */
        a[href*="privacy"], a[href*="Privacy"], a[onclick*="privacy"],
        div[style*="privacy"], div[style*="Privacy"],
        div[style*="powered by"], div[style*="Powered by"],
        div[style*="app icon"], div[style*="App Icon"],
        div[style*="mobile app"], div[style*="Mobile App"],
        div[style*="download the app"], div[style*="Download the App"],
        div[style*="code area"], div[style*="Code Area"],
        div[style*="badge"], div[style*="Badge"],
        img[alt*="app icon"], img[alt*="App Icon"],
        img[alt*="powered by"], img[alt*="Powered by"],
        img[alt*="badge"], img[alt*="Badge"] {
          display: none !important;
        }
        /* Hide any links or text mentioning privacy, powered by, or mobile app */
        span:contains('Privacy'), span:contains('privacy'),
        span:contains('Powered by'), span:contains('powered by'),
        span:contains('Mobile App'), span:contains('mobile app'),
        td:contains('Privacy'), td:contains('privacy'),
        td:contains('Powered by'), td:contains('powered by'),
        td:contains('Mobile App'), td:contains('mobile app') {
          display: none !important;
        }
        /* Error message styling */
        .alert-danger, .alert {
          background: #ffeaea !important;
          color: #dc2626 !important;
          border-radius: 8px !important;
          padding: 10px 14px !important;
          margin-bottom: 12px !important;
          font-size: 15px !important;
        }
        /* Remove all table borders */
        table, tr, td {
          border: none !important;
        }
      `;
      document.head.appendChild(style);
    })();
  ''';

  /// Determine the current page state from the URL
  _PageState _getPageState(String url) {
    if (url.contains('loginManager/load') || url.contains('loginManager/checkLogin')) {
      return _PageState.login;
    } else if (url.contains('multiAuthentication')) {
      return _PageState.otp;
    } else if (url.contains('/main') || url.contains('dashboardFeed')) {
      return _PageState.dashboard;
    }
    return _PageState.unknown;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Don't allow on web (use browser directly)
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Website')),
        body: const Center(
          child: Text('Please use the browser directly for the website.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pageTitle,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (_currentUrl.isNotEmpty)
              Text(
                Uri.tryParse(_currentUrl)?.host ?? '',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_loginUrl),
              ),
              initialSettings: InAppWebViewSettings(
                // Allow JavaScript
                javaScriptEnabled: true,
                // Allow mixed content for captcha
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                // Mobile user-agent for proper rendering
                userAgent:
                    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                // Enable DOM storage for the website's jQuery
                domStorageEnabled: true,
                // Support zoom
                supportZoom: true,
                builtInZoomControls: false,
                // Allow file access
                allowFileAccess: true,
                // Disable cache for fresh login
                cacheEnabled: false,
                // Clear cache on start
                clearCache: true,
                // Use wide viewport for desktop-style pages
                useWideViewPort: false,
                loadWithOverviewMode: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                if (mounted) {
                  setState(() {
                    _isLoading = true;
                    _currentUrl = url?.toString() ?? '';
                  });
                }
              },
              onLoadStop: (controller, url) async {
                if (!mounted) return;

                final urlStr = url?.toString() ?? '';
                final pageState = _getPageState(urlStr);

                setState(() {
                  _isLoading = false;
                  _currentUrl = urlStr;
                });

                // Inject CSS based on page state
                switch (pageState) {
                  case _PageState.login:
                    setState(() => _pageTitle = 'Login');
                    await controller.evaluateJavascript(source: _loginPageCSS);
                    break;
                  case _PageState.otp:
                    setState(() => _pageTitle = 'OTP Verification');
                    await controller.evaluateJavascript(source: _otpPageCSS);
                    break;
                  case _PageState.dashboard:
                    setState(() => _pageTitle = 'Dashboard');
                    // Successfully reached dashboard!
                    _showSuccessAndStay();
                    break;
                  case _PageState.unknown:
                    // Try to get page title
                    final title = await controller.getTitle();
                    if (mounted && title != null && title.isNotEmpty) {
                      setState(() => _pageTitle = title);
                    }
                    break;
                }
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() {
                    _progress = progress / 100;
                  });
                }
              },
              onReceivedError: (controller, request, error) {
                debugPrint('WebView error: ${error.description}');
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('WebView console: ${consoleMessage.message}');
              },
            ),
            // Loading overlay only on initial load
            if (_isLoading && _progress < 0.3)
              Container(
                color: isDark
                    ? AppTheme.darkSurfaceColor.withOpacity(0.8)
                    : Colors.white.withOpacity(0.8),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Show success snackbar when dashboard is reached
  void _showSuccessAndStay() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(child: Text('Successfully logged in to website!')),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Possible page states in the login flow
enum _PageState {
  login,
  otp,
  dashboard,
  unknown,
}
