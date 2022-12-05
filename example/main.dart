import 'package:flutter/material.dart';

import 'screens/device_detail_screen.dart';

const _themeColor = Colors.lightGreen;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
    title: 'Thermal BLE example',
    color: _themeColor,
    theme: ThemeData(primarySwatch: _themeColor),
    initialRoute: DeviceDetailScreen.route,
    routes: {
      DeviceDetailScreen.route: (context) => const DeviceDetailScreen(
            useMock: false,
          ),
    },
  ));
}
