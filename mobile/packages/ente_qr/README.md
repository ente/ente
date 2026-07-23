# ente_qr

A Flutter plugin for scanning QR codes from image files. This plugin provides a simple interface to scan QR codes from images across Ente mobile and desktop apps.

## Features

- Scan QR codes from image files
- Support for Android using zxing-cpp
- Support for iOS and macOS using Vision
- Dart fallback for desktop platforms without native plugin support
- Returns structured results with error handling
- Works with images from file picker or camera

## Platform Support

| Platform | Support |
| -------- | ------- |
| Android  | ✅      |
| iOS      | ✅      |
| Web      | ❌      |
| macOS    | ✅      |
| Windows  | ✅      |
| Linux    | ✅      |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  ente_qr:
    path: path/to/ente_qr
```

## Usage

### Basic Usage

```dart
import 'package:ente_qr/ente_qr.dart';

final qr = EnteQr();

// Scan QR code from an image file
final result = await qr.scanQrFromImage('/path/to/image.jpg');

if (result.success) {
  print('QR Code content: ${result.content}');
} else {
  print('Error: ${result.error}');
}
```

### Complete Example with File Picker

```dart
import 'package:flutter/material.dart';
import 'package:ente_qr/ente_qr.dart';
import 'package:file_picker/file_picker.dart';

class QrScannerPage extends StatefulWidget {
  @override
  _QrScannerPageState createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _enteQr = EnteQr();
  String _result = 'No QR code scanned';

  Future<void> _scanQrFromImage() async {
    // Pick an image file
    FilePickerResult? fileResult = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (fileResult != null && fileResult.files.single.path != null) {
      final imagePath = fileResult.files.single.path!;

      // Scan QR code from the selected image
      final qrResult = await _enteQr.scanQrFromImage(imagePath);

      setState(() {
        if (qrResult.success) {
          _result = 'QR Code: ${qrResult.content}';
        } else {
          _result = 'Error: ${qrResult.error}';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('QR Scanner')),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: _scanQrFromImage,
            child: Text('Pick Image and Scan QR'),
          ),
          Text(_result),
        ],
      ),
    );
  }
}
```

## API Reference

### EnteQr

The main class for QR code scanning operations.

#### Methods

##### `scanQrFromImage(String imagePath)`

Scans a QR code from an image file.

**Parameters:**

- `imagePath` (String): The file path to the image containing the QR code

**Returns:**

- `Future<QrScanResult>`: A result object containing either the QR code content or an error

### QrScanResult

The result object returned by QR scanning operations.

**Properties:**

- `content` (String?): The QR code content if successful, null otherwise
- `error` (String?): Error message if scanning failed, null otherwise
- `success` (bool): Whether the scanning operation was successful

**Factory Constructors:**

- `QrScanResult.success(String content)`: Creates a successful result
- `QrScanResult.error(String error)`: Creates an error result

## Implementation Details

### Android

The Android implementation uses the ZXing library (com.google.zxing) for QR code detection:

- `com.journeyapps:zxing-android-embedded:4.3.0`
- `com.google.zxing:core:3.5.1`

### iOS

The iOS implementation uses Core Image framework's built-in QR code detection capabilities via `CIDetector`.

## Error Handling

The plugin provides comprehensive error handling for common scenarios:

- File not found
- Invalid image format
- No QR code found in image
- Platform-specific errors
- Unexpected errors

All errors are returned as part of the `QrScanResult` object with descriptive error messages.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the same license as the Ente project.
