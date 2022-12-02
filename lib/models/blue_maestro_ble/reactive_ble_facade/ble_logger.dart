import 'dart:developer' as dev;

class BleLogger {
  static void log(String message) {
    dev.log('BleThermal log: $message');
  }
}