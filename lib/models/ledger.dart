import 'dart:convert';

const idrCurrency = 'IDR';

enum AccountKind { cash, digital }
enum EntryKind { expense, income, adjustment }
enum EntrySource { manual, notification }

class Account {
  const Account({
    required this.id,
    required this.kind,
    required this.name,
    required this.openingMinor,
  });

  final String id;
  final AccountKind kind;
  final String name;
  final int openingMinor;

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'openingMinor': openingMinor,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        kind: AccountKind.values.byName(json['kind'] as String),
        name: json['name'] as String,
        openingMinor: json['openingMinor'] as int,
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.amountMinor,
    required this.occurredAt,
    required this.merchant,
    required this.note,
    required this.source,
    this.externalId,
  }) : assert(amountMinor > 0);

  final String id;
  final String accountId;
  final EntryKind kind;
  final int amountMinor;
  final DateTime occurredAt;
  final String merchant;
  final String note;
  final EntrySource source;
  final String? externalId;

  int get signedAmount => kind == EntryKind.expense ? -amountMinor : amountMinor;

  Map<String, Object?> toJson() => {
        'id': id,
        'accountId': accountId,
        'kind': kind.name,
        'amountMinor': amountMinor,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'merchant': merchant,
        'note': note,
        'source': source.name,
        'externalId': externalId,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: json['id'] as String,
        accountId: json['accountId'] as String,
        kind: EntryKind.values.byName(json['kind'] as String),
        amountMinor: json['amountMinor'] as int,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        merchant: json['merchant'] as String,
        note: json['note'] as String,
        source: EntrySource.values.byName(json['source'] as String),
        externalId: json['externalId'] as String?,
      );
}

class PendingCandidate {
  const PendingCandidate({
    required this.externalId,
    required this.accountId,
    required this.amountMinor,
    required this.merchant,
    required this.occurredAt,
    required this.packageName,
    required this.confidence,
  });

  final String externalId;
  final String accountId;
  final int amountMinor;
  final String merchant;
  final DateTime occurredAt;
  final String packageName;
  final double confidence;

  Map<String, Object> toJson() => {
        'externalId': externalId,
        'accountId': accountId,
        'amountMinor': amountMinor,
        'merchant': merchant,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'packageName': packageName,
        'confidence': confidence,
      };

  factory PendingCandidate.fromJson(Map<String, dynamic> json) => PendingCandidate(
        externalId: json['externalId'] as String,
        accountId: json['accountId'] as String,
        amountMinor: json['amountMinor'] as int,
        merchant: json['merchant'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        packageName: json['packageName'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class Ledger {
  Ledger({List<Account>? accounts, List<LedgerEntry>? entries})
      : accounts = accounts ?? <Account>[],
        entries = entries ?? <LedgerEntry>[];

  List<Account> accounts;
  List<LedgerEntry> entries;

  int balanceFor(String accountId) {
    final account = accounts.firstWhere((item) => item.id == accountId);
    return account.openingMinor + entries
        .where((entry) => entry.accountId == accountId)
        .fold(0, (sum, entry) => sum + entry.signedAmount);
  }

  bool containsExternalId(String externalId) => entries.any((entry) => entry.externalId == externalId);

  bool addEntry(LedgerEntry entry) {
    if (containsExternalId(entry.externalId ?? '')) return false;
    entries.add(entry);
    return true;
  }

  Map<String, Object> toJson() => {
        'version': 1,
        'accounts': accounts.map((item) => item.toJson()).toList(),
        'entries': entries.map((item) => item.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  factory Ledger.fromJson(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return Ledger(
      accounts: (json['accounts'] as List<dynamic>)
          .map((item) => Account.fromJson(item as Map<String, dynamic>))
          .toList(),
      entries: (json['entries'] as List<dynamic>)
          .map((item) => LedgerEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

String parseIdrAmount(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) throw const FormatException('Enter an amount in rupiah.');
  final amount = int.tryParse(digits);
  if (amount == null || amount <= 0) throw const FormatException('Amount must be positive.');
  return amount.toString();
}
