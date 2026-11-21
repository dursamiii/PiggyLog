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
        home: _SessionGate(
          repository: authRepository ?? ServerAuthRepository(),
        ),
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
  const LoginPage({
    required this.repository,
    required this.onLogin,
    super.key,
  });

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
          _error = error is ApiException
              ? error.message
              : 'Tidak dapat menghubungi server. Periksa URL dan koneksi jaringan.';
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        AssetType.idr => 'IDR · Rupiah', AssetType.sar => 'SAR · Riyal',
        AssetType.usd => 'USD · US Dollar', AssetType.gold => 'Gold · Emas',
      };
  String get shortCode => switch (this) {
        AssetType.idr => 'IDR', AssetType.sar => 'SAR',
        AssetType.usd => 'USD', AssetType.gold => 'GOLD',
      };
  String get symbol => switch (this) {
        AssetType.idr => 'Rp ', AssetType.sar => 'SAR ',
        AssetType.usd => r'$ ', AssetType.gold => 'g ',
      };
}

class SavingEntry {
  const SavingEntry({required this.asset, required this.amount, required this.source, required this.date});
  final AssetType asset;
  final double amount;
  final String source;
  final DateTime date;

  Map<String, Object> toJson() => {
        'asset': asset.name,
        'amount': amount,
        'source': source,
        'date': date.toIso8601String(),
      };

  factory SavingEntry.fromJson(Map<String, dynamic> json) => SavingEntry(
        asset: AssetType.values.byName(json['asset'] as String),
        amount: (json['amount'] as num).toDouble(),
        source: json['source'] as String,
        date: DateTime.parse(json['date'] as String),
      );
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

  @override
  void initState() {
    super.initState();
    _restoreEntries();
  }

  Future<void> _restoreEntries() async {
    final cached = await widget.repository.loadEntriesCache(widget.session.serverUrl);
    if (!mounted || cached == null) return;
    try {
      final decoded = jsonDecode(cached) as List<dynamic>;
      final entries = decoded
          .map((item) => SavingEntry.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
      });
    } on FormatException catch (error) {
      debugPrint('Invalid cached savings data: $error');
    } on TypeError catch (error) {
      debugPrint('Invalid cached savings data: $error');
    } on ArgumentError catch (error) {
      debugPrint('Invalid cached savings data: $error');
    }
  }

  Future<void> _saveEntriesCache() async {
    try {
      await widget.repository.saveEntriesCache(
        widget.session.serverUrl,
        jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan cache lokal: $error')),
        );
      }
    }
  }

  void _insertEntry(SavingEntry entry) {
    _entries.add(entry);
    _entries.sort((a, b) => b.date.compareTo(a.date));
    _saveEntriesCache();
  }

  Future<void> _deleteEntry(SavingEntry entry) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saving?'),
        content: const Text('This entry will be removed from history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (delete == true) {
      setState(() => _entries.remove(entry));
      _saveEntriesCache();
    }
  }

  double get _totalIdr => _entries.fold(0, (sum, entry) => sum + (entry.asset == AssetType.idr ? entry.amount : 0));

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
      builder: (_) => const _AddSavingSheet());
    if (entry != null) setState(() => _insertEntry(entry));
  }

  void _go(int page) {
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfff7f8f7),
        body: Stack(children: [
          PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              const _PricesPage(),
              _HomePage(entries: _entries, totalIdr: _totalIdr, onDelete: _deleteEntry),
              _SettingsPage(serverUrl: widget.session.serverUrl, onLogout: widget.onLogout),
            ],
          ),
          Align(alignment: Alignment.bottomCenter, child: _BottomNav(page: _page, onTap: _go, onAdd: _addSaving)),
        ]),
      );
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.entries, required this.totalIdr, required this.onDelete});
  final List<SavingEntry> entries;
  final double totalIdr;
  final ValueChanged<SavingEntry> onDelete;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(24, 18, 24, 8), child: Text('PiggyLog', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), child: _BalanceIsland(totalIdr: totalIdr)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('History', style: Theme.of(context).textTheme.titleLarge)),
          Expanded(child: entries.isEmpty ? const Center(child: Text('No savings yet')) : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120), itemCount: entries.length,
            separatorBuilder: (_, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return GestureDetector(
                onLongPress: () => onDelete(entry),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: CircleAvatar(child: Icon(entry.asset == AssetType.gold ? Icons.circle_outlined : Icons.savings_outlined)),
                  title: Align(alignment: Alignment.centerLeft, child: Text(entry.source.isEmpty ? 'Saving' : entry.source, textAlign: TextAlign.left)),
                  subtitle: Align(alignment: Alignment.centerLeft, child: Text('${entry.asset.shortCode} · ${_formatDate(entry.date)}', textAlign: TextAlign.left)),
                  trailing: Text('${entry.asset.symbol}${_formatAmount(entry.amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              );
            },
          )),
        ]),
      );
}

