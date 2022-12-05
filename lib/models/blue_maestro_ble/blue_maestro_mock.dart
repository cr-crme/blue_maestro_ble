import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'blue_maestro_ble.dart';
import 'reactive_ble_facade/ble_command.dart';
import 'reactive_ble_facade/ble_device_connector.dart';
import 'reactive_ble_facade/ble_scanner.dart';

export 'blue_maestro_ble.dart';

class BlueMaestroMock implements BlueMaestroBle {
  Map<String, QualifiedCharacteristic>? _characteristics;
  final int numberMeasurements;

  final _transmitResponse = BlueMaestroResponse();

  BlueMaestroMock({required this.numberMeasurements});

  @override
  Future<BleStatusCode> initialize({
    maximumRetries = 0,
    retryTime = const Duration(seconds: 5),
  }) async {
    _characteristics = {
      'tx': QualifiedCharacteristic(
          characteristicId: Uuid.parse('0000'),
          serviceId: Uuid.parse('0001'),
          deviceId: deviceId),
      'rx': QualifiedCharacteristic(
          characteristicId: Uuid.parse('0002'),
          serviceId: Uuid.parse('0003'),
          deviceId: deviceId),
    };
    isInitialized = true;
    return BleStatusCode.success;
  }

  @override
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

    // Prepare a listener for the answer callback
    return _waitThenResponse(command, onResponse: onResponse);
  }

  Future<BleStatusCode> _waitThenResponse(BlueMaestroCommand command,
      {required dynamic Function(BlueMaestroResponse) onResponse}) async {
    await Future.delayed(const Duration(seconds: 1));
    if (command.message == '*batt') {
      onResponse(_generateBatterieResponse());
    } else if (command.message == '*info') {
      onResponse(_generateInformationResponse());
    } else if (command.message == '*tell') {
      onResponse(_generateTelemetricsResponse());
    } else if (command.message.contains('*lint')) {
      onResponse(_generateLogIntervalResponse(command.message.substring(5)));
    } else if (command.message.contains('*sint')) {
      onResponse(_generateSensorIntervalResponse(command.message.substring(5)));
    } else if (command.message == '*logall') {
      onResponse(_generateMeasuresResponse(nbMeasures: 100));
    } else if (command.message == '*clr') {
      onResponse(_generateClearLogResponse());
    } else {
      throw 'Command not mocked yet';
    }

    return BleStatusCode.success;
  }

  BlueMaestroResponse _generateBatterieResponse() {
    final response = BlueMaestroResponse();
    response.rawResponse.add(_stringAsBytes('Saadc 647, 78%'));
    return response;
  }

  BlueMaestroResponse _generateInformationResponse() {
    final response = BlueMaestroResponse();
    response.rawResponse.add(_stringAsBytes('SETTINGS'));
    response.rawResponse.add(_stringAsBytes('Name:   F02DA739'));
    response.rawResponse.add(_stringAsBytes('Ver no: 27'));
    response.rawResponse.add(_stringAsBytes('Sub ver no: 15.0.0'));
    response.rawResponse.add(_stringAsBytes('Rel dte: 26 Sep 19'));
    response.rawResponse.add(_stringAsBytes('Txp lvl: 4'));
    response.rawResponse.add(_stringAsBytes('Batt lvl: 84%'));
    response.rawResponse.add(_stringAsBytes('Mem 250 days'));
    return response;
  }

  BlueMaestroResponse _generateTelemetricsResponse() {
    final response = BlueMaestroResponse();
    response.rawResponse.add(_stringAsBytes('TELEMETRICS'));
    response.rawResponse.add(_stringAsBytes('Snsr Frq: 15s'));
    response.rawResponse.add(_stringAsBytes('Log Frq: 3600s'));
    response.rawResponse.add(_stringAsBytes('No. logs: 77'));
    response.rawResponse.add(_stringAsBytes('Max: 6000 rcds'));
    response.rawResponse.add(_stringAsBytes('Cur Tem: 22.2C'));
    response.rawResponse.add(_stringAsBytes('Cur Hum: 29.5%'));
    response.rawResponse.add(_stringAsBytes('Cur Press: 1012.3C'));
    response.rawResponse.add(_stringAsBytes('Hghst Tem: 24.8C'));
    response.rawResponse.add(_stringAsBytes('Hghst Hum: 52.6%'));
    response.rawResponse.add(_stringAsBytes('Hghst Dew: -3000.0C'));
    response.rawResponse.add(_stringAsBytes('Lowst Tem: 0.0C'));
    response.rawResponse.add(_stringAsBytes('Lowst Hum: 0.0%'));
    response.rawResponse.add(_stringAsBytes('Lowst Dew: 0.0C'));
    response.rawResponse.add(_stringAsBytes('24Hgh Tem: 22.2C'));
    response.rawResponse.add(_stringAsBytes('24Hgh Hum: 39.0%'));
    response.rawResponse.add(_stringAsBytes('24Hgh Dew: 1012.3C'));
    return response;
  }

  BlueMaestroResponse _generateLogIntervalResponse(String interval) {
    final response = BlueMaestroResponse();
    response.rawResponse.add(_stringAsBytes('Interval: ${interval}s'));
    return response;
  }

  BlueMaestroResponse _generateSensorIntervalResponse(String interval) {
    final response = BlueMaestroResponse();
    response.rawResponse.add(_stringAsBytes('Interval: ${interval}s'));
    return response;
  }

  BlueMaestroResponse _generateMeasuresResponse({required int nbMeasures}) {
    final response = BlueMaestroResponse();

    // Produce the header
    final m = _intAsBytes(nbMeasures);

    // Construct the header
    response.rawResponse.add(
        [m[0], m[1], m[0], m[1], m[0], m[1]] + [0, 0, 0, 0, 0, 0, 0, 0, 0]);

    // Fill the temperature response starting at 23.0 Celsius, varying pm 0.5
    List<List<int>> measurements = [];
    measurements += _generateMeasurements(
        nbMeasures: nbMeasures, startingValue: 230, variation: 5);

    // Fill the humidity response starting at 33.0%, varying pm 0.5
    measurements += _generateMeasurements(
        nbMeasures: nbMeasures, startingValue: 330, variation: 5);

    // Fill the atmospheric pressure response starting at 101.25kPa, varying pm 0.1
    measurements += _generateMeasurements(
        nbMeasures: nbMeasures, startingValue: 10125, variation: 10);

    for (final row in measurements) {
      response.rawResponse.add(row);
    }
    return response;
  }

  BlueMaestroResponse _generateClearLogResponse() => BlueMaestroResponse();

  @override
  late BleDeviceConnector connector;

  @override
  bool isInitialized = false;

  @override
  late BleScanner scanner;

  @override
  Future<void> connect(BleDeviceConnector connector) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  String get deviceId => '123456';

  @override
  String get deviceName => 'MockedMaestro';

  @override
  Future<void> disconnect(BleDeviceConnector connector) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<DiscoveredDevice?> findDevice(List<int> sigId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return null;
  }

  @override
  Future<List<DiscoveredService>?> findServices() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [];
  }

  @override
  Future<BleStatusCode> listenAdvertisement(
      QualifiedCharacteristic characteristic,
      {required Function(List<int> p1) onResponse,
      Function(String p1)? onError}) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return BleStatusCode.success;
  }

  @override
  Future<BleStatusCode> transmit(
          BleCommand command, QualifiedCharacteristic characteristic,
          {int maximumRetries = 3,
          Duration retryTime = const Duration(seconds: 5)}) =>
      throw 'This method should not be called';

  @override
  Future<BleStatusCode> tryInitialize(
          {maximumRetries = 0,
          retryTime = const Duration(seconds: 5),
          required List<int> sigId}) =>
      throw 'This method should not be called';
}

