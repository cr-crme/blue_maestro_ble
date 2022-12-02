enum BleStatusCode {
  success,
  couldNotInitializeDevice,
  bluetoothOff,
  locationPermissionNotGranted,
  couldNotScan,
  couldNotFindDevice,
  couldNotFindServices,
  couldNotConnect,
  couldNotTransmit,
  couldNotSubscribe,
  responseError,
  characteristicsAreNotReady,
  unknownError,
}

String errorCodeToString(BleStatusCode errorCode) {
  if (errorCode == BleStatusCode.couldNotInitializeDevice) {
    return 'Could not initialize the device';
  } else if (errorCode == BleStatusCode.bluetoothOff) {
    return 'The bluetooth is off. Please turn it on';
  } else if (errorCode == BleStatusCode.locationPermissionNotGranted) {
    return 'The location permission must be granted to the application to '
        'use bluetooth device';
  } else if (errorCode == BleStatusCode.couldNotScan) {
    return 'Could not scan for bluetooth devices.\n'
        'Please make sure bluetooth is activated and Location '
        'permission are granted to the app';
  } else if (errorCode == BleStatusCode.couldNotFindDevice) {
    return 'Could not find the device';
  } else if (errorCode == BleStatusCode.couldNotFindServices) {
    return 'Could not find services';
  } else if (errorCode == BleStatusCode.couldNotSubscribe) {
    return 'Could not subscribe to services';
  } else {
    return 'Unknown error';
  }
}
