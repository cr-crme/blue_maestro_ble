import 'dart:async';
import 'dart:developer' as dev;
import 'dart:convert';

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_device_connector.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/constants.dart';

enum BleThermalStatusCode {
  success,
  couldNotInitializeDevice,
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
  late final StreamSubscription<BleScannerState> _stateStream;
  List<DiscoveredDevice> _discoveredDevices = [];
  Map<String, QualifiedCharacteristic>? _characteristics;
  DiscoveredDevice? _bleDevice;

  List<int> responseLog = [];

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

      // If scan failed, it means rights are not granted, there is no point
      // retrying. So we return now.
      if (result == BleThermalStatusCode.couldNotScan) return result;
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
      _stateStream = scanner.state
          .listen((event) => _discoveredDevices = event.discoveredDevices);
      connector = BleDeviceConnector(_ble);
    }

    // If we already have all the necessary information
    if (_characteristics != null) return BleThermalStatusCode.success;

    if (_bleDevice == null) {
      _bleDevice = await _findDevice();
      if (_bleDevice == null) {
        if (!scanner.isScanning) return BleThermalStatusCode.couldNotScan;
        return BleThermalStatusCode.couldNotFindDevice;
      }
    }

    final services = await _findServices(_ble, connector);
    if (services == null) return BleThermalStatusCode.couldNotFindServices;

    _characteristics = await _findCharacteristics(services);
    await _ble.requestMtu(deviceId: _bleDevice!.id, mtu: 64);

    return BleThermalStatusCode.success;
  }

  String get name => _bleDevice != null ? _bleDevice!.name : '';

  Future<void> connect(BleDeviceConnector connector) async {
    BleLogger.log('Connecting');
    if (_bleDevice != null) await connector.connect(_bleDevice!.id);
  }

  Future<void> disconnect(BleDeviceConnector connector) async {
    BleLogger.log('Disconnecting');
    if (_bleDevice != null) connector.disconnect(_bleDevice!.id);
  }

  Future<BleThermalStatusCode> transmit(String command,
      {maximumRetries = 3,
      retryTime = const Duration(seconds: 5),
      required Function(List<int>) onResponse}) async {
    // Sanity check
    if (_characteristics == null) return BleThermalStatusCode.couldNotTransmit;

    // Register to the response
    // Prepare a listener to receive the response
    final resultAdvertising = await listenAdvertisement(onResponse: onResponse);
    if (resultAdvertising != BleThermalStatusCode.success) {
      return resultAdvertising;
    }

    late BleThermalStatusCode result;
    for (int retry = 0; retry < maximumRetries; retry++) {
      // Leave some time before retrying
      if (retry != 0) {
        BleLogger.log('Transmission failed, retrying '
            '${maximumRetries - retry} times (in $retryTime seconds)');
        await Future.delayed(retryTime);
      }

      result = await _transmit(command);
      if (result == BleThermalStatusCode.success) return result;
    }

    return result;
  }

  Future<BleThermalStatusCode> _transmit(String command) async {
    // Initiate connexion to BLE
    try {
      await connect(connector);
    } on Exception {
      return BleThermalStatusCode.couldNotConnect;
    }

    // Send the data
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      BleLogger.log('Transmitting request');
      await _ble.writeCharacteristicWithResponse(_characteristics!['tx']!,
          value: ascii.encode(command));
    } on Exception {
      return BleThermalStatusCode.couldNotTransmit;
    }

    return BleThermalStatusCode.success;
  }

  Future<BleThermalStatusCode> listenAdvertisement(
      {required Function(List<int>) onResponse}) async {
    try {
      BleLogger.log('Subscribing to characteristics');
      _ble.subscribeToCharacteristic(_characteristics!['rx']!).listen((values) {
        BleLogger.log('Receiving response');
        BleLogger.log(values.toString());
        responseLog += values;
        onResponse(values);
      }).onError((Object e) => BleThermalStatusCode.responseError);
    } on Exception {
      return BleThermalStatusCode.couldNotSubscribe;
    }
    return BleThermalStatusCode.success;
  }

  Future<DiscoveredDevice?> _findDevice() async {
    BleLogger.log('Finding devices');
    // Start the scanning if necessary
    if (!scanner.isScanning) scanner.startScan([]);

    // TODO find using the serviceUuid (since it is more general)
    // scanner.connectToAdvertisingDevice(
    //         id: "",
    //         withServices: [Uuid.parse(ThermalDevice.mainServiceUuid)],
    //         prescanDuration: const Duration(seconds: 10));

    if (_discoveredDevices.isEmpty) return null;

    final index =
        _discoveredDevices.indexWhere((e) => e.id == ThermalDevice.deviceId);
    if (index < 0) return null;

    // Cleaning the scanner
    _stateStream.cancel();
    scanner.stopScan();

    return _discoveredDevices[index];
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
