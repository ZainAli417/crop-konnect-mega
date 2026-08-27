import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

/// Calibration offsets added to the raw probe values before they are displayed
/// or saved. Defaults to no correction.
class SoilProbeCalibration {
  const SoilProbeCalibration({
    this.pollIntervalSeconds = 2,
    this.tempOffset = 0.0,
    this.moistureOffset = 0.0,
    this.ecOffset = 0,
    this.phOffset = 0.0,
    this.nOffset = 0,
    this.pOffset = 0,
    this.kOffset = 0,
  });

  final int pollIntervalSeconds;
  final double tempOffset;
  final double moistureOffset;
  final int ecOffset;
  final double phOffset;
  final int nOffset;
  final int pOffset;
  final int kOffset;
}

/// Reads a CWT-type NPK soil sensor over a USB-C RS-485 adapter using the
/// Modbus-RTU protocol. Ported from Crop Konnect UNO's `SensorProvider`: it
/// auto-connects to an attached USB serial device, polls it on an interval,
/// parses the 19-byte response frame (with CRC16 validation) and applies
/// calibration offsets.
///
/// Live values are exposed for the sampling screen; persistence to Supabase is
/// handled separately (see `SoilSampleRepository.saveSample`).
class SoilProbeService extends ChangeNotifier {
  SoilProbeService({this.calibration = const SoilProbeCalibration()}) {
    _initUsbListener();
    unawaited(connectToDevice());
  }

  static const Set<int> _knownSensorVendorIds = {6790, 1027, 4292};
  static final Uint8List _requestFrame = Uint8List.fromList([
    0x01, 0x03, 0x00, 0x00, 0x00, 0x07, 0x04, 0x08,
  ]);

  SoilProbeCalibration calibration;

  UsbPort? _port;
  String _status = 'Disconnected';

  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<UsbEvent>? _usbEventSub;
  final List<int> _buffer = [];

  bool _hasReceivedData = false;
  bool _isConnecting = false;
  bool _isPolling = false;
  bool _disposed = false;
  int _badFrameCount = 0;
  String _deviceName = '';

  // Calibrated metrics
  double temperature = 0.0;
  double moisture = 0.0;
  int ec = 0;
  double ph = 0.0;
  int n = 0;
  int p = 0;
  int k = 0;

  String get status => _status;
  bool get isConnected => _port != null;
  bool get isConnecting => _isConnecting;
  bool get hasData => _hasReceivedData;
  String get deviceName => _deviceName;

  @override
  void dispose() {
    _disposed = true;
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
    _dataSub?.cancel();
    _usbEventSub?.cancel();
    _port?.close();
    super.dispose();
  }

  /// Apply new calibration offsets and restart polling if the interval changed.
  void updateCalibration(SoilProbeCalibration value) {
    calibration = value;
    if (isConnected) {
      _startPolling();
    }
    if (!_disposed) notifyListeners();
  }

