# Blue Maestro Flutter
This is an flutter specialization of the `flutter_reactive_ble` package. 
It is still incomplete in the sense that it does not implement all the command nor that it robusts. 
It should therefore be treated as a quick and dirty implementation that gets the job done. 

A mocker is also provided that will responses as if it was a real device. 
The log are randomized, the rest is simply hard-coded. 
Please note that changing the sensor or log interval won't be reflected in the information.

Please also note that all the permission must be set according to the `flutter_reactive_ble` package. 
The permission won't be automatically asked, but the `status` from `initialize` should be informative enough on what is the problem.

# Example 
An example is provided with the package that implements both the real and the mocked version.

# Instruction
To use the device, one must first `create` and `initialize` an instance:
```dart
final device = BlueMaestroBle()
final status = await device.initialize();
if (status == BleStatusCode.success) debugPrint('Bravo! You are connected!');
```

Then, to communicate, they must call the `transmit` method:
```dart
final command = BlueMaestroCommand.telemetrics();
final status = await device.transmitWithResponse(command, onResponse: onResponse);
if (status == BleStatusCode.success) debugPrint('Bravo! You transmitted a command!');
```
with `onResponse` being either an Ascii response (all commands except for `logAll`) or a BlueMaestroMeasurements (only `logAll` command)
```dart
void handleAsciiResponse(BlueMaestroResponse response) {
    if (response.isEmpty) return;
    debugPrint('${response.toAscii().join('\n')}');
}
```
```dart
void handleLogAllReponse(BlueMaestroResponse response){
    final measurements = response.asMeasurements();
    if (measurements == null) return;

    debugPrint(
        'Number of measurements = ${measurements.temperatureNumberMeasurements}\n\n'
        'Temperature (${measurements.temperatureUnits}) =\n${measurements.temperature.map((e) => e.toStringAsFixed(1)).toList()}\n\n'
        'Humidity (${measurements.humidityUnits}) =\n${measurements.humidity.map((e) => e.toStringAsFixed(1)).toList()}\n\n'
        'Atmospheric pressure (${measurements.atmosphericPressureUnits}) =\n${measurements.atmosphericPressure.map((e) => e.toStringAsFixed(2)).toList()}'
    );
}
```
Please note that the `onResponse` is called multiple times (for each subresponses of the device). 
There is unfortunately no easy way to know how many times it is going to be called. 
