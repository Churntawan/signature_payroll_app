import 'package:flutter/foundation.dart';
import 'image_saver_stub.dart'
    if (dart.library.js_interop) 'image_saver_web.dart';

class ImageSaver {
  static void savePng(Uint8List bytes, String fileName) {
    savePngFile(bytes, fileName);
  }

  static void saveCsv(String content, String fileName) {
    saveCsvFile(content, fileName);
  }
}

