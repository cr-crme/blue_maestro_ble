import 'dart:convert';

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_device_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/constants.dart';

class BleThermal {
  BleThermal();

  bool _isScanning = false;
  Map<String, QualifiedCharacteristic>? _characteristics;
  DiscoveredDevice? _bleDevice;

  Future<bool> tryInitialize(
    BuildContext context, {
    Function(String errorMessage)? onErrorCallback,
  }) async {
    // If we already have all the necessary information
    if (_characteristics != null) return true;

    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);
    final connector = Provider.of<BleDeviceConnector>(context, listen: false);
    final scanner = Provider.of<BleScanner>(context, listen: false);
    final status = Provider.of<BleStatus?>(context, listen: false);
    final state = Provider.of<BleScannerState?>(context, listen: false);

    // Start the scanning if necessary
    if (!_isScanning) scanner.startScan([]);
    _isScanning = true;
    // TODO find using the serviceUuid (since it is more general)
    // scanner.connectToAdvertisingDevice(
    //         id: "",
    //         withServices: [Uuid.parse(ThermalDevice.mainServiceUuid)],
    //         prescanDuration: const Duration(seconds: 10));

    _bleDevice = await _findDevice(status, state);
    if (_bleDevice == null) return false;

    scanner.stopScan();
    _isScanning = false;

    final services =
        await _findServices(ble, connector, onErrorCallback: onErrorCallback);
    if (services == null) return false;

    _characteristics = await _findCharacteristics(services);

    return true;
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
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);
    final connector = Provider.of<BleDeviceConnector>(context, listen: false);

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
      ble.subscribeToCharacteristic(_characteristics!['rx']!).listen((event) {
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
      await ble.writeCharacteristicWithResponse(_characteristics!['tx']!,
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

  Future<DiscoveredDevice?> _findDevice(
      BleStatus? status, BleScannerState? state) async {
    if (state == null || state.discoveredDevices.isEmpty) return null;

    final index = state.discoveredDevices
        .indexWhere((e) => e.id == ThermalDevice.deviceId);
    if (index < 0) return null;

    return state.discoveredDevices[index];
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
