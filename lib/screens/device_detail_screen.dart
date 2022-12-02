import 'dart:async';

import 'package:bluetooth_flutter_test/models/ble_thermal_response.dart';
import 'package:flutter/material.dart';

import '/models/ble_thermal.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key});

  static const route = '/device-detail-screen';

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  String? _writeOutput;
  final _bleThermal = BleThermal();
  late Future<bool> _isBleReady;
  bool _isTransmitting = false;

  @override
  void initState() {
    super.initState();

    _isBleReady = _connectBleThermal();
  }

  Future<bool> _connectBleThermal() async {
    final status = await _bleThermal.tryInitialize();

    if (status != BleThermalStatusCode.success) {
      _showErrorMessage(status, extraMessage: 'retrying in 10 seconds');
      await Future.delayed(const Duration(seconds: 10));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isBleReady = _connectBleThermal();
      });
    }

    setState(() {
      _isTransmitting = false;
      _writeOutput =
          status == BleThermalStatusCode.success ? 'Connected' : 'Failed';
    });
    return status == BleThermalStatusCode.success;
  }

  void _handleAsciiResponse(BleThermalResponse response) {
    setState(() {
      _writeOutput = response.isEmpty
          ? 'Received empty data'
          : 'Response:\n${response.toAscii().join('\n')}';
      return;
    });
  }

  void _handleLogAllResponse(BleThermalResponse response) {
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

  void _showErrorMessage(BleThermalStatusCode errorCode,
      {String? extraMessage}) {
    String errorMessage = errorCodeToString(errorCode);
    if (extraMessage != null) errorMessage += ', $extraMessage';

    // Show message to user
    final snackBar = SnackBar(
      content: Text(errorMessage),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _transmit(String command,
      {required Function(BleThermalResponse) onResponse}) async {
    setState(() {
      _writeOutput = null;
      _isTransmitting = true;
    });

    final status = await _bleThermal.transmit(command, onResponse: onResponse);
    if (status != BleThermalStatusCode.success) {
      _showErrorMessage(status);
    }

    setState(() => _isTransmitting = false);
  }

  Future<void> _transmitWithNumbers(String command, String title,
      {required Function(BleThermalResponse) onResponse}) async {
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

    final answer = await showDialog<int?>(
      context: context,
      builder: (context) {
        return alert;
      },
    );
    if (answer == null) return;

    final newCommand = '$command$answer';
    _transmit(newCommand, onResponse: onResponse);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _isBleReady,
        builder: (context, isBleReady) {
          if (isBleReady.hasData && isBleReady.data!) {
            return _buildMainScaffold();
          } else {
            return Scaffold(
                appBar: AppBar(title: const Text('Searching for device')),
                body: const Center(child: CircularProgressIndicator()));
          }
        });
  }

  Scaffold _buildMainScaffold() {
    return Scaffold(
      appBar: AppBar(title: Text(_bleThermal.name)),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*batt', onResponse: _handleAsciiResponse),
                child: const Text('Battery level'),
              ),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*info', onResponse: _handleAsciiResponse),
                child: const Text('Information'),
              ),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*tell', onResponse: _handleAsciiResponse),
                child: const Text('Telemetrics'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*logall', onResponse: _handleLogAllResponse),
                child: const Text('Get sensor logs'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _transmitWithNumbers(
                    '*lint', 'Time in seconds',
                    onResponse: _handleAsciiResponse),
                child: const Text('Set log intervals'),
              ),
              ElevatedButton(
                onPressed: () => _transmitWithNumbers(
                    '*sint', 'Time in seconds',
                    onResponse: _handleAsciiResponse),
                child: const Text('Set sensor intervals'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*clr', onResponse: _handleAsciiResponse),
                child: const Text('Clear log'),
              ),
              ElevatedButton(
                onPressed: () =>
                    _transmit('*dummy', onResponse: _handleAsciiResponse),
                child: const Text('Dummy'),
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
