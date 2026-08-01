import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ledger.dart';

class LedgerStore {
  LedgerStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'trackit.ledger.v1';
  final FlutterSecureStorage _storage;

  Future<Ledger> load() async {
    final value = await _storage.read(key: _key);
    return value == null ? Ledger() : Ledger.fromJson(value);
  }

  Future<void> save(Ledger ledger) =>
      _storage.write(key: _key, value: ledger.encode());
}
