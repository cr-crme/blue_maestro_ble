import 'dart:async';

import 'package:bluetooth_flutter_test/helpers/ble_facade/ble_logger.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '/helpers/ble_facade/ble.dart';
import '/helpers/ble_facade/ble_status_code.dart';
import '/helpers/constants.dart';
import '/models/ble_thermal_response.dart';

class BleThermal extends Ble {
  Map<String, QualifiedCharacteristic>? _characteristics;

  BleThermal({this.mock = false});

  bool mock;
  final _transmitResponse = BleThermalResponse();

  Future<BleStatusCode> initialize({
    maximumRetries = 0,
    retryTime = const Duration(seconds: 5),
  }) async {
    final status = await super.tryInitialize(
      maximumRetries: maximumRetries,
      retryTime: retryTime,
      deviceMacToFind: ThermalDevice.deviceMac,
    );
    if (status != BleStatusCode.success) return status;

    final services = await findServices();
    if (services == null) return BleStatusCode.couldNotFindServices;

    _characteristics = _setCharacteristics(deviceId, services);
    return BleStatusCode.success;
  }

  Future<BleStatusCode> transmitWithResponse(
    String command, {
    int maximumRetries = 3,
    Duration retryTime = const Duration(seconds: 5),
    required dynamic Function(BleThermalResponse) onResponse,
  }) async {
    // Sanity check
    if (_characteristics == null) return BleStatusCode.couldNotTransmit;

    // Prepare the response
    _transmitResponse.clear();

    // The connexion last for 10 secondes, we must reconnect at each transmit
    try {
      await connect(connector);
    } on Exception {
      return BleStatusCode.couldNotConnect;
    }

    // Prepare a listener to receive the response
    var result = await listenAdvertisement(_characteristics!['rx']!,
        onResponse: (values) {
      _transmitResponse.add(values);
      onResponse(_transmitResponse);
    });
    if (result != BleStatusCode.success) return result;

    // Transmit the actual command
    return super.transmit(command, _characteristics!['tx']!);
  }

  Map<String, QualifiedCharacteristic>? _setCharacteristics(
      String deviceId, List<DiscoveredService> services) {
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
          deviceId: deviceId),
      'rx': QualifiedCharacteristic(
          characteristicId: rxCharacteristic.characteristicId,
          serviceId: rxCharacteristic.serviceId,
          deviceId: deviceId),
    };
  }
}