class _BalanceIsland extends StatelessWidget {
  const _BalanceIsland({required this.totalIdr});
  final double totalIdr;
  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('balance-island'),
        width: double.infinity, padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
        decoration: BoxDecoration(color: const Color(0xffe5eee9), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white, width: 1.5), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, 8))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTAL SAVINGS', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.2, color: Colors.black54)),
          const SizedBox(height: 8), Text('Rp ${_formatAmount(totalIdr)}', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8), Text('+0% overall', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _PricesPage extends StatelessWidget {
  const _PricesPage();
  @override
  Widget build(BuildContext context) => const _SimplePage(title: 'Price updates', icon: Icons.trending_up, children: [
        _PriceTile(label: 'Gold', value: 'Coming soon'), _PriceTile(label: 'USD', value: 'Coming soon'), _PriceTile(label: 'SAR', value: 'Coming soon'),
      ]);
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(title: Text(label), trailing: Text(value, style: const TextStyle(color: Colors.black54))));
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
          const ListTile(
            title: Text('Currency display'),
            trailing: Text('IDR'),
          ),
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
                  content: const Text('Your saved session will be removed from this device.'),
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
  const _SimplePage({required this.title, required this.icon, required this.children});
  final String title; final IconData icon; final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 22, 24, 110), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(icon), const SizedBox(width: 12), Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))]),
    const SizedBox(height: 24), ...children])));
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.page, required this.onTap, required this.onAdd});
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
              boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 22, offset: Offset(0, 8))],
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              final slot = constraints.maxWidth / 3;
              const indicatorWidth = 86.0;
              return Stack(alignment: Alignment.center, children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: slot * page + (slot - indicatorWidth) / 2,
                  child: IgnorePointer(child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: indicatorWidth,
                    height: 48,
                    decoration: BoxDecoration(color: active, borderRadius: BorderRadius.circular(24)),
                  )),
                ),
                Row(children: [
                  Expanded(child: IconButton(key: const ValueKey('prices-tab'), onPressed: () => onTap(0), icon: const Icon(Icons.trending_up))),
                  Expanded(child: Center(child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    reverseDuration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: Tween<double>(begin: .88, end: 1).animate(animation), child: child),
                    ),
                    child: page == 1
                        ? SizedBox(key: const ValueKey('add-tab'), width: 86, height: 48, child: FilledButton(
                            onPressed: onAdd,
                            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: EdgeInsets.zero),
                            child: const Icon(Icons.add),
                          ))
                        : SizedBox(key: const ValueKey('home-tab'), width: 86, height: 48, child: IconButton(
                            onPressed: () => onTap(1), icon: const Icon(Icons.account_balance_wallet_outlined),
                          )),
                  ))),
                  Expanded(child: IconButton(key: const ValueKey('settings-tab'), onPressed: () => onTap(2), icon: const Icon(Icons.tune))),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _AddSavingSheet extends StatefulWidget {
  const _AddSavingSheet();
  @override State<_AddSavingSheet> createState() => _AddSavingSheetState();
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
  void dispose() { _amountController.dispose(); _sourceController.dispose(); super.dispose(); }

  void _save() {
    if (_goldMode || !_formKey.currentState!.validate()) return;
    Navigator.pop(context, SavingEntry(asset: _asset, amount: _parseAmount(_amountController.text), source: _sourceController.text.trim(), date: _date));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDate: _date);
    if (picked != null) setState(() { _date = picked; _today = false; });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + inset),
      child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Add savings', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 18),
      _CashGoldToggle(selectedGold: _goldMode, onChanged: (gold) => setState(() => _goldMode = gold)),
      const SizedBox(height: 18),
      SizedBox(height: 370, child: _goldMode ? const _GoldPlaceholder() : _CashFields(
        asset: _asset,
        today: _today,
        date: _date,
        amountController: _amountController,
        sourceController: _sourceController,
        onAssetChanged: (asset) => setState(() => _asset = asset),
        onTodayChanged: (today) => setState(() { _today = today; if (today) _date = DateTime.now(); }),
        onPickDate: _pickDate,
        onSave: _save,
      )),
    ])));
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
        if (details.primaryVelocity == null || details.primaryVelocity == 0) return;
        onChanged(details.primaryVelocity! < 0);
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xfff0f2f1), borderRadius: BorderRadius.circular(28)),
        child: LayoutBuilder(builder: (context, constraints) => Stack(children: [
          AnimatedAlign(
            alignment: selectedGold ? Alignment.centerRight : Alignment.centerLeft,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Container(width: constraints.maxWidth / 2 - 2, height: 48,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 2))])),
          ),
          Row(children: [
            Expanded(child: _ModeButton(label: 'Cash', active: !selectedGold, color: accent, onTap: () => onChanged(false))),
            Expanded(child: _ModeButton(label: 'Gold', active: selectedGold, color: accent, onTap: () => onChanged(true))),
          ]),
        ])),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.active, required this.color, required this.onTap});
  final String label; final bool active; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(onPressed: onTap,
    style: TextButton.styleFrom(shape: const StadiumBorder(), foregroundColor: active ? color : Colors.black54),
    child: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500)));
}

