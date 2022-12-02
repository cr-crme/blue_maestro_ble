class BlueMaestroConstants {
  static const String bleHead = '0000';
  static const String bleTail = '0000-1000-8000-00805f9b34fb';
  static const String uartHead = '6e40';
  static const String uartTail = 'b5a3-f393-e0a9-e50e24dcca9e';

  static const String mainServiceUuid = '${uartHead}0001-$uartTail';
  static const String txServiceUuid = '${uartHead}0002-$uartTail';
  static const String rxServiceUuid = '${uartHead}0003-$uartTail';

  static const String service1 = '${bleHead}1800-$bleTail';
  static const String service2 = '${bleHead}1801-$bleTail';
  static const String descriptor1 = '${bleHead}2aa6-$bleTail';
  static const String descriptor2 = '${bleHead}2aa6-$bleTail';

  static const String deviceMac = 'F0:2D:A7:39:B8:7D';
}
