import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import '/helpers/ble_facade/ble_device_connector.dart';
import '/helpers/ble_facade/ble_device_interactor.dart';
import '/helpers/constants.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceDetailScreen({required this.device, super.key});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<QualifiedCharacteristic?> _txCharacteristic;

  late Function() _connectCallback;
  late Function() _disconnectCallback;

  late String writeOutput;
  late TextEditingController textEditingController;
  late StreamSubscription<List<int>>? subscribeStream;

  @override
  void initState() {
    super.initState();

    _setCallbacks();
    _txCharacteristic = _findTxCharacteristic();

    writeOutput = '';
    textEditingController = TextEditingController();
  }

  @override
  void dispose() {
    subscribeStream?.cancel();
    super.dispose();
  }

  void _setCallbacks() {
    final deviceConnector =
        Provider.of<BleDeviceConnector>(context, listen: false);
    _connectCallback = () => deviceConnector.connect(widget.device.id);
    _disconnectCallback = () => deviceConnector.disconnect(widget.device.id);
  }

  Future<QualifiedCharacteristic?> _findTxCharacteristic() async {
    final interactor = Provider.of<BleDeviceInteractor>(context, listen: false);

    await _connectCallback();
    final services = await interactor.discoverServices(widget.device.id);
    await _disconnectCallback();

    // Find the main service
    late final DiscoveredCharacteristic characteristic;
    try {
      final service = services.firstWhere(
          (e) => e.serviceId.toString() == ThermalDevice.mainServiceUuid);
      characteristic = service.characteristics.firstWhere(
          (e) => e.characteristicId.toString() == ThermalDevice.txServiceUuid);
    } on StateError {
      return null;
    }

    return QualifiedCharacteristic(
        characteristicId: characteristic.characteristicId,
        serviceId: characteristic.serviceId,
        deviceId: widget.device.id);
  }

  List<int> _parseInput() =>
      textEditingController.text.split(',').map(int.parse).toList();

  Future<void> _sendCharacteristic(QualifiedCharacteristic txCharacteristic,
      {required bool response}) async {
    final interactor = Provider.of<BleDeviceInteractor>(context, listen: false);

    await _connectCallback();
    if (response) {
      await interactor.writeCharacterisiticWithResponse(
          txCharacteristic, _parseInput());
    } else {
      await interactor.writeCharacterisiticWithoutResponse(
          txCharacteristic, _parseInput());
    }
    await _disconnectCallback();

    setState(() {
      writeOutput = response ? 'Ok' : 'Done';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QualifiedCharacteristic?>(
        future: _txCharacteristic,
        builder: (context, txCharacteristic) {
          if (txCharacteristic.hasData) {
            final charac = txCharacteristic.data!;
            return WillPopScope(
              onWillPop: () async {
                _disconnectCallback();
                return true;
              },
              child: Scaffold(
                appBar: AppBar(title: Text(widget.device.name)),
                body: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Write characteristic',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextField(
                        controller: textEditingController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Value',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          _sendCharacteristic(charac, response: true),
                      child: const Text('With response'),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          _sendCharacteristic(charac, response: false),
                      child: const Text('Without response'),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 8.0),
                      child: Text('Output: $writeOutput'),
                    ),
                  ],
                ),
              ),
            );
          } else {
            return Scaffold(
                appBar: AppBar(title: Text(widget.device.name)),
                body: const Center(child: CircularProgressIndicator()));
          }
        });
  }
}
