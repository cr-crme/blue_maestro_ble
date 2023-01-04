import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'blue_maestro_command.dart';
import 'blue_maestro_constants.dart';
import 'blue_maestro_response.dart';
import 'reactive_ble_facade/reactive_ble_facade.dart';

export 'blue_maestro_command.dart';
export 'blue_maestro_mock.dart';
export 'blue_maestro_response.dart';
export 'reactive_ble_facade/reactive_ble_facade.dart';

class BlueMaestroBle extends ReactiveBle {
  Map<String, QualifiedCharacteristic>? _characteristics;

  final _transmitResponse = BlueMaestroResponse();

  Future<BleStatusCode> initialize({
    maximumRetries = 0,
    retryTime = const Duration(seconds: 5),
    Function? onDeviceFound,
    Function? onServicesFound,
  }) async {
    final status = await super.tryInitialize(
      maximumRetries: maximumRetries,
      retryTime: retryTime,
      sigId: BlueMaestroConstants.sigId,
    );
    if (status != BleStatusCode.success) return status;
    if (onDeviceFound != null) onDeviceFound();

    final services = await findServices();
    if (services == null) return BleStatusCode.couldNotFindServices;
    if (onServicesFound != null) onServicesFound();

    _characteristics = _setCharacteristics(deviceId, services);
    return BleStatusCode.success;
  }

  Future<BleStatusCode> transmitWithResponse(
    BlueMaestroCommand command, {
    int maximumRetries = 3,
    Duration retryTime = const Duration(seconds: 5),
    required dynamic Function(BlueMaestroResponse) onResponse,
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
        (e) => e.serviceId.toString() == BlueMaestroConstants.mainServiceUuid);
    final txCharacteristic = service.characteristics.firstWhere((e) =>
        e.characteristicId.toString() == BlueMaestroConstants.txServiceUuid);
    final rxCharacteristic = service.characteristics.firstWhere((e) =>
        e.characteristicId.toString() == BlueMaestroConstants.rxServiceUuid);

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
