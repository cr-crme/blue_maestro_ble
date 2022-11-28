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
  late String _writeOutput;
  late StreamSubscription<List<int>>? _subscribeStream;
  late TextEditingController _textEditingController;

  final _bleThermal = BleThermal();
  late Future<bool> _isBleReady;
  bool _isTransmitting = false;

  @override
  void initState() {
    super.initState();

    _isBleReady = _connectBleThermal();

    _writeOutput = '';
    _textEditingController = TextEditingController();
  }

  Future<bool> _connectBleThermal() async {
    final errorMessage = await _bleThermal.tryInitialize(context);
    if (errorMessage == null) {
      setState(() {});
    } else {
      _processError('$errorMessage, retrying in 5 seconds');
      await Future.delayed(const Duration(seconds: 5));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isBleReady = _connectBleThermal();
      });
    }

    return errorMessage == null;
  }

  @override
  void dispose() {
    _subscribeStream?.cancel();
    super.dispose();
  }

  void _printResponse(String response) {
    setState(() {
      _writeOutput = response;
      return;
    });
  }

  void _processError(String message) {
    final snackBar = SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);

    setState(() {
      _isTransmitting = false;
      _writeOutput = 'Failed';
      return;
    });
  }

  Future<void> _transmit() async {
    setState(() => _isTransmitting = true);
    await _bleThermal.transmit(context, _textEditingController.text,
        responseCallback: _printResponse, onErrorCallback: _processError);
    setState(() => _isTransmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _isBleReady,
        builder: (context, isBleReady) {
          if (isBleReady.hasData && isBleReady.data!) {
            return Scaffold(
              appBar: AppBar(title: Text(_bleThermal.name)),
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _isTransmitting
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
                            controller: _textEditingController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Command',
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _transmit,
                          child: const Text('With response'),
                        ),
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.only(bottom: 28.0),
                          child: Text('Output: $_writeOutput'),
                        ),
                      ],
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
