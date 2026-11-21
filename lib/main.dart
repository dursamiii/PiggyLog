// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

void main() => runApp(const PiggyLogApp());

class PiggyLogApp extends StatelessWidget {
  const PiggyLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PiggyLog',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167c68)),
          useMaterial3: true,
        ),
        home: const SavingsPage(),
      );
}

enum AssetType { idr, usd, eur, gold }

extension AssetTypeLabel on AssetType {
  String get label => switch (this) {
        AssetType.idr => 'IDR · Rupiah',
        AssetType.usd => 'USD · US Dollar',
        AssetType.eur => 'EUR · Euro',
        AssetType.gold => 'Gold · Emas',
      };

  String get symbol => switch (this) {
        AssetType.idr => 'Rp',
        AssetType.usd => r'$ ',
        AssetType.eur => '€ ',
        AssetType.gold => 'g ',
      };
}

class SavingEntry {
  const SavingEntry({required this.asset, required this.amount, required this.source, required this.date});

  final AssetType asset;
  final double amount;
  final String source;
  final DateTime date;
}

class SavingsPage extends StatefulWidget {
  const SavingsPage({super.key});

  @override
  State<SavingsPage> createState() => _SavingsPageState();
}

class _SavingsPageState extends State<SavingsPage> {
  final List<SavingEntry> _entries = [];

  double get _totalIdr => _entries.fold(0, (sum, entry) =>
      sum + (entry.asset == AssetType.idr ? entry.amount : 0));

  Future<void> _addSaving() async {
    final entry = await showModalBottomSheet<SavingEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddSavingSheet(),
    );
    if (entry != null) setState(() => _entries.insert(0, entry));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PiggyLog')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TOTAL SAVINGS', style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('Rp ${_formatAmount(_totalIdr)}', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('+0% overall', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('History', style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(onPressed: _addSaving, icon: const Icon(Icons.add), label: const Text('Add savings')),
              ]),
            ),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(child: Text('No savings yet'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _entries.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return ListTile(
                          leading: CircleAvatar(child: Icon(entry.asset == AssetType.gold ? Icons.circle_outlined : Icons.savings_outlined)),
                          title: Text(entry.source),
                          subtitle: Text('${entry.asset.label} · ${_formatDate(entry.date)}'),
                          trailing: Text('${entry.asset.symbol}${_formatAmount(entry.amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSaving, icon: const Icon(Icons.add), label: const Text('Add savings')),
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

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, SavingEntry(
      asset: _asset,
      amount: double.parse(_amountController.text.trim().replaceAll(',', '.')),
      source: _sourceController.text.trim(),
      date: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add savings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          DropdownButtonFormField<AssetType>(
            initialValue: _asset,
            decoration: const InputDecoration(labelText: 'Asset', border: OutlineInputBorder()),
            items: AssetType.values.map((asset) => DropdownMenuItem(
              value: asset, enabled: asset != AssetType.gold,
              child: Text(asset == AssetType.gold ? 'Gold · Coming soon' : asset.label),
            )).toList(),
            onChanged: (asset) { if (asset != null) setState(() => _asset = asset); },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount', prefixText: _asset.symbol, border: const OutlineInputBorder()),
            validator: (value) {
              final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
              if (amount == null || !amount.isFinite || amount <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sourceController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Source', hintText: 'e.g. Salary, gift', border: OutlineInputBorder()),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a source' : null,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ),
    );
  }
}

String _formatAmount(double amount) => amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
