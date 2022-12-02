import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:meta/meta.dart';

enum ScannerState {
  idle,
  scanning,
  devicesFound,
  locationPermissionNotGranted,
  bluetoothOffFailure,
  unknownFailure,
}

class BleScanner {
  BleScanner(this._ble);

  ScannerState currentState = ScannerState.idle;
  final FlutterReactiveBle _ble;
  final StreamController<BleScannerState> _stateStreamController =
      StreamController();

  final devices = <DiscoveredDevice>[];

  void startScan(List<Uuid> serviceIds) {
    devices.clear();
    _subscription?.cancel();
    currentState = ScannerState.scanning;

    _subscription =
        _ble.scanForDevices(withServices: serviceIds).listen((device) {
      final knownDeviceIndex = devices.indexWhere((d) => d.id == device.id);
      if (knownDeviceIndex >= 0) {
        devices[knownDeviceIndex] = device;
      } else {
        devices.add(device);
      }
      currentState = ScannerState.devicesFound;
      _pushState();
    })
          ..onError((e, StackTrace s) {
            if (e.message.message == 'Bluetooth disabled (code 1)') {
              currentState = ScannerState.bluetoothOffFailure;
            } else if (e.message.message ==
                'Location Permission missing (code 3)') {
              currentState = ScannerState.locationPermissionNotGranted;
            } else {
              currentState = ScannerState.unknownFailure;
            }
            return stopScan();
          });
    _pushState();
  }

  void _pushState() {
    _stateStreamController.add(
      BleScannerState(
        discoveredDevices: devices,
        scanIsInProgress: _subscription != null,
      ),
    );
  }

  Future<void> stopScan() async {
    await _subscription?.cancel();
    _subscription = null;
    _pushState();
  }

  Future<void> dispose() async {
    await _stateStreamController.close();
  }

  StreamSubscription? _subscription;
}

@immutable
class BleScannerState {
  const BleScannerState({
    required this.discoveredDevices,
    required this.scanIsInProgress,
  });

  final List<DiscoveredDevice> discoveredDevices;
  final bool scanIsInProgress;
}
