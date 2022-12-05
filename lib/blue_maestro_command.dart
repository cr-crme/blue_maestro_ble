import './reactive_ble_facade/ble_command.dart';

class BlueMaestroCommand extends BleCommand {
  const BlueMaestroCommand(command, [parameter = ''])
      : super('$command$parameter');

  factory BlueMaestroCommand.batteryLevel() {
    return const BlueMaestroCommand('*batt');
  }

  factory BlueMaestroCommand.information() {
    return const BlueMaestroCommand('*info');
  }

  factory BlueMaestroCommand.telemetrics() {
    return const BlueMaestroCommand('*tell');
  }

  factory BlueMaestroCommand.logAll() {
    return const BlueMaestroCommand('*logall');
  }

  factory BlueMaestroCommand.loggingInterval(int interval) {
    return BlueMaestroCommand('*lint', interval);
  }

  factory BlueMaestroCommand.sensorInterval(int interval) {
    return BlueMaestroCommand('*sint', interval);
  }

  factory BlueMaestroCommand.clearLog() {
    return const BlueMaestroCommand('*clr');
  }
}
