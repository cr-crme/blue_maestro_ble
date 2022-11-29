import 'dart:async';

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
  int _redoCountdown = 0;
  String _lastCommand = '';

  @override
  void initState() {
    super.initState();

    _isBleReady = _connectBleThermal();
  }

  Future<bool> _connectBleThermal() async {
    final errorCode = await _bleThermal.tryInitialize(context);
    if (errorCode == BleThermalStatusCode.success) {
      setState(() {});
    } else {
      _processError(errorCode, 'retrying in 5 seconds');
      await Future.delayed(const Duration(seconds: 5));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isBleReady = _connectBleThermal();
      });
      return false;
    }

    if (errorCode == BleThermalStatusCode.success) _writeOutput = 'Connected';
    return errorCode == BleThermalStatusCode.success;
  }

  void _printResponse(String response) {
    setState(() {
      _writeOutput ??= 'Response:\n';

      _writeOutput = response == ''
          ? '$_writeOutput\nReceived empty data'
          : '$_writeOutput\n$response';
      return;
    });
  }

  void _processError(BleThermalStatusCode errorCode, String? message) {
    // Sometimes the error processing is called even though we got an answer
    // If so, just ignore the error
    if (_writeOutput != null) return;

    late String errorMessage;
    if (errorCode == BleThermalStatusCode.couldNotInitializeDevice) {
      errorMessage = 'Could not initialize the device';
    } else if (errorCode == BleThermalStatusCode.couldNotScan) {
      errorMessage = 'Could not scan for bluetooth devices.\n'
          'Please make sure bluetooth is activated and Location '
          'permission are granted to the app';
    } else if (errorCode == BleThermalStatusCode.couldNotFindDevice) {
      errorMessage = 'Could not find the device';
    } else if (errorCode == BleThermalStatusCode.couldNotFindServices) {
      errorMessage = 'Could not find services';
    } else if (errorCode == BleThermalStatusCode.couldNotSubscribe) {
      errorMessage = 'Could not subscribe to services';
    } else {
      errorMessage = 'Unknown error';
    }
    if (message != null) errorMessage += ', $message';

    if (_redoCountdown > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _transmit(_lastCommand, resetCountdown: false);
        _redoCountdown--;
      });
      errorMessage += '\nRetrying for $_redoCountdown times';
    }

    final snackBar = SnackBar(
      content: Text(errorMessage),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);

    setState(() {
      _isTransmitting = false;
      _writeOutput = 'Failed';
    });
  }

  Future<void> _transmit(String command, {resetCountdown = true}) async {
    if (resetCountdown) _redoCountdown = 3;

    try {
      _lastCommand = command;
      setState(() {
        _writeOutput = null;
        _isTransmitting = true;
      });
      await _bleThermal.transmit(context, command,
          responseCallback: _printResponse,
          onErrorCallback: (status) => _processError(status, null));
    } catch (_) {
      _processError(BleThermalStatusCode.unknownError, null);
    } finally {
      setState(() => _isTransmitting = false);
    }
  }

  Future<void> _transmitWithNumbers(String command, String title) async {
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
    _transmit(newCommand);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _isBleReady,
        builder: (context, isBleReady) {
          if (isBleReady.hasData && isBleReady.data!) {
            return Scaffold(
              appBar: AppBar(title: Text(_bleThermal.name)),
              body: SingleChildScrollView(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => _transmit('*batt'),
                        child: const Text('Battery level'),
                      ),
                      ElevatedButton(
                        onPressed: () => _transmit('*info'),
                        child: const Text('Information'),
                      ),
                      ElevatedButton(
                        onPressed: () => _transmit('*tell'),
                        child: const Text('Telemetrics'),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => _transmit('*loggert'),
                        child: const Text('Temperature log'),
                      ),
                      ElevatedButton(
                        onPressed: () => _transmit('*loggerh'),
                        child: const Text('Humidity log'),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () =>
                            _transmitWithNumbers('*lint', 'Time in seconds'),
                        child: const Text('Set log intervals'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            _transmitWithNumbers('*sint', 'Time in seconds'),
                        child: const Text('Set sensor intervals'),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => _transmit('*clr'),
                        child: const Text('Clear log'),
                      ),
                      ElevatedButton(
                        onPressed: () => _transmit('not a real command'),
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
          } else {
            return Scaffold(
                appBar: AppBar(title: const Text('Searching for device')),
                body: const Center(child: CircularProgressIndicator()));
          }
        });
  }
}
