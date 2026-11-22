// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'auth.dart';

void main() => runApp(const PiggyLogApp());

class PiggyLogApp extends StatelessWidget {
  const PiggyLogApp({this.authRepository, super.key});

  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PiggyLog',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167c68)),
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    ),
    home: _SessionGate(repository: authRepository ?? ServerAuthRepository()),
  );
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.repository});
  final AuthRepository repository;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  SavedSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await widget.repository.loadSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  void _onLogin(SavedSession session) => setState(() => _session = session);

  Future<void> _logout() async {
    final session = _session;
    if (session == null) return;
    try {
      await widget.repository.logout(session);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session lokal dihapus. Server: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _session = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session == null) {
      return LoginPage(repository: widget.repository, onLogin: _onLogin);
    }
    return SavingsPage(
      session: session,
      repository: widget.repository,
      onLogout: _logout,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.repository, required this.onLogin, super.key});

  final AuthRepository repository;
  final ValueChanged<SavedSession> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _connected = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _busy = true;
      _connected = false;
      _error = null;
    });
    try {
      await widget.repository.checkConnection(_serverController.text);
      if (mounted) setState(() => _connected = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException ? error.message : 'Tidak dapat menghubungi server. Periksa URL dan koneksi jaringan.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.repository.login(
        _serverController.text,
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (mounted) widget.onLogin(session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Login gagal. Periksa koneksi server dan kredensial.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xffd2d9d6)),
    );
    final decoration = InputDecoration(
      filled: true,
      fillColor: const Color(0xfff5f7f6),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xfff7f8f7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.savings_outlined, size: 52),
                  const SizedBox(height: 12),
                  Text(
                    'PiggyLog',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hubungkan ke server untuk melanjutkan',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const ValueKey('server-url-field'),
                    controller: _serverController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    readOnly: _connected,
                    decoration: decoration.copyWith(
                      labelText: 'Server URL',
                      hintText: 'https://piggylog.example.com',
                      prefixIcon: const Icon(Icons.dns_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('check-server-button'),
                    onPressed: _busy ? null : _checkConnection,
                    icon: _busy && !_connected
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: const Text('Check connection'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: const StadiumBorder(),
                    ),
                  ),
                  if (_connected) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Color(0xff167c68)),
                        SizedBox(width: 8),
                        Text('Server terhubung'),
                      ],
                    ),
                    TextButton.icon(
                      key: const ValueKey('edit-server-button'),
                      onPressed: () => setState(() => _connected = false),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Change server URL'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('username-field'),
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: decoration.copyWith(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('password-field'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onSubmitted: (_) => _busy ? null : _login(),
                      decoration: decoration.copyWith(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('login-button'),
                      onPressed: _busy ? null : _login,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: const StadiumBorder(),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log in'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('login-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum AssetType { idr, sar, usd, gold }

extension AssetTypeLabel on AssetType {
  String get label => switch (this) {
    AssetType.idr => 'IDR · Rupiah',
    AssetType.sar => 'SAR · Riyal',
    AssetType.usd => 'USD · US Dollar',
    AssetType.gold => 'Gold · Emas',
  };
  String get shortCode => switch (this) {
    AssetType.idr => 'IDR',
    AssetType.sar => 'SAR',
    AssetType.usd => 'USD',
    AssetType.gold => 'GOLD',
  };
  String get symbol => switch (this) {
    AssetType.idr => 'Rp ',
    AssetType.sar => 'SAR ',
    AssetType.usd => r'$ ',
    AssetType.gold => 'g ',
  };
}

class SavingEntry {
  const SavingEntry({
    this.id,
    required this.asset,
    required this.amount,
    required this.source,
    required this.date,
    this.costBasisIdr,
    this.kind = 'saving',
  });
  final int? id;
  final AssetType asset;
  final double amount;
  final String source;
  final DateTime date;
  final double? costBasisIdr;
  final String kind;

  Map<String, Object> toJson() => {
    if (id != null) 'id': id!,
    'asset': asset.name,
    'amount': amount,
    'source': source,
    'date': date.toIso8601String(),
    if (costBasisIdr != null) 'costBasisIdr': costBasisIdr!,
    'kind': kind,
  };

  factory SavingEntry.fromJson(Map<String, dynamic> json) => SavingEntry(
    id: json['id'] as int?,
    asset: AssetType.values.byName(json['asset'] as String),
    amount: (json['amount'] as num).toDouble(),
    source: json['source'] as String? ?? '',
    date: DateTime.parse(json['date'] as String),
    costBasisIdr: (json['costBasisIdr'] as num?)?.toDouble(),
    kind: json['kind'] as String? ?? 'saving',
  );

  Map<String, Object?> toApiJson() => {
    'asset': asset.name,
    'amount': amount,
    'source': source,
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    if (costBasisIdr != null) 'cost_basis_idr': costBasisIdr!,
  };
}

class SavingsPage extends StatefulWidget {
  const SavingsPage({
    required this.session,
    required this.repository,
    required this.onLogout,
    super.key,
  });

  final SavedSession session;
  final AuthRepository repository;
  final Future<void> Function() onLogout;

  @override
  State<SavingsPage> createState() => _SavingsPageState();
}

class _SavingsPageState extends State<SavingsPage> {
  final _pageController = PageController(initialPage: 1);
  final List<SavingEntry> _entries = [];
  int _page = 1;
  double _totalIdr = 0;
  double _profitIdr = 0;
  double _profitPercent = 0;
  Map<String, dynamic> _prices = {};
  String? _syncError;
  bool _refreshingPrices = false;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    await _restoreCache();
    if (!mounted) return;
    await Future.wait([_syncEntries(), _syncPrices()]);
    await _syncSummary();
  }

  Future<void> _restoreCache() async {
    try {
      final cached = await widget.repository.loadEntriesCache(
        widget.session.serverUrl,
      );
      if (cached != null) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        final entries =
            decoded
                .map(
                  (item) => SavingEntry.fromJson(item as Map<String, dynamic>),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        if (mounted)
          setState(() {
            _entries
              ..clear()
              ..addAll(entries);
          });
      }
    } on FormatException catch (error) {
      _setSyncError('Invalid cached savings data: $error');
    } on TypeError catch (error) {
      _setSyncError('Invalid cached savings data: $error');
    } on ArgumentError catch (error) {
      _setSyncError('Invalid cached savings data: $error');
    } catch (error) {
      _setSyncError('Could not read saved savings: $error');
    }

    try {
      final summary = await widget.repository.loadSummaryCache(
        widget.session.serverUrl,
      );
      if (summary != null) _applySummary(summary);
    } catch (error) {
      _setSyncError('Could not read saved summary: $error');
    }

    try {
      final prices = await widget.repository.loadPricesCache(
        widget.session.serverUrl,
      );
      if (prices != null) _applyPrices(prices);
    } catch (error) {
      _setSyncError('Could not read saved prices: $error');
    }
  }

  void _applySummary(Map<String, dynamic> summary) {
    if (!mounted) return;
    setState(() {
      _totalIdr = (summary['totalIdr'] as num?)?.toDouble() ?? 0;
      _profitIdr = (summary['profitIdr'] as num?)?.toDouble() ?? 0;
      _profitPercent = (summary['profitPercent'] as num?)?.toDouble() ?? 0;
    });
  }

  void _applyPrices(Map<String, dynamic> payload) {
    final prices = payload['prices'];
    if (prices is! Map<String, dynamic>) {
      throw const ApiException('Respons harga server tidak valid.');
    }
    if (mounted) setState(() => _prices = prices);
  }

  void _setSyncError(String message) {
    if (mounted) setState(() => _syncError = message);
  }

  void _showError(String message, Object error) {
    if (!mounted) return;
    setState(() => _syncError = '$message: $error');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$message: $error')));
  }

  Future<void> _syncEntries() async {
    try {
      final remoteEntries = (await widget.repository.loadEntries(
        widget.session,
      )).map(SavingEntry.fromJson).toList();
      final unsynced = <SavingEntry>[];
      final cachedUnsynced = _entries
          .where((entry) => entry.id == null)
          .toList();
      final unmatchedRemoteEntries = List<SavingEntry>.of(remoteEntries);
      for (final entry in cachedUnsynced) {
        final match = unmatchedRemoteEntries.indexWhere(
          (remote) => _sameEntry(remote, entry),
        );
        if (match >= 0) {
          unmatchedRemoteEntries.removeAt(match);
          continue;
        }
        try {
          final created = await widget.repository.createEntry(
            widget.session,
            entry.toApiJson(),
          );
          remoteEntries.add(SavingEntry.fromJson(created));
        } catch (error) {
          unsynced.add(entry);
          _setSyncError('Some saved entries are not synced: $error');
        }
      }
      final entries = [...remoteEntries, ...unsynced]
        ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
      });
      await _saveEntriesCache();
    } catch (error) {
      _setSyncError('Could not sync savings from server: $error');
    }
  }

  bool _sameEntry(SavingEntry a, SavingEntry b) =>
      a.asset == b.asset &&
      a.source.trim() == b.source.trim() &&
      (a.amount - b.amount).abs() < 1e-9 &&
      a.date.year == b.date.year &&
      a.date.month == b.date.month &&
      a.date.day == b.date.day;

  Future<void> _syncPrices() async {
    try {
      var payload = await widget.repository.loadPrices(widget.session);
      final prices = payload['prices'];
      if (prices is! Map<String, dynamic> || prices.isEmpty) {
        payload = await widget.repository.refreshPrices(widget.session);
      }
      _applyPrices(payload);
      await widget.repository.savePricesCache(
        widget.session.serverUrl,
        payload,
      );
    } catch (error) {
      _setSyncError('Could not load current prices: $error');
    }
  }

  Future<void> _syncSummary() async {
    try {
      final summary = await widget.repository.loadSummary(widget.session);
      _applySummary(summary);
      await widget.repository.saveSummaryCache(
        widget.session.serverUrl,
        summary,
      );
    } catch (error) {
      _setSyncError('Could not load profit summary: $error');
    }
  }

  Future<void> _saveEntriesCache() async {
    try {
      await widget.repository.saveEntriesCache(
        widget.session.serverUrl,
        jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (error) {
      _showError('Could not save local savings cache', error);
    }
  }

  Future<void> _insertEntry(SavingEntry entry) async {
    try {
      final created = await widget.repository.createEntry(
        widget.session,
        entry.toApiJson(),
      );
      final saved = SavingEntry.fromJson(created);
      if (!mounted) return;
      setState(() {
        _entries.add(saved);
        _entries.sort((a, b) => b.date.compareTo(a.date));
      });
      await _saveEntriesCache();
      await _syncSummary();
    } catch (error) {
      _showError('Saving was not recorded on the server', error);
    }
  }

  Future<void> _deleteEntry(SavingEntry entry) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saving?'),
        content: const Text('This entry will be removed from history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (delete == true) {
      if (entry.kind != 'saving') {
        _showError(
          'This entry cannot be deleted directly',
          'It is a conversion record.',
        );
        return;
      }
      if (entry.id == null) {
        _showError(
          'This entry is not synced yet',
          'Try again when the server is available.',
        );
        return;
      }
      try {
        await widget.repository.deleteEntry(widget.session, entry.id!);
        if (mounted) setState(() => _entries.remove(entry));
        await _saveEntriesCache();
        await _syncSummary();
      } catch (error) {
        _showError('Saving was not deleted', error);
      }
    }
  }

  Future<void> _refreshPrices() async {
    if (_refreshingPrices) return;
    setState(() => _refreshingPrices = true);
    try {
      final payload = await widget.repository.refreshPrices(widget.session);
      _applyPrices(payload);
      await widget.repository.savePricesCache(
        widget.session.serverUrl,
        payload,
      );
      await _syncSummary();
      if (mounted) setState(() => _syncError = null);
    } catch (error) {
      _showError('Could not refresh prices', error);
    } finally {
      if (mounted) setState(() => _refreshingPrices = false);
    }
  }

  Future<void> _convert() async {
    final conversion = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ConvertSheet(),
    );
    if (conversion == null) return;
    try {
      await widget.repository.createConversion(widget.session, conversion);
      await _syncEntries();
      await _syncSummary();
    } catch (error) {
      _showError('Conversion was not recorded', error);
    }
  }

  Future<void> _addSaving() async {
    final entry = await showModalBottomSheet<SavingEntry>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (_) => const _AddSavingSheet(),
    );
    if (entry != null) await _insertEntry(entry);
  }

  void _go(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff7f8f7),
    body: Stack(
      children: [
        PageView(
          controller: _pageController,
          onPageChanged: (page) => setState(() => _page = page),
          children: [
            _PricesPage(
              prices: _prices,
              error: _syncError,
              refreshing: _refreshingPrices,
              onRefresh: _refreshPrices,
            ),
            _HomePage(
              entries: _entries,
              totalIdr: _totalIdr,
              profitIdr: _profitIdr,
              profitPercent: _profitPercent,
              syncError: _syncError,
              onDelete: _deleteEntry,
              onConvert: _convert,
            ),
            _SettingsPage(
              serverUrl: widget.session.serverUrl,
              onLogout: widget.onLogout,
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _BottomNav(page: _page, onTap: _go, onAdd: _addSaving),
        ),
      ],
    ),
  );
}

String _priceText(Map<String, dynamic> prices, String symbol) {
  final price = prices[symbol];
  if (price is! Map<String, dynamic> || price['idrPerUnit'] is! num) {
    return 'Unavailable';
  }
  return 'Rp ${_formatAmount((price['idrPerUnit'] as num).toDouble())}';
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.entries,
    required this.totalIdr,
    required this.profitIdr,
    required this.profitPercent,
    required this.syncError,
    required this.onDelete,
    required this.onConvert,
  });
  final List<SavingEntry> entries;
  final double totalIdr;
  final double profitIdr;
  final double profitPercent;
  final String? syncError;
  final ValueChanged<SavingEntry> onDelete;
  final VoidCallback onConvert;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 18, 24, 8),
          child: Text(
            'PiggyLog',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: _BalanceIsland(
            totalIdr: totalIdr,
            profitIdr: profitIdr,
            profitPercent: profitPercent,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'History',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const ValueKey('convert-button'),
                tooltip: 'Convert assets',
                onPressed: onConvert,
                icon: const Icon(Icons.currency_exchange),
              ),
            ],
          ),
        ),
        if (syncError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              'Using saved data · $syncError',
              key: const ValueKey('sync-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No savings yet'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: entries.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return GestureDetector(
                      onLongPress: () => onDelete(entry),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          child: Icon(
                            entry.asset == AssetType.gold
                                ? Icons.circle_outlined
                                : Icons.savings_outlined,
                          ),
                        ),
                        title: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.source.isEmpty ? 'Saving' : entry.source,
                            textAlign: TextAlign.left,
                          ),
                        ),
                        subtitle: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${entry.asset.shortCode} · ${_formatDate(entry.date)}',
                            textAlign: TextAlign.left,
                          ),
                        ),
                        trailing: Text(
                          '${entry.asset.symbol}${_formatAmount(entry.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _BalanceIsland extends StatelessWidget {
  const _BalanceIsland({
    required this.totalIdr,
    required this.profitIdr,
    required this.profitPercent,
  });
  final double totalIdr;
  final double profitIdr;
  final double profitPercent;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('balance-island'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
    decoration: BoxDecoration(
      color: const Color(0xffe5eee9),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOTAL SAVINGS',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(letterSpacing: 1.2, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Text(
          'Rp ${_formatAmount(totalIdr)}',
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${profitIdr >= 0 ? '+' : '-'}Rp ${_formatAmount(profitIdr.abs())} profit · ${profitPercent >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(2)}% overall',
          key: const ValueKey('profit-summary'),
          style: TextStyle(
            color: profitIdr >= 0
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PricesPage extends StatelessWidget {
  const _PricesPage({
    required this.prices,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
  });

  final Map<String, dynamic> prices;
  final String? error;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => _SimplePage(
    title: 'Price updates',
    icon: Icons.trending_up,
    children: [
      _PriceTile(label: 'Gold · per gram', value: _priceText(prices, 'gold')),
      _PriceTile(label: 'USD · 1 USD', value: _priceText(prices, 'usd')),
      _PriceTile(label: 'SAR · 1 SAR', value: _priceText(prices, 'sar')),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('refresh-prices-button'),
        onPressed: refreshing ? null : onRefresh,
        icon: refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        label: Text(refreshing ? 'Updating…' : 'Refresh prices'),
      ),
      if (error != null) ...[
        const SizedBox(height: 8),
        Text(
          'Could not load prices: $error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(label),
      trailing: Text(value, style: const TextStyle(color: Colors.black54)),
    ),
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.serverUrl, required this.onLogout});

  final String serverUrl;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => _SimplePage(
    title: 'Settings',
    icon: Icons.tune,
    children: [
      const ListTile(title: Text('Currency display'), trailing: Text('IDR')),
      ListTile(
        title: const Text('Connected server'),
        subtitle: Text(serverUrl),
        leading: const Icon(Icons.dns_outlined),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('logout-button'),
        onPressed: () async {
          final shouldLogout = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Log out?'),
              content: const Text(
                'Your saved session will be removed from this device.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Log out'),
                ),
              ],
            ),
          );
          if (shouldLogout == true) await onLogout();
        },
        icon: const Icon(Icons.logout),
        label: const Text('Log out'),
      ),
    ],
  );
}

