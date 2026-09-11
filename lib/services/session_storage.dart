import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart';

class SessionStorage {
  static String? get(String key) => getSessionItem(key);
  static void set(String key, String value) => setSessionItem(key, value);
  static void remove(String key) => removeSessionItem(key);
}
