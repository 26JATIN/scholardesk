// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// On web, intercept the browser back button using the popstate event
/// and history API. This pushes a dummy history entry so that pressing
/// browser back consumes that entry instead of leaving the site.
/// Flutter's internal Navigator will then handle popping modals.
void setupWebBackButton() {
  // Push an initial dummy state so there's always something to "go back" to
  html.window.history.pushState(null, '', html.window.location.href);
  
  // Listen for popstate (browser back/forward)
  html.window.onPopState.listen((event) {
    // Re-push the state so that the next back press is also caught
    html.window.history.pushState(null, '', html.window.location.href);
  });
}