class _GoldPlaceholder extends StatelessWidget {
  const _GoldPlaceholder();
  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.auto_awesome, size: 38, color: Colors.black38), SizedBox(height: 10),
    Text('Gold savings coming soon'),
    Text('Price updates will be connected later.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
  ]));
}

class _CashFields extends StatelessWidget {
  const _CashFields({required this.asset, required this.today, required this.date,
    required this.amountController, required this.sourceController, required this.onAssetChanged,
    required this.onTodayChanged, required this.onPickDate, required this.onSave});
  final AssetType asset; final bool today; final DateTime date;
  final TextEditingController amountController, sourceController;
  final ValueChanged<AssetType> onAssetChanged; final ValueChanged<bool> onTodayChanged;
  final VoidCallback onPickDate, onSave;
  @override
  Widget build(BuildContext context) {
    final outline = OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xffd2d9d6), width: 1));
    final fieldDecoration = InputDecoration(filled: true, fillColor: const Color(0xfff5f7f6), border: outline, enabledBorder: outline, focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.6)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<AssetType>(value: asset, decoration: fieldDecoration.copyWith(labelText: 'Currency'), items: const [AssetType.idr, AssetType.sar, AssetType.usd].map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(), onChanged: (value) { if (value != null) onAssetChanged(value); }),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: InkWell(onTap: today ? null : onPickDate, borderRadius: BorderRadius.circular(18), child: InputDecorator(
          decoration: fieldDecoration.copyWith(labelText: 'Date', fillColor: today ? const Color(0xffe9eceb) : const Color(0xfff3f5f4)),
          child: Text(_formatDate(date), style: TextStyle(color: today ? Colors.black45 : null)),
        ))),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, children: [
          CheckboxTheme(data: CheckboxThemeData(shape: const CircleBorder(), side: BorderSide(color: Theme.of(context).colorScheme.primary)), child: Checkbox(value: today, onChanged: (value) => onTodayChanged(value ?? false))),
          const Text('Today', style: TextStyle(fontSize: 12)),
        ]),
      ]),
      const SizedBox(height: 12),
      TextFormField(key: const ValueKey('amount-field'), controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration.copyWith(labelText: 'Amount', prefixText: asset.symbol), validator: (value) { final raw = (value ?? '').trim(); final amount = RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(raw) ? _parseAmount(raw) : double.nan; return !amount.isFinite || amount <= 0 ? 'Enter a valid amount' : null; }),
      const SizedBox(height: 12),
      TextFormField(controller: sourceController, decoration: fieldDecoration.copyWith(labelText: 'Source (optional)', hintText: 'Where did it come from?')),
      const Spacer(),
      FilledButton(onPressed: onSave, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()), child: const Text('Save')),
    ]);
  }
}

String _formatAmount(double amount) {
  final raw = amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  final parts = raw.split('.');
  final grouped = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return parts.length == 1 ? grouped : '$grouped,${parts.last}';
}

double _parseAmount(String value) => double.parse(value.trim().replaceAll('.', '').replaceAll(',', '.'));
String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