///
/// Converts an int to a 2 bytes list
///
List<int> _stringAsBytes(String value) {
  return value.codeUnits;
}

///
/// Converts an int to a 2 bytes list
///
List<int> _intAsBytes(int value) {
  final valueTp = ByteData(2)..setInt16(0, value, Endian.big);
  return valueTp.buffer.asUint8List();
}

///
/// Fill the first 20 bytes by simulating measurements with a specified
/// [startingValue] and plus or minus [variation] around that value at each
/// measurement.
/// If get get to the 20th byte, start a new row. If it finishes before
/// filling a row, print the number 0x2C2C, then pad with 0.
///
List<List<int>> _generateMeasurements({
  required int nbMeasures,
  required int startingValue,
  required int variation,
}) {
  final rand = Random();

  List<List<int>> measurements = [];
  var current = startingValue;
  for (var i = 0; i <= nbMeasures ~/ 10; i++) {
    List<int> row = [];
    for (var j = 0; j < 10; j++) {
      // Add or remove up to [variation] units
      current += rand.nextInt(variation);

      row += _intAsBytes(i < nbMeasures ~/ 10 || j < nbMeasures % 10
          ? current
          : j == nbMeasures % 10
              ? 0x2C2C
              : 0);
    }
    measurements.add(row);
  }
  return measurements;
}
