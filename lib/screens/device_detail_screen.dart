import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';

import '/helpers/ble_facade/ble_device_connector.dart';
import '/helpers/constants.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceDetailScreen({required this.device, super.key});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<Map<String, QualifiedCharacteristic>?> _characteristics;
  String subscribeOutput = '';
  late StreamSubscription<List<int>>? _subscribeStream;

  BleDeviceConnector get _connector =>
      Provider.of<BleDeviceConnector>(context, listen: false);

  bool _isProcessingRequest = false;
  Function() get _connectCallback => () => _connector.connect(widget.device.id);
  Function() get _disconnectCallback =>
      () => _connector.disconnect(widget.device.id);

  late String writeOutput;
  late TextEditingController textEditingController;

  @override
  void initState() {
    super.initState();

    _characteristics = _initializeCharacteristics();

    writeOutput = '';
    textEditingController = TextEditingController();
  }

  @override
  void dispose() {
    _subscribeStream?.cancel();
    super.dispose();
  }

  Future<Map<String, QualifiedCharacteristic>?>
      _initializeCharacteristics() async {
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);

    late final List<DiscoveredService> services;
    try {
      await _connectCallback();
      services = await ble.discoverServices(widget.device.id);
    } on Exception catch (e) {
      _showSnackbarError('Error while getting the services :\n$e');
      setState(() {
        writeOutput = 'Failed to get the services, retrying in 5 seconds';
        subscribeOutput = '';
        return;
      });
      await Future.delayed(const Duration(seconds: 5));
      return await _initializeCharacteristics();
    } finally {
      await _disconnectCallback();
    }

    // Find the main service
    late final DiscoveredCharacteristic txCharacteristic;
    late final DiscoveredCharacteristic rxCharacteristic;
    try {
      final service = services.firstWhere(
          (e) => e.serviceId.toString() == ThermalDevice.mainServiceUuid);

      txCharacteristic = service.characteristics.firstWhere(
          (e) => e.characteristicId.toString() == ThermalDevice.txServiceUuid);
      rxCharacteristic = service.characteristics.firstWhere(
          (e) => e.characteristicId.toString() == ThermalDevice.rxServiceUuid);
    } on StateError catch (e) {
      _showSnackbarError(e.message);
      return null;
    }

    return {
      'tx': QualifiedCharacteristic(
          characteristicId: txCharacteristic.characteristicId,
          serviceId: txCharacteristic.serviceId,
          deviceId: widget.device.id),
      'rx': QualifiedCharacteristic(
          characteristicId: rxCharacteristic.characteristicId,
          serviceId: rxCharacteristic.serviceId,
          deviceId: widget.device.id),
    };
  }

  void _showSnackbarError(String text) {
    final snackBar = SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _transmit(
      Map<String, QualifiedCharacteristic> characteristics) async {
    final ble = Provider.of<FlutterReactiveBle>(context, listen: false);

    setState(() => _isProcessingRequest = true);

    // Initiate connexion to BLE
    try {
      await _connectCallback();
    } on Exception catch (e) {
      _showSnackbarError('Error while reading :\n$e');
      await _disconnectCallback();
      setState(() {
        writeOutput = 'Failed to connect';
        subscribeOutput = '';
        return;
      });
    }

    // Prepare a listener
    try {
      _subscribeStream =
          ble.subscribeToCharacteristic(characteristics['rx']!).listen((event) {
        // This automatically disconnect
        setState(() {
          subscribeOutput = String.fromCharCodes(event);
        });
      });
    } on Exception catch (e) {
      _showSnackbarError('Error while reading :\n$e');
      try {
        await _disconnectCallback();
      } on Exception {
        //
      }

      setState(() {
        writeOutput = 'Failed Subscribing';
        subscribeOutput = '';
        return;
      });
    }

    // Prevents from rapid fire the BLE
    await Future.delayed(const Duration(seconds: 2));

    // Send some data
    try {
      await ble.writeCharacteristicWithResponse(characteristics['tx']!,
          value: ascii.encode(textEditingController.text));
    } on Exception catch (e) {
      _showSnackbarError('Error while reading :\n$e');
      try {
        await _disconnectCallback();
      } on Exception {
        //
      }
      setState(() {
        writeOutput = 'Failed transmitting';
        subscribeOutput = '';
        return;
      });
    }

    setState(() {
      _isProcessingRequest = false;
      writeOutput = 'Transmitted';
      subscribeOutput = 'Waiting';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, QualifiedCharacteristic>?>(
        future: _characteristics,
        builder: (context, characteristics) {
          if (characteristics.hasData) {
            final charac = characteristics.data!;
            return WillPopScope(
              onWillPop: () async {
                _disconnectCallback();
                return true;
              },
              child: Scaffold(
                appBar: AppBar(title: Text(widget.device.name)),
                body: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _isProcessingRequest
                      ? [
                          const Center(child: CircularProgressIndicator()),
                          const Text('Processing request'),
                        ]
                      : [
                          const Text('Write characteristic',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextField(
                              controller: textEditingController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Command',
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _transmit(charac),
                            child: const Text('With response'),
                          ),
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(bottom: 28.0),
                            child: Text('Output: $writeOutput'),
                          ),
                          Text('Response: $subscribeOutput'),
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