class _SimplePage extends StatelessWidget {
  const _SimplePage({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.page,
    required this.onTap,
    required this.onAdd,
  });
  final int page;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary.withOpacity(.14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ClipRRect(
        key: const ValueKey('bottom-navigation'),
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xffedf1ef).withOpacity(.94),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slot = constraints.maxWidth / 3;
                const indicatorWidth = 86.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: slot * page + (slot - indicatorWidth) / 2,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: indicatorWidth,
                          height: 48,
                          decoration: BoxDecoration(
                            color: active,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: IconButton(
                            key: const ValueKey('prices-tab'),
                            onPressed: () => onTap(0),
                            icon: const Icon(Icons.trending_up),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              reverseDuration: const Duration(
                                milliseconds: 180,
                              ),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: .88,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: page == 1
                                  ? SizedBox(
                                      key: const ValueKey('add-tab'),
                                      width: 86,
                                      height: 48,
                                      child: FilledButton(
                                        onPressed: onAdd,
                                        style: FilledButton.styleFrom(
                                          shape: const StadiumBorder(),
                                          padding: EdgeInsets.zero,
                                        ),
                                        child: const Icon(Icons.add),
                                      ),
                                    )
                                  : SizedBox(
                                      key: const ValueKey('home-tab'),
                                      width: 86,
                                      height: 48,
                                      child: IconButton(
                                        onPressed: () => onTap(1),
                                        icon: const Icon(
                                          Icons.account_balance_wallet_outlined,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: IconButton(
                            key: const ValueKey('settings-tab'),
                            onPressed: () => onTap(2),
                            icon: const Icon(Icons.tune),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet();

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  AssetType _fromAsset = AssetType.idr;
  AssetType _toAsset = AssetType.usd;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, Object?>{
      'from_asset': _fromAsset.name,
      'to_asset': _toAsset.name,
      'amount': _parseAmount(_amountController.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xffd2d9d6)),
    );
    final decoration = InputDecoration(
      filled: true,
      fillColor: const Color(0xfff5f7f6),
      border: outline,
      enabledBorder: outline,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Convert assets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<AssetType>(
              key: const ValueKey('convert-from-asset'),
              value: _fromAsset,
              decoration: decoration.copyWith(labelText: 'From'),
              items: AssetType.values
                  .map(
                    (asset) => DropdownMenuItem(
                      value: asset,
                      child: Text(asset.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _fromAsset = value;
                  if (_fromAsset == _toAsset) {
                    _toAsset = AssetType.values.firstWhere(
                      (asset) => asset != value,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('convert-amount-field'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: decoration.copyWith(
                labelText: 'Amount',
                prefixText: _fromAsset.symbol,
              ),
              validator: (value) {
                final raw = (value ?? '').trim();
                final valid = RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(raw);
                if (!valid || _parseAmount(raw) <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AssetType>(
              key: const ValueKey('convert-to-asset'),
              value: _toAsset,
              decoration: decoration.copyWith(labelText: 'To'),
              items: AssetType.values
                  .map(
                    (asset) => DropdownMenuItem(
                      value: asset,
                      child: Text(asset.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _toAsset = value;
                  if (_toAsset == _fromAsset) {
                    _fromAsset = AssetType.values.firstWhere(
                      (asset) => asset != value,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('submit-conversion-button'),
              onPressed: _save,
              child: const Text('Convert'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSavingSheet extends StatefulWidget {
  const _AddSavingSheet();
  @override
  State<_AddSavingSheet> createState() => _AddSavingSheetState();
}

class _AddSavingSheetState extends State<_AddSavingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  AssetType _asset = AssetType.idr;
  bool _goldMode = false;
  bool _today = true;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      SavingEntry(
        asset: _goldMode ? AssetType.gold : _asset,
        amount: _parseAmount(_amountController.text),
        source: _sourceController.text.trim(),
        date: _date,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _date,
    );
    if (picked != null)
      setState(() {
        _date = picked;
        _today = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + inset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add savings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            _CashGoldToggle(
              selectedGold: _goldMode,
              onChanged: (gold) => setState(() => _goldMode = gold),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 370,
              child: _CashFields(
                asset: _goldMode ? AssetType.gold : _asset,
                availableAssets: _goldMode
                    ? const [AssetType.gold]
                    : const [AssetType.idr, AssetType.sar, AssetType.usd],
                today: _today,
                date: _date,
                amountController: _amountController,
                sourceController: _sourceController,
                onAssetChanged: (asset) => setState(() {
                  if (!_goldMode) _asset = asset;
                }),
                onTodayChanged: (today) => setState(() {
                  _today = today;
                  if (today) _date = DateTime.now();
                }),
                onPickDate: _pickDate,
                onSave: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashGoldToggle extends StatelessWidget {
  const _CashGoldToggle({required this.selectedGold, required this.onChanged});
  final bool selectedGold;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      key: const ValueKey('cash-gold-toggle'),
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null || details.primaryVelocity == 0)
          return;
        onChanged(details.primaryVelocity! < 0);
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xfff0f2f1),
          borderRadius: BorderRadius.circular(28),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              AnimatedAlign(
                alignment: selectedGold
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: constraints.maxWidth / 2 - 2,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      label: 'Cash',
                      active: !selectedGold,
                      color: accent,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _ModeButton(
                      label: 'Gold',
                      active: selectedGold,
                      color: accent,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      shape: const StadiumBorder(),
      foregroundColor: active ? color : Colors.black54,
    ),
    child: Text(
      label,
      style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500),
    ),
  );
}

class _CashFields extends StatelessWidget {
  const _CashFields({
    required this.asset,
    required this.availableAssets,
    required this.today,
    required this.date,
    required this.amountController,
    required this.sourceController,
    required this.onAssetChanged,
    required this.onTodayChanged,
    required this.onPickDate,
    required this.onSave,
  });
  final AssetType asset;
  final List<AssetType> availableAssets;
  final bool today;
  final DateTime date;
  final TextEditingController amountController, sourceController;
  final ValueChanged<AssetType> onAssetChanged;
  final ValueChanged<bool> onTodayChanged;
  final VoidCallback onPickDate, onSave;
  @override
  Widget build(BuildContext context) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xffd2d9d6), width: 1),
    );
    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor: const Color(0xfff5f7f6),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<AssetType>(
          value: asset,
          decoration: fieldDecoration.copyWith(labelText: 'Currency'),
          items: availableAssets
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onAssetChanged(value);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: today ? null : onPickDate,
                borderRadius: BorderRadius.circular(18),
                child: InputDecorator(
                  decoration: fieldDecoration.copyWith(
                    labelText: 'Date',
                    fillColor: today
                        ? const Color(0xffe9eceb)
                        : const Color(0xfff3f5f4),
                  ),
                  child: Text(
                    _formatDate(date),
                    style: TextStyle(color: today ? Colors.black45 : null),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxTheme(
                  data: CheckboxThemeData(
                    shape: const CircleBorder(),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: Checkbox(
                    value: today,
                    onChanged: (value) => onTodayChanged(value ?? false),
                  ),
                ),
                const Text('Today', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('amount-field'),
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDecoration.copyWith(
            labelText: 'Amount',
            prefixText: asset.symbol,
          ),
          validator: (value) {
            final raw = (value ?? '').trim();
            final amount = RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(raw)
                ? _parseAmount(raw)
                : double.nan;
            return !amount.isFinite || amount <= 0
                ? 'Enter a valid amount'
                : null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: sourceController,
          decoration: fieldDecoration.copyWith(
            labelText: 'Source (optional)',
            hintText: 'Where did it come from?',
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _formatAmount(double amount) {
  final raw = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = raw.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return parts.length == 1 ? grouped : '$grouped,${parts.last}';
}

double _parseAmount(String value) =>
    double.parse(value.trim().replaceAll('.', '').replaceAll(',', '.'));
String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
