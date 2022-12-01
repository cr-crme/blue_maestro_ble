import 'dart:async';

import 'package:flutter/foundation.dart';
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
      _showErrorCode(status, extraMessage: 'retrying in 10 seconds');
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

  void _handleAsciiResponse(List<int> response) {
    setState(() {
      final responseAsString = String.fromCharCodes(_bleThermal.responseLog);

      _writeOutput = responseAsString == ''
          ? 'Received empty data'
          : 'Response:\n$responseAsString';
      return;
    });
  }

  List<int> _toMeasure(List<int> entries) {
    Uint8List byteList = Uint8List.fromList(entries);

    // Convert each successive pairs to int16 as Big Endian
    final List<int> measures = [];
    for (int i = 0; i < entries.length; i += 2) {
      ByteData byteData = ByteData.sublistView(byteList, i, i + 2);
      measures.add(byteData.getInt16(0, Endian.big));
    }
    return measures;
  }

  void _handleLogallResponse(List<int> response) {
    ///
    /// The '*logall' command, contrary to all other responses, is not in ASCII.
    /// It is made from a first header of 15 bytes. The first 2 are for
    /// the number of temperature measures, the next 2 are for the number
    /// humidity measures, the next 2 are for the number of atmospheric
    /// pressure. I could not figure out the remaining 9 bytes, but I suspect
    /// the last few are timestamp.
    /// The next responses are the sensor measurements made of 20 bytes,
    /// corresponding to 10 big endian int16 measurements. After the last
    /// measurement two bytes are sent (0x2C 0x2C) and the remmaining bytes
    /// are 0 padded. Then the next sensor is sent.
    /// The order of the sensors is
    /// temperature, humidity and atmospheric pressure.

    final entries = _bleThermal.responseLog;
    const headerSize = 15;
    if (entries.length < headerSize) return; // Chech if we received the header

    // We are extracting some values *per sensor* from the header
    final List<int> numberMeasurements =
        _toMeasure(entries.getRange(0, 6).toList()); // number measurements

    // For each sensor
    var runningCountFirst = headerSize; // First entry starts after header
    final List<int> firstMeasurements = []; // position of the starting
    for (var numberMeasurement in numberMeasurements) {
      firstMeasurements.add(runningCountFirst);
      // Compute the number of bytes (including the padding) so we can compute
      // next first measurement position
      runningCountFirst += (numberMeasurement / 10).ceil() * 20;
    }
    final lastBytePosition = runningCountFirst;

    // If there are still data to come
    debugPrint(entries.length.toString());
    debugPrint(lastBytePosition.toString());
    if (entries.length < lastBytePosition) return;
    if (entries.length > lastBytePosition) {
      throw Exception('Too much packages!');
    }

    // Convert each successive pairs to int16 as Big Endian
    final List<List<int>> measurements = [];
    for (var i = 0; i < 3; i++) {
      measurements.add(_toMeasure(entries
          .getRange(firstMeasurements[i],
              firstMeasurements[i] + numberMeasurements[i])
          .toList()));
    }

    setState(() {
      _writeOutput = 'Temperature = ${measurements[0]}.\n\n'
          'Humidity = ${measurements[1]}\n\n'
          'Atmospheric pressure = ${measurements[2]}';
    });
  }

  void _showErrorCode(BleThermalStatusCode errorCode, {String? extraMessage}) {
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
      {required Function(List<int> response) onResponse}) async {
    _bleThermal.responseLog.clear();
    setState(() {
      _writeOutput = null;
      _isTransmitting = true;
    });

    final status = await _bleThermal.transmit(command, onResponse: onResponse);
    if (status != BleThermalStatusCode.success) {
      _showErrorCode(status);
    }

    setState(() => _isTransmitting = false);
  }

  Future<void> _transmitWithNumbers(String command, String title,
      {required Function(List<int> response) onResponse}) async {
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
                    _transmit('*logall', onResponse: _handleLogallResponse),
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
