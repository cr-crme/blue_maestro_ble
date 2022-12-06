import 'dart:async';

import 'package:blue_maestro_ble/blue_maestro_ble.dart';
import 'package:flutter/material.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, this.useMock = false});

  final bool useMock;
  static const route = '/device-detail-screen';

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  String? _writeOutput;
  late final _blueMaestro = widget.useMock
      ? BlueMaestroMock(numberMeasurements: 10)
      : BlueMaestroBle();
  late Future<bool> _isBlueMaestroReady;
  bool _isTransmitting = false;

  @override
  void initState() {
    super.initState();

    _isBlueMaestroReady = _connectBlueMaestro();
  }

  Future<bool> _connectBlueMaestro() async {
    final status = await _blueMaestro.initialize();

    if (status != BleStatusCode.success) {
      _showErrorMessage(status, extraMessage: 'retrying in 10 seconds');
      await Future.delayed(const Duration(seconds: 10));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isBlueMaestroReady = _connectBlueMaestro();
      });
    }

    setState(() {
      _isTransmitting = false;
      _writeOutput = status == BleStatusCode.success ? 'Connected' : 'Failed';
    });
    return status == BleStatusCode.success;
  }

  void _handleAsciiResponse(BlueMaestroResponse response) {
    setState(() {
      _writeOutput = response.isEmpty
          ? 'Received empty data'
          : 'Response:\n\n${response.toAscii().join('\n')}';
      return;
    });
  }

  void _handleLogAllResponse(BlueMaestroResponse response) {
    final measurements = response.asMeasurements();
    if (measurements == null) return;

    setState(() {
      _writeOutput =
          'Number of measurements = ${measurements.temperatureNumberMeasurements}\n\n'
          'Temperature (${measurements.temperatureUnits}) =\n${measurements.temperature.map((e) => e.toStringAsFixed(1)).toList()}\n\n'
          'Humidity (${measurements.humidityUnits}) =\n${measurements.humidity.map((e) => e.toStringAsFixed(1)).toList()}\n\n'
          'Atmospheric pressure (${measurements.atmosphericPressureUnits}) =\n${measurements.atmosphericPressure.map((e) => e.toStringAsFixed(2)).toList()}';
    });
  }

  void _showErrorMessage(BleStatusCode errorCode, {String? extraMessage}) {
    String errorMessage = errorCodeToString(errorCode);
    if (extraMessage != null) errorMessage += ', $extraMessage';

    // Show message to user
    final snackBar = SnackBar(
      content: Text(errorMessage),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _transmit(BlueMaestroCommand command,
      {required Function(BlueMaestroResponse) onResponse}) async {
    setState(() {
      _writeOutput = null;
      _isTransmitting = true;
    });

    final status = await _blueMaestro.transmitWithResponse(command,
        onResponse: onResponse);
    if (status != BleStatusCode.success) {
      _showErrorMessage(status);
    }

    setState(() => _isTransmitting = false);
  }

  Future<void> _transmitWithIntParameter(
      BlueMaestroCommand Function(int) commandFactory, String title,
      {required Function(BlueMaestroResponse) onResponse}) async {
    var controller = TextEditingController();
    var alert = AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(
                  controller.text == '' ? null : int.parse(controller.text));
            },
            child: const Text('ok'),
          ),
        ],
      ),
    );

    final parameter = await showDialog<int?>(
      context: context,
      builder: (context) {
        return alert;
      },
    );
    if (parameter == null) return;

    _transmit(commandFactory(parameter), onResponse: onResponse);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _isBlueMaestroReady,
        builder: (context, isBlueMaestroReady) {
          if (isBlueMaestroReady.hasData && isBlueMaestroReady.data!) {
            return _buildButtons();
          } else {
            return Scaffold(
                appBar: AppBar(title: const Text('Searching for device')),
                body: const Center(child: CircularProgressIndicator()));
          }
        });
  }

  Scaffold _buildButtons() {
    return Scaffold(
      appBar: AppBar(title: Text(_blueMaestro.deviceName)),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _transmit(BlueMaestroCommand.batteryLevel(),
                    onResponse: _handleAsciiResponse),
                child: const Text('Battery level'),
              ),
              ElevatedButton(
                onPressed: () => _transmit(BlueMaestroCommand.information(),
                    onResponse: _handleAsciiResponse),
                child: const Text('Information'),
              ),
              ElevatedButton(
                onPressed: () => _transmit(BlueMaestroCommand.telemetrics(),
                    onResponse: _handleAsciiResponse),
                child: const Text('Telemetrics'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _transmit(BlueMaestroCommand.logAll(),
                    onResponse: _handleLogAllResponse),
                child: const Text('Get sensor logs'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _transmitWithIntParameter(
                    BlueMaestroCommand.loggingInterval, 'Time in seconds',
                    onResponse: _handleAsciiResponse),
                child: const Text('Set log intervals'),
              ),
              ElevatedButton(
                onPressed: () => _transmitWithIntParameter(
                    BlueMaestroCommand.sensorInterval, 'Time in seconds',
                    onResponse: _handleAsciiResponse),
                child: const Text('Set sensor intervals'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _transmit(BlueMaestroCommand.clearLog(),
                    onResponse: _handleAsciiResponse),
                child: const Text('Clear log'),
              ),
              const SizedBox(height: 20),
              Text(
                  textAlign: TextAlign.center,
                  _isTransmitting
                      ? 'Processing request'
                      : _writeOutput ?? 'Empty response'),
              if (_isTransmitting)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                )),
            ],
          ),
        ),
      ),
    );
  }
}
