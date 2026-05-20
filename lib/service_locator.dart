import 'services/api_service.dart';
import 'services/feed_cache_service.dart';
import 'services/timetable_cache_service.dart';
import 'services/attendance_cache_service.dart';
import 'services/subjects_cache_service.dart';
import 'services/update_service.dart';
import 'services/shorebird_service.dart';
import 'services/whats_new_service.dart';

/// Service locator for shared service instances.
/// This prevents creating multiple instances of the same service across the app,
/// reducing memory usage and improving performance.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Lazy-initialized services
  ApiService? _apiService;
  FeedCacheService? _feedCacheService;
  TimetableCacheService? _timetableCacheService;
  AttendanceCacheService? _attendanceCacheService;
  SubjectsCacheService? _subjectsCacheService;
  UpdateService? _updateService;
  ShorebirdService? _shorebirdService;
  WhatsNewService? _whatsNewService;

  // Getters for services
  ApiService get apiService {
    _apiService ??= ApiService();
    return _apiService!;
  }

  FeedCacheService get feedCacheService {
    _feedCacheService ??= FeedCacheService();
    return _feedCacheService!;
  }

  TimetableCacheService get timetableCacheService {
    _timetableCacheService ??= TimetableCacheService();
    return _timetableCacheService!;
  }

  AttendanceCacheService get attendanceCacheService {
    _attendanceCacheService ??= AttendanceCacheService();
    return _attendanceCacheService!;
  }

  SubjectsCacheService get subjectsCacheService {
    _subjectsCacheService ??= SubjectsCacheService();
    return _subjectsCacheService!;
  }

  UpdateService get updateService {
    _updateService ??= UpdateService();
    return _updateService!;
  }

  ShorebirdService get shorebirdService {
    _shorebirdService ??= ShorebirdService();
    return _shorebirdService!;
  }

  WhatsNewService get whatsNewService {
    _whatsNewService ??= WhatsNewService();
    return _whatsNewService!;
  }

  /// Reset all services (useful for testing or logout)
  void reset() {
    _apiService = null;
    _feedCacheService = null;
    _timetableCacheService = null;
    _attendanceCacheService = null;
    _subjectsCacheService = null;
    _updateService = null;
    _shorebirdService = null;
    _whatsNewService = null;
  }
}

/// Global service locator instance
final services = ServiceLocator();