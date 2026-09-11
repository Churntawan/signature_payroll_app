final Map<String, String> _memoryStorage = {};

String? getSessionItem(String key) {
  return _memoryStorage[key];
}

void setSessionItem(String key, String value) {
  _memoryStorage[key] = value;
}

void removeSessionItem(String key) {
  _memoryStorage.remove(key);
}
