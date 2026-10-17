import 'dart:convert';
import 'dart:math';

final _secureRandom = Random.secure();
String newRecordId() =>
    base64UrlEncode(List<int>.generate(18, (_) => _secureRandom.nextInt(256)));
