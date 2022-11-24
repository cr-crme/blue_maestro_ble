import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

String bleStatusToText(BleStatus status) {
  switch (status) {
    case BleStatus.unsupported:
      return "This device does not support Bluetooth";
    case BleStatus.unauthorized:
      return "Authorize the FlutterReactiveBle example app to use Bluetooth and location";
    case BleStatus.poweredOff:
      return "Bluetooth is powered off on your device turn it on";
    case BleStatus.locationServicesDisabled:
      return "Enable location services";
    case BleStatus.ready:
      return "Bluetooth is up and running";
    default:
      return "Waiting to fetch Bluetooth status $status";
  }
}
