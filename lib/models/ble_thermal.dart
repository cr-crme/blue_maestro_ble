import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_device_connector.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/constants.dart';
import '/models/ble_thermal_response.dart';

enum BleThermalStatusCode {
  success,
  couldNotInitializeDevice,
  bluetoothOff,
  locationPermissionNotGranted,
  couldNotScan,
  couldNotFindDevice,
  couldNotFindServices,
  couldNotConnect,
  couldNotTransmit,
  couldNotSubscribe,
  responseError,
  characteristicsAreNotReady,
  unknownError,
}

String errorCodeToString(BleThermalStatusCode errorCode) {
  if (errorCode == BleThermalStatusCode.couldNotInitializeDevice) {
    return 'Could not initialize the device';
  } else if (errorCode == BleThermalStatusCode.bluetoothOff) {
    return 'The bluetooth is off. Please turn it on';
  } else if (errorCode == BleThermalStatusCode.locationPermissionNotGranted) {
    return 'The location permission must be granted to the application to '
        'use bluetooth device';
  } else if (errorCode == BleThermalStatusCode.couldNotScan) {
    return 'Could not scan for bluetooth devices.\n'
        'Please make sure bluetooth is activated and Location '
        'permission are granted to the app';
  } else if (errorCode == BleThermalStatusCode.couldNotFindDevice) {
    return 'Could not find the device';
  } else if (errorCode == BleThermalStatusCode.couldNotFindServices) {
    return 'Could not find services';
  } else if (errorCode == BleThermalStatusCode.couldNotSubscribe) {
    return 'Could not subscribe to services';
  } else {
    return 'Unknown error';
  }
}

class BleLogger {
  static void log(String message) {
    dev.log('BleThermal log: $message');
  }
}

class BleThermal {
  BleThermal({this.mock = false});

  bool mock;

  bool isInitialized = false;
  late final FlutterReactiveBle _ble;
  late final BleScanner scanner;
  late final BleDeviceConnector connector;
  Map<String, QualifiedCharacteristic>? _characteristics;
  DiscoveredDevice? _bleDevice;

  final _transmitResponse = BleThermalResponse();

  Future<BleThermalStatusCode> tryInitialize(
      {maximumRetries = 0, retryTime = const Duration(seconds: 5)}) async {
    late BleThermalStatusCode result;
    for (int retry = 0; retry < maximumRetries + 1; retry++) {
      // Leave some time before retrying
      if (retry != 0) {
        BleLogger.log('Initialization failed, retrying '
            '${maximumRetries - retry} times (in $retryTime seconds)');
        await Future.delayed(retryTime);
      }

      result = await _tryInitialize();
      if (result == BleThermalStatusCode.success) return result;

      // If proper rights are not granted, there is no point retrying
      if (result == BleThermalStatusCode.bluetoothOff ||
          result == BleThermalStatusCode.locationPermissionNotGranted) {
        return result;
      }
    }

    // If we get there, the transmission failed
    return result;
  }

  Future<BleThermalStatusCode> _tryInitialize() async {
    ///
    /// Try initialize and connect to the BLE thermal device.
    /// Returns null on success, returns the error message otherwise

    // Starting device
    if (!isInitialized) {
      BleLogger.log('Initializing device');
      try {
        _ble = FlutterReactiveBle();
      } on Exception {
        return BleThermalStatusCode.couldNotInitializeDevice;
      }
      isInitialized = true;
      scanner = BleScanner(_ble);
      connector = BleDeviceConnector(_ble);
    }

    // If we already have all the necessary information
    if (_characteristics != null) return BleThermalStatusCode.success;

    if (_bleDevice == null) {
      _bleDevice = await _findDevice();
      if (_bleDevice == null) {
        if (scanner.currentState == ScannerState.bluetoothOffFailure) {
          return BleThermalStatusCode.bluetoothOff;
        } else if (scanner.currentState ==
            ScannerState.locationPermissionNotGranted) {
          return BleThermalStatusCode.locationPermissionNotGranted;
        } else {
          return BleThermalStatusCode.couldNotFindDevice;
        }
      }
    }

    final services = await _findServices(_ble, connector);
    if (services == null) return BleThermalStatusCode.couldNotFindServices;

    _characteristics = await _findCharacteristics(services);
    await _ble.requestMtu(deviceId: _bleDevice!.id, mtu: 64);

    BleLogger.log('Device is ready');
    return BleThermalStatusCode.success;
  }

  String get name => _bleDevice != null ? _bleDevice!.name : '';

  Future<void> connect(BleDeviceConnector connector) async {
    BleLogger.log('Connecting');
    if (_bleDevice == null) return;

    await connector.connect(_bleDevice!.id);
    await Future.delayed(const Duration(milliseconds: 1000));
  }

