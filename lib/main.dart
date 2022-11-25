import 'package:bluetooth_flutter_test/screens/device_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import 'helpers/ble_facade/ble_device_connector.dart';
import 'helpers/ble_facade/ble_scanner.dart';

const _themeColor = Colors.lightGreen;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final ble = FlutterReactiveBle();
  final scanner = BleScanner(ble);
  final connector = BleDeviceConnector(ble);
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: ble),
        Provider.value(value: scanner),
        Provider.value(value: connector),
        StreamProvider<BleScannerState?>(
          create: (_) => scanner.state,
          initialData: const BleScannerState(
            discoveredDevices: [],
            scanIsInProgress: false,
          ),
        ),
        StreamProvider<ConnectionStateUpdate>(
          create: (_) => connector.state,
          initialData: const ConnectionStateUpdate(
            deviceId: 'Unknown device',
            connectionState: DeviceConnectionState.disconnected,
            failure: null,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Flutter Reactive BLE example',
        color: _themeColor,
        theme: ThemeData(primarySwatch: _themeColor),
        initialRoute: DeviceDetailScreen.route,
        routes: {
          DeviceDetailScreen.route: (context) => const DeviceDetailScreen(),
        },
      ),
    ),
  );
}
