import 'package:flutter/material.dart';

import 'models/ledger.dart';
import 'notification_bridge.dart';
import 'storage/ledger_store.dart';

void main() => runApp(const TrackitApp());

class TrackitApp extends StatelessWidget {
  const TrackitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Trackit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffe96942),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xfffffbf5),
          useMaterial3: true,
        ),
        home: const TrackitHome(),
      );
}

class TrackitHome extends StatefulWidget {
  const TrackitHome({super.key});

  @override
  State<TrackitHome> createState() => _TrackitHomeState();
}

class _TrackitHomeState extends State<TrackitHome> with WidgetsBindingObserver {
  final _store = LedgerStore();
  final _bridge = NotificationBridge();
  Ledger _ledger = Ledger();
  List<PendingCandidate> _pending = [];
  bool _loading = true;
  bool _accessEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPending();
  }

  Future<void> _load() async {
    final ledger = await _store.load();
    if (!mounted) return;
    setState(() {
      _ledger = ledger;
      _loading = false;
    });
    await _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final enabled = await _bridge.isAccessEnabled();
      final pending = await _bridge.drainCandidates();
      if (mounted) {
        setState(() {
          _accessEnabled = enabled;
          _pending = pending;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _accessEnabled = false);
    }
  }

  Future<void> _save() async => _store.save(_ledger);

  Future<void> _setup() async {
    final cash = await _amountDialog('Cash balance');
    if (cash == null) return;
    final digital = await _amountDialog('Digital balance');
    if (digital == null) return;
    setState(() {
      _ledger.accounts = [
        Account(
          id: 'cash',
          kind: AccountKind.cash,
          name: 'Cash',
          openingMinor: cash,
        ),
        Account(
          id: 'digital',
          kind: AccountKind.digital,
          name: 'Digital',
          openingMinor: digital,
        ),
      ];
    });
    await _save();
  }

  Future<int?> _amountDialog(String title) async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: 'Rp '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(
                  context,
                  int.parse(parseIdrAmount(controller.text)),
                );
              } on FormatException catch (error) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addManual() async {
    if (_ledger.accounts.isEmpty) return _setup();
    final amount = await _amountDialog('Expense amount');
    if (amount == null) return;
    final entry = LedgerEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      accountId: _ledger.accounts.first.id,
      kind: EntryKind.expense,
      amountMinor: amount,
      occurredAt: DateTime.now(),
      merchant: 'Manual expense',
      note: '',
      source: EntrySource.manual,
    );
    setState(() => _ledger.addEntry(entry));
    await _save();
  }

  Future<void> _confirm(PendingCandidate candidate) async {
    final entry = LedgerEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      accountId: candidate.accountId,
      kind: EntryKind.expense,
      amountMinor: candidate.amountMinor,
      occurredAt: candidate.occurredAt,
      merchant: candidate.merchant,
      note: 'Imported from ${candidate.packageName}',
      source: EntrySource.notification,
      externalId: candidate.externalId,
    );
    if (_ledger.addEntry(entry)) await _save();
    await _bridge.acknowledge(candidate.externalId);
    if (mounted) setState(() => _pending.remove(candidate));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final configured = _ledger.accounts.length == 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trackit'),
        actions: [IconButton(onPressed: _setup, icon: const Icon(Icons.tune))],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPending,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Your money, in one view',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              configured
                  ? 'IDR balances · updated locally'
                  : 'Set your starting balances to begin.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (!configured) _setupCard() else _balanceCards(),
            const SizedBox(height: 20),
            _accessCard(),
            if (_pending.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Review from notifications',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._pending.map(_candidateTile),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addManual,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 32),
              const SizedBox(height: 12),
              Text(
                'Start with two balances',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep cash and digital money separate, then see the total at a glance.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _setup, child: const Text('Set balances')),
            ],
          ),
        ),
      );

  Widget _balanceCards() => Column(
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total balance'),
                  Text(
                    _money(
                      _ledger.accounts.fold(
                        0,
                        (sum, account) => sum + _ledger.balanceFor(account.id),
                      ),
                    ),
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _ledger.accounts
                .map(
                  (account) => Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              account.kind == AccountKind.cash
                                  ? Icons.payments_outlined
                                  : Icons.phone_android_outlined,
                            ),
                            const SizedBox(height: 8),
                            Text(account.name),
                            const SizedBox(height: 4),
                            Text(
                              _money(_ledger.balanceFor(account.id)),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      );

  Widget _accessCard() => Card(
        child: ListTile(
          leading: Icon(
            _accessEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
          ),
          title: Text(
            _accessEnabled
                ? 'Payment notifications connected'
                : 'Connect payment notifications',
          ),
          subtitle: const Text(
            'Only supported payment apps are processed on this device.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _bridge.openSettings,
        ),
      );

  Widget _candidateTile(PendingCandidate candidate) => Card(
        child: ListTile(
          title: Text(candidate.merchant),
          subtitle: Text(
            '${_money(candidate.amountMinor)} · ${candidate.packageName}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.check_circle_outline),
            onPressed: () => _confirm(candidate),
          ),
        ),
      );

  String _money(int value) =>
      'Rp ${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';
}
