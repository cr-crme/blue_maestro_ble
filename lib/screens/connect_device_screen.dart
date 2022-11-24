import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import '/helpers/ble_facade/ble_scanner.dart';
import '/helpers/ble_facade/ble_status_helper.dart';
import '/helpers/constants.dart';
import 'device_detail_screen.dart';

class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({Key? key}) : super(key: key);

  static const String route = '/connect-to-device-screen';

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  bool _hasScanned = false;
  bool _sensorFound = false;

  void _startScanning() {
    Provider.of<BleScanner>(context, listen: false)
        // TODO find using the serviceUuid (since it is more general)
        // .startScan([Uuid.parse(ConnectDeviceScreen.serviceUuid)]);
        .startScan([]);
    _hasScanned = true;
  }

  void _stopScanning() {
    Provider.of<BleScanner>(context, listen: false).stopScan();
  }

  void _checkAndConnect(BleScannerState? bleScannerState) {
    if (bleScannerState == null || bleScannerState.discoveredDevices.isEmpty) {
      return;
    }

    final index = bleScannerState.discoveredDevices
        .indexWhere((e) => e.id == ThermalDevice.deviceId);
    if (index < 0) return;

    _stopScanning();
    _sensorFound = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => DeviceDetailScreen(
                  device: bleScannerState.discoveredDevices[index])));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Scan for temperature device'),
      ),
      body: Consumer2<BleStatus?, BleScannerState?>(
        builder: (_, bleStatus, bleScannerState, __) {
          if (bleStatus != BleStatus.ready) {
            Center(
              child: Text(bleStatusToText(bleStatus ?? BleStatus.unknown)),
            );
          }

          if (!_hasScanned) {
            _startScanning();
          }

          if (_sensorFound) {
            return Container();
          }

          _checkAndConnect(bleScannerState);
          return const Center(
            child: Text(
              'Scanning for the temperature device\n'
              'Looking for service:\n'
              '${ThermalDevice.mainServiceUuid}',
              textAlign: TextAlign.center,
            ),
          );
        },
      ));
}
