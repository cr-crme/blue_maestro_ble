import 'blue_maestro_measurements.dart';

class BlueMaestroResponse {
  final List<List<int>> rawResponse = [];

  List<String> toAscii() {
    return rawResponse.map((e) => String.fromCharCodes(e)).toList();
  }

  BlueMaestroMeasurements? asMeasurements() {
    try {
      return BlueMaestroMeasurements(rawResponse);
    } on NotEnoughDataException {
      return null;
    }
  }

  void add(List<int> value) => rawResponse.add(value);
  void clear() => rawResponse.clear();
  bool get isEmpty => rawResponse.isEmpty;
  bool get isNotEmpty => rawResponse.isNotEmpty;
}
