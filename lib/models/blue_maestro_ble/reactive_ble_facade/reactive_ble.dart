import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_device_connector.dart';
import 'ble_scanner.dart';
import 'ble_status_code.dart';
import 'ble_logger.dart';

abstract class ReactiveBle {
  bool isInitialized = false;
  late final FlutterReactiveBle _ble;
  late final BleScanner scanner;
  late final BleDeviceConnector connector;
  DiscoveredDevice? _bleDevice;
  String get deviceName => _bleDevice != null ? _bleDevice!.name : '';
  String get deviceId => _bleDevice != null ? _bleDevice!.id : '';

  ///
  /// Try to initialize a connexion to a BLE device. If [maximumRetries] is
  /// greater than 0, then this method tries again if it fails after waiting for
  /// [retryTime] seconds.
  ///
  Future<BleStatusCode> tryInitialize({
    maximumRetries = 0,
    retryTime = const Duration(seconds: 5),
    required String deviceMacToFind,
  }) async {
    late BleStatusCode result;
    for (int retry = 0; retry < maximumRetries + 1; retry++) {
      // Leave some time before retrying
      if (retry != 0) {
        BleLogger.log('Initialization failed, retrying '
            '${maximumRetries - retry} times (in $retryTime seconds)');
        await Future.delayed(retryTime);
      }

      result = await _tryInitialize(deviceMacToFind: deviceMacToFind);
      if (result == BleStatusCode.success) return result;

      // If proper rights are not granted, there is no point retrying
      if (result == BleStatusCode.bluetoothOff ||
          result == BleStatusCode.locationPermissionNotGranted) {
        return result;
      }
    }

    // If we get there, the transmission failed
    return result;
  }

  ///
  /// Performs the actual initialization BLE device.
  Future<BleStatusCode> _tryInitialize(
      {required String deviceMacToFind}) async {
    // Starting device
    if (!isInitialized) {
      BleLogger.log('Initializing device');
      try {
        _ble = FlutterReactiveBle();
      } on Exception {
        return BleStatusCode.couldNotInitializeDevice;
      }
      isInitialized = true;
      scanner = BleScanner(_ble);
      connector = BleDeviceConnector(_ble);
    }

    if (_bleDevice == null) {
      _bleDevice = await findDevice(deviceMacToFind);
      if (_bleDevice == null) {
        if (scanner.currentState == ScannerState.bluetoothOffFailure) {
          BleLogger.log('Failed to find devices: Bluetooth is off');
          return BleStatusCode.bluetoothOff;
        } else if (scanner.currentState ==
            ScannerState.locationPermissionNotGranted) {
          BleLogger.log(
              'Failed to find devices: location permission is not granted to the app');
          return BleStatusCode.locationPermissionNotGranted;
        } else {
          BleLogger.log('Failed to find devices');
          return BleStatusCode.couldNotFindDevice;
        }
      }
    }

    BleLogger.log('Device is ready');
    return BleStatusCode.success;
  }

  ///
  /// Find the requested device
  /// TODO find using the serviceUuid (since it is more general)
  ///
  Future<DiscoveredDevice?> findDevice(String deviceMacToFind) async {
    BleLogger.log('Finding devices');
    // Start the scanning if necessary
    if (scanner.currentState != ScannerState.devicesFound) {
      scanner.startScan([]);
      // Give the scanner a little bit of time
      await Future.delayed(const Duration(seconds: 1));
    }

    if (scanner.currentState != ScannerState.devicesFound) return null;

    final index = scanner.devices.indexWhere((e) => e.id == deviceMacToFind);
    if (index < 0) return null;

    // Cleaning the scanner
    scanner.stopScan();

    return scanner.devices[index];
  }

  ///
  /// Find the available services
  ///
  Future<List<DiscoveredService>?> findServices() async {
    BleLogger.log('Finding services');
    try {
      return await _ble.discoverServices(deviceId);
    } on Exception {
      BleLogger.log('Failed to find services');
      return null;
    }
  }

  Future<void> connect(BleDeviceConnector connector) async {
    BleLogger.log('Connecting');
    if (_bleDevice == null) return;

    await connector.connect(deviceId);
    await Future.delayed(const Duration(milliseconds: 1000));
  }

  Future<void> disconnect(BleDeviceConnector connector) async {
    BleLogger.log('Disconnecting');
    if (_bleDevice == null) return;

    connector.disconnect(deviceId);
    await Future.delayed(const Duration(milliseconds: 1000));
  }

  Future<BleStatusCode> transmit(
    String command,
    QualifiedCharacteristic characteristic, {
    int maximumRetries = 3,
    Duration retryTime = const Duration(seconds: 5),
  }) async {
    for (int retry = 0; retry < maximumRetries; retry++) {
      // Leave some time before retrying
      if (retry != 0) {
        BleLogger.log('Transmission failed, retrying '
            '${maximumRetries - retry} times (in ${retryTime.inSeconds} seconds)');
        await Future.delayed(retryTime);
        try {
          await disconnect(connector);
          await connect(connector);
        } on Exception {
          return BleStatusCode.couldNotConnect;
        }
      }

      // Send the data
      try {
        BleLogger.log('Transmitting request');
        await _ble.writeCharacteristicWithResponse(characteristic,
            value: ascii.encode(command));
        BleLogger.log('Transmission was successful');
        return BleStatusCode.success;
      } on Exception catch (e) {
        BleLogger.log((e as dynamic).message.message);
      }
    }

    BleLogger.log('Transmission failed');
    return BleStatusCode.couldNotTransmit;
  }

  Future<BleStatusCode> listenAdvertisement(
    QualifiedCharacteristic characteristic, {
    required Function(List<int>) onResponse,
    Function(String)? onError,
  }) async {
    try {
      BleLogger.log('Subscribing to characteristics');
      _ble.subscribeToCharacteristic(characteristic).listen((values) {
        BleLogger.log('Receiving response');
        onResponse(values);
      }).onError((e) {
        // This error usually does not affect the actual subscription
        BleLogger.log(e.message.message);
        if (onError != null) onError(e.message.message);
        return;
      });
    } on Exception {
      BleLogger.log('Could not subscribe');
      return BleStatusCode.couldNotSubscribe;
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    return BleStatusCode.success;
  }
}
