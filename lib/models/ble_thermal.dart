import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_device_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/constants.dart';

class BleThermal {
  String? lastError;
  bool isInitialized = false;
  late final FlutterReactiveBle _ble;
  late final BleScanner scanner;
  late final BleDeviceConnector connector;
  late final StreamSubscription<BleScannerState> _stateStream;
  List<DiscoveredDevice> _discoveredDevices = [];

  bool isScanning = false;
  Map<String, QualifiedCharacteristic>? _characteristics;
  DiscoveredDevice? _bleDevice;

  Future<String?> tryInitialize(
    BuildContext context, {
    Function(String errorMessage)? onErrorCallback,
  }) async {
    ///
    /// Try initialize and connect to the BLE thermal device.
    /// Returns null on success, returns the error message otherwise

    // Starting device
    if (!isInitialized) {
      try {
        _ble = FlutterReactiveBle();
      } on Exception {
        return 'Could not initialize the device';
      }
      isInitialized = true;
      scanner = BleScanner(_ble);
      _stateStream = scanner.state
          .listen((event) => _discoveredDevices = event.discoveredDevices);
      connector = BleDeviceConnector(_ble);
    }

    // If we already have all the necessary information
    if (_characteristics != null) return null;

    _bleDevice = await _findDevice();
    if (_bleDevice == null) return 'Could not find the device';

    final services =
        await _findServices(_ble, connector, onErrorCallback: onErrorCallback);
    if (services == null) return 'Could not find the services';

    _characteristics = await _findCharacteristics(services);

    return null;
  }

  String get name => _bleDevice != null ? _bleDevice!.name : '';

  Future<void> connect(BleDeviceConnector connector) async {
    if (_bleDevice != null) await connector.connect(_bleDevice!.id);
  }

  Future<void> disconnect(BleDeviceConnector connector) async {
    if (_bleDevice != null) connector.disconnect(_bleDevice!.id);
  }

  Future<bool> transmit(
    BuildContext context,
    String command, {
    Function(String)? responseCallback,
    Function(String errorMessage)? onErrorCallback,
  }) async {
    if (_characteristics == null) {
      _processError(connector, 'Characteristics are not ready',
          keepAlive: false, onErrorCallback: onErrorCallback);
      return false;
    }

    // Initiate connexion to BLE
    try {
      await connect(connector);
    } on Exception {
      _processError(connector, 'Error while connecting',
          keepAlive: false, onErrorCallback: onErrorCallback);
      return false;
    }

    // Prepare a listener before sending data
    try {
      _ble.subscribeToCharacteristic(_characteristics!['rx']!).listen((event) {
        // This automatically disconnect
        if (responseCallback != null) {
          responseCallback(String.fromCharCodes(event));
        }
      });
    } on Exception {
      _processError(connector, 'Could not set subscription',
          keepAlive: false, onErrorCallback: onErrorCallback);
      return false;
    }

    // Send the data
    try {
      await _ble.writeCharacteristicWithResponse(_characteristics!['tx']!,
          value: ascii.encode(command));
    } on Exception {
      _processError(connector, 'Could not transmit',
          keepAlive: false, onErrorCallback: onErrorCallback);
      return false;
    }

    await disconnect(connector);
    return true;
  }

  void _processError(
    BleDeviceConnector connector,
    String errorMessage, {
    required bool keepAlive,
    required Function(String errorMessage)? onErrorCallback,
  }) {
    if (onErrorCallback != null) onErrorCallback(errorMessage);
    if (!keepAlive) disconnect(connector);
  }

  Future<DiscoveredDevice?> _findDevice() async {
    // Start the scanning if necessary
    if (!isScanning) scanner.startScan([]);
    isScanning = true;
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
    isScanning = false;

    return _discoveredDevices[index];
  }

  Future<List<DiscoveredService>?> _findServices(
    FlutterReactiveBle ble,
    BleDeviceConnector connector, {
    Function(String errorMessage)? onErrorCallback,
  }) async {
    // Connect to the scanned device
    try {
      await connect(connector);
    } on Exception {
      _processError(
          connector, 'Error on first connection, retrying in 5 seconds',
          keepAlive: true, onErrorCallback: onErrorCallback);
      return null;
    }

    late final List<DiscoveredService> services;
    try {
      services = await ble.discoverServices(_bleDevice!.id);
    } on Exception {
      _processError(
          connector, 'Error on getting the services, retrying in 5 seconds',
          keepAlive: true, onErrorCallback: onErrorCallback);
      return null;
    }

    return services;
  }

  Future<Map<String, QualifiedCharacteristic>?> _findCharacteristics(
      List<DiscoveredService> services) async {
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