  void _initUsbListener() {
    _usbEventSub = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        _scheduleReconnect(const Duration(milliseconds: 300));
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        unawaited(_handlePortLost('Reconnecting…'));
      }
    });
  }

  Future<void> connectToDevice() async {
    if (_disposed || _isConnecting || _port != null) return;

    _isConnecting = true;
    _reconnectTimer?.cancel();
    _updateStatus('Scanning for device…');

    try {
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        _updateStatus('No USB device found');
        _scheduleReconnect();
        return;
      }

      final targetDevice = _selectTargetDevice(devices);
      final port = await targetDevice.create();
      if (port == null) {
        _updateStatus('Failed to open port');
        _scheduleReconnect();
        return;
      }

      final didOpen = await port.open();
      if (!didOpen) {
        await port.close();
        _updateStatus('Failed to open port');
        _scheduleReconnect();
        return;
      }

      _port = port;
      _deviceName = targetDevice.productName ??
          targetDevice.manufacturerName ??
          'USB Serial Device';
      await _port!.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      await _port!.setDTR(true);
      await _port!.setRTS(true);

      _badFrameCount = 0;
      _updateStatus('Waiting for data…');
      _setupDataStream();
      _startPolling();
    } catch (e) {
      debugPrint('USB connect error: $e');
      await _closeActivePort();
      _updateStatus('Failed to open port');
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  UsbDevice _selectTargetDevice(List<UsbDevice> devices) {
    final knownDevices = devices
        .where((device) => _knownSensorVendorIds.contains(device.vid))
        .toList();
    if (knownDevices.isNotEmpty) return knownDevices.first;
    return devices.first;
  }

  void _scheduleReconnect([Duration delay = const Duration(seconds: 2)]) {
    if (_disposed || _port != null || _isConnecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && _port == null) {
        unawaited(connectToDevice());
      }
    });
  }

  void _updateStatus(String status) {
    if (_disposed || _status == status) return;
    _status = status;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _closeActivePort();
    _deviceName = '';
    _updateStatus('Disconnected');
  }

  Future<void> _handlePortLost(String status) async {
    if (_disposed) return;
    await _closeActivePort();
    _updateStatus(status);
    _scheduleReconnect();
  }

  Future<void> _closeActivePort() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _dataSub?.cancel();
    _dataSub = null;
    _buffer.clear();
    _hasReceivedData = false;

    final port = _port;
    _port = null;
    if (port != null) {
      try {
        await port.close();
      } catch (e) {
        debugPrint('USB close error: $e');
      }
    }
  }

  void _setupDataStream() {
    _dataSub?.cancel();
    _buffer.clear();
    _dataSub = _port?.inputStream?.listen(
      (Uint8List data) {
        if (data.isEmpty) return;
        _buffer.addAll(data);
        if (_buffer.length > 256) {
          _buffer.removeRange(0, _buffer.length - 256);
        }
        _processBuffer();
      },
      onError: (Object e) {
        debugPrint('USB stream error: $e');
        unawaited(_handlePortLost('Reconnecting…'));
      },
      onDone: () => unawaited(_handlePortLost('Reconnecting…')),
      cancelOnError: true,
    );
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    final seconds = calibration.pollIntervalSeconds.clamp(1, 60).toInt();
    final interval = Duration(seconds: seconds);

    unawaited(_pollSensor());
    _pollingTimer = Timer.periodic(interval, (_) => unawaited(_pollSensor()));
  }

  Future<void> _pollSensor() async {
    final port = _port;
    if (port == null || _isPolling) return;

    _isPolling = true;
    try {
      await port
          .write(_requestFrame)
          .timeout(const Duration(milliseconds: 900));
    } catch (e) {
      debugPrint('Polling error: $e');
      if (identical(port, _port)) {
        await _handlePortLost('Reconnecting…');
      }
    } finally {
      _isPolling = false;
    }
  }

  void _processBuffer() {
    while (_buffer.length >= 19) {
      if (_buffer[0] == 0x01 && _buffer[1] == 0x03 && _buffer[2] == 0x0E) {
        final frame = _buffer.sublist(0, 19);
        _buffer.removeRange(0, 19);

        if (_checkCRC16(frame)) {
          _badFrameCount = 0;
          _parseData(frame);
        } else {
          _badFrameCount++;
          if (_badFrameCount >= 3) {
            _updateStatus('CRC error');
          }
        }
      } else {
        _buffer.removeAt(0);
      }
    }
  }

  bool _checkCRC16(List<int> frame) {
    if (frame.length < 3) return false;
    int crc = 0xFFFF;
    for (int i = 0; i < frame.length - 2; i++) {
      crc ^= frame[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    final expectedLow = crc & 0xFF;
    final expectedHigh = (crc >> 8) & 0xFF;
    return frame[frame.length - 2] == expectedLow &&
        frame[frame.length - 1] == expectedHigh;
  }

  void _parseData(List<int> frame) {
    // Register order per the CWT NPK-type manual: 0x0000=Humidity/Moisture,
    // 0x0001=Temperature.
    final rawMoisture = (frame[3] << 8) | frame[4];
    int rawTemp = (frame[5] << 8) | frame[6];
    final rawEC = (frame[7] << 8) | frame[8];
    final rawPH = (frame[9] << 8) | frame[10];
    final rawN = (frame[11] << 8) | frame[12];
    final rawP = (frame[13] << 8) | frame[14];
    final rawK = (frame[15] << 8) | frame[16];

    if (rawTemp > 32767) {
      rawTemp -= 65536;
    }

    moisture = (rawMoisture / 10.0) + calibration.moistureOffset;
    temperature = (rawTemp / 10.0) + calibration.tempOffset;
    ec = rawEC + calibration.ecOffset;
    ph = (rawPH / 10.0) + calibration.phOffset;
    n = rawN + calibration.nOffset;
    p = rawP + calibration.pOffset;
    k = rawK + calibration.kOffset;

    _hasReceivedData = true;
    _updateStatus('Connected');
    if (!_disposed) notifyListeners();
  }
}
