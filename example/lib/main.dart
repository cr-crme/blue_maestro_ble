import 'package:flutter/material.dart';

import 'screens/device_detail_screen.dart';

const _themeColor = Colors.lightGreen;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Using the mock here will load the non-connected version of the library.
  // This of course should not be used in production, but is ideal to having
  // a good idea what the responses are expected to be when connected to a real
  // device
  const useMock = true;

  runApp(MaterialApp(
    title: 'Blue Maestro BLE example',
    color: _themeColor,
    theme: ThemeData(primarySwatch: _themeColor),
    initialRoute: DeviceDetailScreen.route,
    routes: {
      DeviceDetailScreen.route: (context) =>
          const DeviceDetailScreen(useMock: useMock),
    },
  ));
}
