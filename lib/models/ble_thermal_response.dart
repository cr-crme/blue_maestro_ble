import 'package:flutter/foundation.dart';

class NotEnoughDataException implements Exception {
  const NotEnoughDataException();
  final String message = 'Not enough Packages. Maybe there are still to come. '
      'You can wait a little to see if more packages come or retry later';
}

class TooManyDataException implements Exception {
  const TooManyDataException();
  final String message =
      'Too much packages! Maybe there are too much subscriptions. '
      'Wait a bit and retry';
}

class NotCompatibleDataException implements Exception {
  const NotCompatibleDataException();
  final String message =
      'Data are not compatible with BleThermalSensorMeasurements';
}

List<int> _intListToInt16(List<int> entries) {
  Uint8List byteList = Uint8List.fromList(entries);

  // Convert each successive pairs to int16 as Big Endian
  final List<int> out = [];
  for (int i = 0; i < entries.length; i += 2) {
    ByteData byteData = ByteData.sublistView(byteList, i, i + 2);
    out.add(byteData.getInt16(0, Endian.big));
  }
  return out;
}

List<int> _concatenate(List<List<int>> toContatenate) {
  return toContatenate.expand((e) => e).toList();
}

class BleThermalSensorMeasurements {
  late final List<double> temperature;
  late final List<double> humidity;
  late final List<double> atmosphericPressure;

  String get temperatureUnits => 'C';
  String get humidityUnits => '%';
  String get atmosphericPressureUnits => 'kPa';

  double get temperatureFromInt => 0.1;
  double get humidityFromInt => 0.1;
  double get atmosphericPressureFromInt => 0.01;
  List<double> get _conversionFactors =>
      [temperatureFromInt, humidityFromInt, atmosphericPressureFromInt];

  late final int temperatureNumberMeasurements;
  late final int humidityNumberMeasurements;
  late final int atmosphericPressureNumberMeasurements;

  BleThermalSensorMeasurements(List<List<int>> entries) {
    ///
    /// The '*logall' command, contrary to all other responses, is not in ASCII.
    /// It is made from a header of 15 bytes. The first 2 are for
    /// the number of temperature measures, the next 2 are for the number
    /// humidity measures, the next 2 are for the number of atmospheric
    /// pressure measures. I could not figure out the remaining 9 bytes. Yet
    /// they seem to be constant (0,2,1,0,0,0,0,0,58).
    /// The next responses are the sensor measurements made from 20 bytes,
    /// corresponding to 10 big endian int16 measurements. After the last
    /// measurement two bytes are sent (0x2C 0x2C) and the remmaining bytes
    /// are 0 padded. Then the next sensor is sent.
    /// The order of the sensors is
    /// temperature, humidity and atmospheric pressure.

    // Chech if we have received the header
    // Parse the header (15 bytes)
    if (entries.isEmpty || entries[0].length != 15) {
      throw const NotCompatibleDataException();
    }
    final header = entries[0];

    // Number of measurements per sensor
    final List<int> numberMeasurements =
        _intListToInt16(header.getRange(0, 6).toList());
    temperatureNumberMeasurements = numberMeasurements[0];
    humidityNumberMeasurements = numberMeasurements[1];
    atmosphericPressureNumberMeasurements = numberMeasurements[2];

    // For each sensor
    var runningCountFirst = 1; // First sensor is on the 2nd row
    final List<int> firstRow = []; // row measurements start per sensor
    for (var numberMeasurement in numberMeasurements) {
      firstRow.add(runningCountFirst);
      // There are 10 measurements per row
      runningCountFirst += (numberMeasurement / 10).ceil();
    }
    firstRow.add(runningCountFirst);
    final lastExpectedRow = runningCountFirst;

    // Sanity check on number of data actually received which should match the
    // predicted number of data
    if (entries.length < lastExpectedRow) {
      throw const NotEnoughDataException();
    } else if (entries.length > lastExpectedRow) {
      throw const TooManyDataException();
    }
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].length != 20) throw const NotCompatibleDataException();
    }

    // Parse the results into measurements
    final List<List<double>> measurements = [];
    for (var i = 0; i < 3; i++) {
      final rows =
          _concatenate(entries.getRange(firstRow[i], firstRow[i + 1]).toList());
      final data =
          _intListToInt16(rows.getRange(0, numberMeasurements[i] * 2).toList());
      measurements.add(data.map((e) => e * _conversionFactors[i]).toList());
    }
    temperature = measurements[0];
    humidity = measurements[1];
    atmosphericPressure = measurements[2];
  }
}

class BleThermalResponse {
  final List<List<int>> rawResponse = [];

  List<String> toAscii() {
    return rawResponse.map((e) => String.fromCharCodes(e)).toList();
  }

  BleThermalSensorMeasurements? asMeasurements() {
    try {
      return BleThermalSensorMeasurements(rawResponse);
    } on NotEnoughDataException {
      return null;
    }
  }

  void add(List<int> value) => rawResponse.add(value);
  void clear() => rawResponse.clear();
  bool get isEmpty => rawResponse.isEmpty;
  bool get isNotEmpty => rawResponse.isNotEmpty;
}
