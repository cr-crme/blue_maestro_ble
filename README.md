# Blue Maestro BLE Flutter
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

## Build and access rights
First make sure you grant every rights. 

### Android
In "android/app/src/main/AndroidManifest.xml", add the following permissions before the "<application ..." tag

```xml
<!-- required for API 18 - 30 -->
<uses-permission
        android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" />
<uses-permission
        android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" />

<!-- required for API 23 - 30 -->
<uses-permission-sdk-23
        android:name="android.permission.ACCESS_COARSE_LOCATION"
        android:maxSdkVersion="30" />
<uses-permission-sdk-23
        android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" />

<!-- API 31+ -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission
        android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />

```

Please note that you will also have to grant the "Location" permission from the phone itself.

### IOS
Todo

## How to use

### Connecting to the device
To use the device, one must first `create` and `initialize` an instance:
```dart
import 'package:blue_maestro_ble/blue_maestro_ble.dart';
...
final device = BlueMaestroBle()  // Alternatively one can instantiate BlueMaestroMock(numberMeasurements: 50)
final status = await device.initialize();
if (status == BleStatusCode.success) debugPrint('Bravo! You are connected!');
```

### Communicate with the device
Then, to communicate, they must call the `transmit` method:
```dart
final command = BlueMaestroCommand.telemetrics();
final status = await device.transmitWithResponse(command, onResponse: onResponse);
if (status == BleStatusCode.success) debugPrint('Bravo! You transmitted a command!');
```
with `onResponse` explained down below

### Handling the response
The expected `BlueMaestroResponse` called back by `onResponse` can either be an Ascii response (all commands except for `logAll`) or a BlueMaestroMeasurements (only for the `logAll` command)

Please note that the `onResponse` is called multiple times (for each subresponses of the device). 
There is unfortunately no easy way to know how many times it is going to be called. 

#### ASCII responses
```dart
void handleAsciiResponse(BlueMaestroResponse response) {
    if (response.isEmpty) return;
    debugPrint('${response.toAscii().join('\n')}');
}
```

#### Measurements log responses
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
