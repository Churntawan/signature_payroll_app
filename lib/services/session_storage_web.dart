import 'package:web/web.dart' as web;

String? getSessionItem(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void setSessionItem(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

void removeSessionItem(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}
