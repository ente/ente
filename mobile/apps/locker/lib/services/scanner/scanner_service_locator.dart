import 'package:locker/services/scanner/document_scanner_service.dart';
import 'package:locker/services/scanner/rust_document_scanner_service.dart';

DocumentScannerService? _documentScannerService;

DocumentScannerService get documentScannerService =>
    _documentScannerService ??= RustDocumentScannerService();
