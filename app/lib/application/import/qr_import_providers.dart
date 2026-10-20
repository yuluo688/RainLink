import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/import/qr_import.dart';

final qrImportParserProvider = Provider<QrImportParser>((ref) {
  throw StateError('QrImportParser must be provided during bootstrap.');
});
