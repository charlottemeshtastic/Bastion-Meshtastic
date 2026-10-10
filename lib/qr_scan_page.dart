import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans one QR code with the camera and returns its text.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.title = 'Scan QR code'});

  final String title;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Flashlight',
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: _controller.toggleTorch,
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission is needed to scan. Allow it for Bastion in Android settings, or paste the link instead.'
                        : 'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Point the camera at a Meshtastic channel QR code.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