  Future<void> disconnect(BleDeviceConnector connector) async {
    BleLogger.log('Disconnecting');
    if (_bleDevice == null) return;

    connector.disconnect(_bleDevice!.id);
    await Future.delayed(const Duration(milliseconds: 1000));
  }

  Future<BleThermalStatusCode> transmit(
    String command, {
    int maximumRetries = 3,
    Duration retryTime = const Duration(seconds: 5),
    required Function(BleThermalResponse) onResponse,
  }) async {
    // Sanity check
    if (_characteristics == null) return BleThermalStatusCode.couldNotTransmit;
    BleThermalStatusCode result = BleThermalStatusCode.success;
    _transmitResponse.clear();

    try {
      await connect(connector);
    } on Exception {
      return BleThermalStatusCode.couldNotConnect;
    }

    // Register to the response
    // Prepare a listener to receive the response
    result = await listenAdvertisement(onResponse: onResponse);
    if (result != BleThermalStatusCode.success) return result;

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
          return BleThermalStatusCode.couldNotConnect;
        }
      }

      result = await _transmit(command);
      if (result == BleThermalStatusCode.success) break;
    }

    if (result != BleThermalStatusCode.success) {
      BleLogger.log('Transmission failed');
      return result;
    }

    return result;
  }

  Future<BleThermalStatusCode> _transmit(String command) async {
    // Send the data
    try {
      BleLogger.log('Transmitting request');
      await _ble.writeCharacteristicWithResponse(_characteristics!['tx']!,
          value: ascii.encode(command));
    } on Exception catch (e) {
      BleLogger.log((e as dynamic).message.message);
      return BleThermalStatusCode.couldNotTransmit;
    }

    return BleThermalStatusCode.success;
  }

  Future<BleThermalStatusCode> listenAdvertisement({
    String? command,
    required Function(BleThermalResponse) onResponse,
    Function(String)? onError,
  }) async {
    try {
      BleLogger.log('Subscribing to characteristics');
      _ble.subscribeToCharacteristic(_characteristics!['rx']!).listen((values) {
        BleLogger.log('Receiving response');
        _transmitResponse.add(values);
        onResponse(_transmitResponse);
      }).onError((e) {
        // This error usually does not affect the actual subscription
        BleLogger.log(e.message.message);
        if (onError != null) onError(e.message.message);
        return;
      });
    } on Exception {
      BleLogger.log('Could not subscribe');
      return BleThermalStatusCode.couldNotSubscribe;
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    return BleThermalStatusCode.success;
  }

  Future<DiscoveredDevice?> _findDevice() async {
    BleLogger.log('Finding devices');
    // Start the scanning if necessary
    if (scanner.currentState != ScannerState.devicesFound) {
      scanner.startScan([]);
      // Give the scanner a little bit of time
      await Future.delayed(const Duration(seconds: 1));
    }

    // TODO find using the serviceUuid (since it is more general)
    // scanner.connectToAdvertisingDevice(
    //         id: "",
    //         withServices: [Uuid.parse(ThermalDevice.mainServiceUuid)],
    //         prescanDuration: const Duration(seconds: 10));

    if (scanner.currentState != ScannerState.devicesFound) return null;

    final index =
        scanner.devices.indexWhere((e) => e.id == ThermalDevice.deviceId);
    if (index < 0) return null;

    // Cleaning the scanner
    scanner.stopScan();

    return scanner.devices[index];
  }

  Future<List<DiscoveredService>?> _findServices(
      FlutterReactiveBle ble, BleDeviceConnector connector) async {
    BleLogger.log('Finding services');
    try {
      return await ble.discoverServices(_bleDevice!.id);
    } on Exception {
      return null;
    }
  }

  Future<Map<String, QualifiedCharacteristic>?> _findCharacteristics(
      List<DiscoveredService> services) async {
    BleLogger.log('Finding characteristics');
    // Find the main service
    final service = services.firstWhere(
        (e) => e.serviceId.toString() == ThermalDevice.mainServiceUuid);
    final txCharacteristic = service.characteristics.firstWhere(
        (e) => e.characteristicId.toString() == ThermalDevice.txServiceUuid);
    final rxCharacteristic = service.characteristics.firstWhere(
        (e) => e.characteristicId.toString() == ThermalDevice.rxServiceUuid);

    return {
      'tx': QualifiedCharacteristic(
          characteristicId: txCharacteristic.characteristicId,
          serviceId: txCharacteristic.serviceId,
          deviceId: _bleDevice!.id),
      'rx': QualifiedCharacteristic(
          characteristicId: rxCharacteristic.characteristicId,
          serviceId: rxCharacteristic.serviceId,
          deviceId: _bleDevice!.id),
    };
  }
}
