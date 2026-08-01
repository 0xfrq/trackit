import 'package:flutter_test/flutter_test.dart';
import 'package:trackit/models/ledger.dart';

void main() {
  test('calculates IDR balances using integer amounts', () {
    final ledger = Ledger(accounts: [
      const Account(
        id: 'digital',
        kind: AccountKind.digital,
        name: 'Digital',
        openingMinor: 100000,
      ),
    ]);
    ledger.addEntry(LedgerEntry(
      id: '1',
      accountId: 'digital',
      kind: EntryKind.expense,
      amountMinor: 12500,
      occurredAt: DateTime.utc(2026, 1, 1),
      merchant: 'Coffee',
      note: '',
      source: EntrySource.manual,
    ));
    expect(ledger.balanceFor('digital'), 87500);
  });

  test('rejects duplicate imported entries', () {
    final ledger = Ledger(accounts: [
      const Account(
        id: 'digital',
        kind: AccountKind.digital,
        name: 'Digital',
        openingMinor: 0,
      ),
    ]);
    final entry = LedgerEntry(
      id: '1',
      accountId: 'digital',
      kind: EntryKind.expense,
      amountMinor: 5000,
      occurredAt: DateTime.utc(2026, 1, 1),
      merchant: 'Shop',
      note: '',
      source: EntrySource.notification,
      externalId: 'notification-1',
    );
    expect(ledger.addEntry(entry), isTrue);
    expect(ledger.addEntry(entry), isFalse);
    expect(ledger.entries, hasLength(1));
  });

  test('parses formatted rupiah input', () {
    expect(parseIdrAmount('Rp 1.250.000'), '1250000');
    expect(() => parseIdrAmount('none'), throwsFormatException);
  });
}
