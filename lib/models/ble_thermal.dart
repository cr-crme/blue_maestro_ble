import 'dart:async';
import 'dart:developer' as dev;
import 'dart:convert';

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_device_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/constants.dart';

enum BleThermalStatusCode {
  success,
  couldNotInitializeDevice,
  couldNotFindDevice,
  couldNotFetchServices,
  couldNotFindServices,
  couldNotConnect,
  couldNotTransmit,
  couldNotSubscribe,
  characteristicsAreNotReady,
  unknownError,
}

class BleLogger {
  static void log(String message) {
    dev.log('BleThermal log: $message');
  }
}

class BleThermal {
  BleThermal({this.mock = false});

  bool mock;
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

  Future<BleThermalStatusCode> tryInitialize(
    BuildContext context, {
    Function(BleThermalStatusCode status)? onErrorCallback,
  }) async {
    ///
    /// Try initialize and connect to the BLE thermal device.
    /// Returns null on success, returns the error message otherwise

    // Starting device
    if (!isInitialized) {
      BleLogger.log('Initializing device');
      try {
        _ble = FlutterReactiveBle();
      } catch (_) {
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

    _bleDevice = await _findDevice();
    if (_bleDevice == null) return BleThermalStatusCode.couldNotFindDevice;

    final services =
        await _findServices(_ble, connector, onErrorCallback: onErrorCallback);
    if (services == null) return BleThermalStatusCode.couldNotFindServices;

    _characteristics = await _findCharacteristics(services);

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

  Future<BleThermalStatusCode> transmit(
    BuildContext context,
    String command, {
    Function(String)? responseCallback,
    Function(BleThermalStatusCode errorMessage)? onErrorCallback,
  }) async {
    if (_characteristics == null) {
      _processError(connector, BleThermalStatusCode.characteristicsAreNotReady,
          keepAlive: false, onErrorCallback: onErrorCallback);
      return BleThermalStatusCode.couldNotTransmit;
    }

    // Initiate connexion to BLE
    try {
      await connect(connector);
    } catch (_) {
      _processError(connector, BleThermalStatusCode.couldNotConnect,
          keepAlive: false, onErrorCallback: onErrorCallback);
      return BleThermalStatusCode.couldNotTransmit;
    }

    // Register to the response
    // Prepare a listener to receive the response
    try {
      BleLogger.log('Subscribing to characteristics');
      Future.delayed(const Duration(milliseconds: 500));
      _ble.subscribeToCharacteristic(_characteristics!['rx']!).listen((value) {
        BleLogger.log('Receiving response');
        if (responseCallback != null) {
          responseCallback(String.fromCharCodes(value));
        }
      });
    } catch (_) {
      _processError(connector, BleThermalStatusCode.couldNotSubscribe,
          keepAlive: false, onErrorCallback: onErrorCallback);
      return BleThermalStatusCode.couldNotSubscribe;
    }

    // Send the data
    try {
      BleLogger.log('Transmitting request');
      await _ble.writeCharacteristicWithResponse(_characteristics!['tx']!,
          value: ascii.encode(command));
    } catch (_) {
      _processError(connector, BleThermalStatusCode.couldNotTransmit,
          keepAlive: false, onErrorCallback: onErrorCallback);
      return BleThermalStatusCode.couldNotTransmit;
    }

    await disconnect(connector);
    return BleThermalStatusCode.success;
  }

  void _processError(
    BleDeviceConnector connector,
    BleThermalStatusCode status, {
    required bool keepAlive,
    required Function(BleThermalStatusCode status)? onErrorCallback,
  }) {
    BleLogger.log('Processing error');
    if (onErrorCallback != null) onErrorCallback(status);
    if (!keepAlive) disconnect(connector);
  }

  Future<DiscoveredDevice?> _findDevice() async {
    BleLogger.log('Finding devices');
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
    Function(BleThermalStatusCode status)? onErrorCallback,
  }) async {
    BleLogger.log('Finding services');
    // Connect to the scanned device
    try {
      await connect(connector);
    } catch (_) {
      _processError(connector, BleThermalStatusCode.couldNotConnect,
          keepAlive: true, onErrorCallback: onErrorCallback);
      return null;
    }

    late final List<DiscoveredService> services;
    try {
      services = await ble.discoverServices(_bleDevice!.id);
    } catch (_) {
      _processError(connector, BleThermalStatusCode.couldNotFetchServices,
          keepAlive: true, onErrorCallback: onErrorCallback);
      return null;
    }

    return services;
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
