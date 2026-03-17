import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';
import 'add_listing_screen.dart';

class SellerListingsScreen extends StatefulWidget {
  const SellerListingsScreen({super.key});

  @override
  State<SellerListingsScreen> createState() => _SellerListingsScreenState();
}

enum _SortBy {
  highestValue,
  highestProfit,
  latestUpdated,
  mostDemanded,
}

enum _FraudFilter {
  all,
  low,
  high,
}

class _SellerListingsScreenState extends State<SellerListingsScreen> {
  static const Color _gold = AppColors.accentGold;
  static const Color _darkGreenStart = AppColors.background;
  static const Color _card = AppColors.cardSurface;
  static const Color _cardAlt = AppColors.cardSurface;

  final MarketplaceService _marketplaceService = MarketplaceService();
  final NumberFormat _money = NumberFormat('#,##0.##', 'en_US');
  final NumberFormat _compact = NumberFormat.compact(locale: 'en_US');

  final TextEditingController _calcRateCtrl = TextEditingController();
  final TextEditingController _calcQtyCtrl = TextEditingController();
  String _calcUnit = 'kg';
  bool _calcExpanded = false;

  List<StockItem> _cachedItems = <StockItem>[];
  DateTime? _cachedAt;
  DateTime? _lastRefreshedAt;

  String? _productFilter;
  String? _districtFilter;
  String? _statusFilter;
  bool _verifiedOnly = false;
  _FraudFilter _fraudFilter = _FraudFilter.all;
  _SortBy _sortBy = _SortBy.latestUpdated;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _calcRateCtrl.dispose();
    _calcQtyCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _rawStockStream() {
    if (_uid.isEmpty) {
      return FirebaseFirestore.instance
          .collection('stocks')
          .where('sellerId', isEqualTo: '__none__')
          .snapshots();
    }

    try {
      return _marketplaceService.getSellerListingsStream(_uid);
    } catch (_) {
      return FirebaseFirestore.instance
          .collection('stocks')
          .where('sellerId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .snapshots();
    }
  }

  Future<void> _manualRefresh() async {
    if (_uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .where('sellerId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(150)
          .get();
    } catch (_) {
      await FirebaseFirestore.instance
          .collection('stocks')
          .where('sellerId', isEqualTo: _uid)
          .limit(150)
          .get();
    }
    if (!mounted) return;
    setState(() {
      _lastRefreshedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkGreenStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Mera Maal (My Stock) / میرا مال',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _manualRefresh,
            icon: const Icon(Icons.refresh_rounded, color: _gold),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _SellerBackground()),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _rawStockStream(),
            builder: (context, snapshot) {
              final state = snapshot.connectionState;
              if (state == ConnectionState.waiting && _cachedItems.isEmpty) {
                return const _LoadingSkeleton();
              }

              if (snapshot.hasError) {
                if (_cachedItems.isNotEmpty) {
                  return _buildContent(
                    allItems: _cachedItems,
                    showOfflineBanner: true,
                    errorText: 'Offline mode / آف لائن: cached data shown',
                  );
                }
                return _ErrorState(onRetry: _manualRefresh);
              }

              final docs = snapshot.data?.docs ?? const [];
              final items = docs.map(StockItem.fromDoc).toList(growable: false);
              if (items.isNotEmpty) {
                _cachedItems = items;
                _cachedAt = DateTime.now();
              }

              final sourceItems = items.isNotEmpty ? items : _cachedItems;
              if (sourceItems.isEmpty) {
                return _EmptyState(onAddStock: _onTapAddStock);
              }

              return _buildContent(
                allItems: sourceItems,
                showOfflineBanner: items.isEmpty && _cachedItems.isNotEmpty,
                errorText: items.isEmpty && _cachedItems.isNotEmpty
                    ? 'Showing last cached values / آخری محفوظ ڈیٹا'
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required List<StockItem> allItems,
    required bool showOfflineBanner,
    String? errorText,
  }) {
    final filtered = _applyFilters(allItems);
    final sorted = _sortItems(filtered);
    final summary = StockSummary.fromItems(sorted);
    final hasDemandData = allItems.any((e) => e.demandScore > 0);
    final availableProducts = _uniqueNonEmpty(allItems.map((e) => e.productName));
    final availableDistricts = _uniqueNonEmpty(allItems.map((e) => e.district));
    final availableStatuses = _uniqueNonEmpty(allItems.map((e) => e.status));

    return RefreshIndicator(
      color: _gold,
      onRefresh: _manualRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          if (showOfflineBanner)
            _OfflineBanner(
              text: errorText ?? 'Offline mode',
              cachedAt: _cachedAt,
              refreshedAt: _lastRefreshedAt,
            ),
          _SummaryCard(summary: summary),
          const SizedBox(height: 10),
          _buildInsightsStrip(summary),
          const SizedBox(height: 10),
          _buildFilterRow(),
          const SizedBox(height: 8),
          _buildAppliedFiltersChips(),
          const SizedBox(height: 12),
          _CalculatorPanel(
            isExpanded: _calcExpanded,
            rateController: _calcRateCtrl,
            qtyController: _calcQtyCtrl,
            selectedUnit: _calcUnit,
            marketRate: summary.averageMarketRate,
            onExpandedChanged: (v) => setState(() => _calcExpanded = v),
            onUnitChanged: (u) => setState(() => _calcUnit = u),
            moneyFormatter: _money,
          ),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            _NoFilteredResults(onClear: _clearFilters)
          else
            ...sorted.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StockItemCard(
                  item: item,
                  money: _money,
                  compact: _compact,
                  onReverify: () => _onReverify(item),
                  onMenuSelected: (action) => _onMenuAction(action, item),
                  runFraudChecks: runFraudChecks,
                ),
              ),
            ),
          const SizedBox(height: 8),
          _TrustSection(
            items: sorted,
            onRecordVideo: () => _onTapAddStock(reverifyOnly: true),
            onUpdateGps: () => _onTapAddStock(reverifyOnly: true),
          ),
          const SizedBox(height: 24),
          _buildSortHint(hasDemandData),
          const SizedBox(height: 24),
          _buildFooterNote(
            hasDemandData: hasDemandData,
            products: availableProducts,
            districts: availableDistricts,
            statuses: availableStatuses,
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsStrip(StockSummary summary) {
    final up = summary.profitLoss >= 0;
    final icon = up ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final color = up ? const Color(0xFF8BE28B) : const Color(0xFFFF8A8A);
    return Container(
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              up
                  ? 'Insights: Market is favorable / منڈی بہتر ہے'
                  : 'Insights: Review rates / ریٹ چیک کریں',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${summary.profitPercent >= 0 ? '+' : ''}${summary.profitPercent.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickChip(
                label: 'Verified Only / صرف تصدیق شدہ',
                selected: _verifiedOnly,
                onTap: () => setState(() => _verifiedOnly = !_verifiedOnly),
              ),
              _quickChip(
                label: 'High Risk / زیادہ رسک',
                selected: _fraudFilter == _FraudFilter.high,
                onTap: () {
                  setState(() {
                    _fraudFilter = _fraudFilter == _FraudFilter.high
                        ? _FraudFilter.all
                        : _FraudFilter.high;
                  });
                },
              ),
              _quickChip(
                label: 'Low Risk / کم رسک',
                selected: _fraudFilter == _FraudFilter.low,
                onTap: () {
                  setState(() {
                    _fraudFilter = _fraudFilter == _FraudFilter.low
                        ? _FraudFilter.all
                        : _FraudFilter.low;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _gold,
            side: BorderSide(color: _gold.withValues(alpha: 0.55)),
          ),
          onPressed: _openFilterSortSheet,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Filter'),
        ),
      ],
    );
  }

  Widget _quickChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _gold.withValues(alpha: 0.2),
      checkmarkColor: _gold,
      labelStyle: TextStyle(
        color: selected ? _gold : Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: selected ? _gold : AppColors.divider),
      backgroundColor: _card.withValues(alpha: 0.85),
      label: Text(label),
    );
  }

  Widget _buildAppliedFiltersChips() {
    final chips = <Widget>[];
    if (_productFilter != null) {
      chips.add(_removableChip('Product: $_productFilter', () {
        setState(() => _productFilter = null);
      }));
    }
    if (_districtFilter != null) {
      chips.add(_removableChip('District: $_districtFilter', () {
        setState(() => _districtFilter = null);
      }));
    }
    if (_statusFilter != null) {
      chips.add(_removableChip('Status: $_statusFilter', () {
        setState(() => _statusFilter = null);
      }));
    }
    if (!_verifiedOnly && _fraudFilter == _FraudFilter.all && chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _removableChip(String label, VoidCallback onRemove) {
    return Chip(
      backgroundColor: _gold.withValues(alpha: 0.18),
      side: BorderSide(color: _gold.withValues(alpha: 0.5)),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      deleteIconColor: Colors.white,
      onDeleted: onRemove,
    );
  }

  Widget _buildSortHint(bool hasDemandData) {
    final text = _sortLabel(_sortBy);
    return Text(
      hasDemandData
          ? 'Sort: $text'
          : 'Sort: $text (Most demanded hidden - no data)',
      style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
    );
  }

  Widget _buildFooterNote({
    required bool hasDemandData,
    required List<String> products,
    required List<String> districts,
    required List<String> statuses,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.30)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Filters / اسمارٹ فلٹر',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Products: ${products.isEmpty ? '--' : products.take(4).join(', ')}',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          Text(
            'Districts: ${districts.isEmpty ? '--' : districts.take(4).join(', ')}',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          Text(
            'Statuses: ${statuses.isEmpty ? '--' : statuses.join(', ')}',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          if (!hasDemandData)
            const Text(
              'Most demanded sorting will auto-enable when demand metric arrives.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    );
  }

  void _openFilterSortSheet() {
    final products = _uniqueNonEmpty(_cachedItems.map((e) => e.productName));
    final districts = _uniqueNonEmpty(_cachedItems.map((e) => e.district));
    final statuses = _uniqueNonEmpty(_cachedItems.map((e) => e.status));
    final hasDemand = _cachedItems.any((e) => e.demandScore > 0);

    String? draftProduct = _productFilter;
    String? draftDistrict = _districtFilter;
    String? draftStatus = _statusFilter;
    bool draftVerified = _verifiedOnly;
    _FraudFilter draftFraud = _fraudFilter;
    _SortBy draftSort = _sortBy;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(
                        child: Text(
                          'Filters & Sorting / فلٹرز',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sheetLabel('Product / جنس'),
                      _sheetDropdown(
                        value: draftProduct,
                        values: products,
                        onChanged: (v) => setSheet(() => draftProduct = v),
                      ),
                      const SizedBox(height: 10),
                      _sheetLabel('District / ضلع'),
                      _sheetDropdown(
                        value: draftDistrict,
                        values: districts,
                        onChanged: (v) => setSheet(() => draftDistrict = v),
                      ),
                      const SizedBox(height: 10),
                      _sheetLabel('Status / حالت'),
                      _sheetDropdown(
                        value: draftStatus,
                        values: statuses,
                        onChanged: (v) => setSheet(() => draftStatus = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: draftVerified,
                        activeThumbColor: _gold,
                        title: const Text(
                          'Verified only / صرف تصدیق شدہ',
                          style: TextStyle(color: Colors.white),
                        ),
                        onChanged: (v) => setSheet(() => draftVerified = v),
                      ),
                      const SizedBox(height: 6),
                      _sheetLabel('Fraud Risk / رسک'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _riskChoice('All', _FraudFilter.all, draftFraud,
                              (v) => setSheet(() => draftFraud = v)),
                          _riskChoice('Low', _FraudFilter.low, draftFraud,
                              (v) => setSheet(() => draftFraud = v)),
                          _riskChoice('High', _FraudFilter.high, draftFraud,
                              (v) => setSheet(() => draftFraud = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _sheetLabel('Sort by / ترتیب'),
                      ..._sortTiles(hasDemand, draftSort, (value) {
                        setSheet(() => draftSort = value);
                      }),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white30),
                              ),
                              onPressed: () {
                                setSheet(() {
                                  draftProduct = null;
                                  draftDistrict = null;
                                  draftStatus = null;
                                  draftVerified = false;
                                  draftFraud = _FraudFilter.all;
                                  draftSort = _SortBy.latestUpdated;
                                });
                              },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: _darkGreenStart,
                              ),
                              onPressed: () {
                                setState(() {
                                  _productFilter = draftProduct;
                                  _districtFilter = draftDistrict;
                                  _statusFilter = draftStatus;
                                  _verifiedOnly = draftVerified;
                                  _fraudFilter = draftFraud;
                                  _sortBy = draftSort;
                                });
                                Navigator.pop(ctx);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetLabel(String text) {
    return Text(
      text,
      style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
    );
  }

  Widget _sheetDropdown({
    required String? value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        hintText: values.isEmpty ? 'No options' : 'Select',
        filled: true,
        fillColor: _card.withValues(alpha: 0.8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.35)),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dropdownColor: _cardAlt,
      iconEnabledColor: _gold,
      style: const TextStyle(color: Colors.white),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...values.map(
          (v) => DropdownMenuItem<String>(value: v, child: Text(v)),
        ),
      ],
      onChanged: onChanged,
    );
  }

  ChoiceChip _riskChoice(
    String label,
    _FraudFilter value,
    _FraudFilter group,
    ValueChanged<_FraudFilter> onChanged,
  ) {
    final selected = value == group;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _gold.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: selected ? _gold : Colors.white),
      side: BorderSide(color: selected ? _gold : Colors.white30),
      onSelected: (_) => onChanged(value),
    );
  }

  List<Widget> _sortTiles(
    bool hasDemand,
    _SortBy selected,
    ValueChanged<_SortBy> onChanged,
  ) {
    final values = <_SortBy>[
      _SortBy.highestValue,
      _SortBy.highestProfit,
      _SortBy.latestUpdated,
      if (hasDemand) _SortBy.mostDemanded,
    ];

    return values
        .map(
          (s) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: () => onChanged(s),
            leading: Icon(
              s == selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: s == selected ? _gold : Colors.white54,
            ),
            title: Text(
              _sortLabel(s),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        )
        .toList(growable: false);
  }

  String _sortLabel(_SortBy value) {
    switch (value) {
      case _SortBy.highestValue:
        return 'Highest value';
      case _SortBy.highestProfit:
        return 'Highest profit';
      case _SortBy.latestUpdated:
        return 'Latest updated';
      case _SortBy.mostDemanded:
        return 'Most demanded';
    }
  }

  List<StockItem> _applyFilters(List<StockItem> source) {
    return source.where((item) {
      if (_productFilter != null && item.productName != _productFilter) {
        return false;
      }
      if (_districtFilter != null && item.district != _districtFilter) {
        return false;
      }
      if (_statusFilter != null && item.status != _statusFilter) {
        return false;
      }
      if (_verifiedOnly && !(item.videoVerified && item.gpsVerified)) {
        return false;
      }
      if (_fraudFilter == _FraudFilter.high && item.fraudScore < 0.7) {
        return false;
      }
      if (_fraudFilter == _FraudFilter.low && item.fraudScore >= 0.7) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<StockItem> _sortItems(List<StockItem> source) {
    final list = List<StockItem>.from(source);
    switch (_sortBy) {
      case _SortBy.highestValue:
        list.sort((a, b) => b.totalValue.compareTo(a.totalValue));
        break;
      case _SortBy.highestProfit:
        list.sort((a, b) => b.profitLoss.compareTo(a.profitLoss));
        break;
      case _SortBy.latestUpdated:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortBy.mostDemanded:
        list.sort((a, b) => b.demandScore.compareTo(a.demandScore));
        break;
    }
    return list;
  }

  List<String> _uniqueNonEmpty(Iterable<String> values) {
    final set = <String>{};
    for (final v in values) {
      final value = v.trim();
      if (value.isNotEmpty) set.add(value);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _clearFilters() {
    setState(() {
      _productFilter = null;
      _districtFilter = null;
      _statusFilter = null;
      _verifiedOnly = false;
      _fraudFilter = _FraudFilter.all;
      _sortBy = _SortBy.latestUpdated;
    });
  }

  Future<void> _onTapAddStock({bool reverifyOnly = false}) async {
    final userData = await _resolveUserData();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddListingScreen(
          userData: {
            ...userData,
            if (reverifyOnly) 'reverifyMode': true,
          },
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _resolveUserData() async {
    if (_uid.isEmpty) return <String, dynamic>{};
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      return snap.data() ?? <String, dynamic>{'uid': _uid};
    } catch (_) {
      return <String, dynamic>{'uid': _uid};
    }
  }

  Future<void> _onMenuAction(String action, StockItem item) async {
    switch (action) {
      case 'bump_listing':
        await _onBumpListing(item);
        break;
      case 'sell_now':
        await _onSellNow(item);
        break;
      case 'edit_stock':
        await _onEditStock(item);
        break;
      case 'split_lot':
        await _onSplitLot(item);
        break;
      case 'view_details':
        _onViewDetails(item);
        break;
      default:
        break;
    }
  }

  Future<void> _onBumpListing(StockItem item) async {
    try {
      await FirebaseFirestore.instance.collection('listings').doc(item.id).set({
        'bumpedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing bumped to top / لسٹنگ اوپر کر دی گئی')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not bump listing right now')),
      );
    }
  }

  Future<void> _onSellNow(StockItem item) async {
    final userData = await _resolveUserData();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddListingScreen(
          userData: {
            ...userData,
            'prefillListing': {
              'product': item.productName,
              'quantity': item.quantity,
              'unit': item.unit,
              'price': item.rate,
              'province': item.province,
              'district': item.district,
            },
          },
        ),
      ),
    );
  }

  Future<void> _onEditStock(StockItem item) async {
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final rateCtrl = TextEditingController(text: item.rate.toString());

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Stock / اسٹاک ترمیم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity / مقدار'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Rate / ریٹ'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (shouldSave != true) return;

    final quantity = double.tryParse(qtyCtrl.text.trim()) ?? item.quantity;
    final rate = double.tryParse(rateCtrl.text.trim()) ?? item.rate;

    try {
      await FirebaseFirestore.instance.collection('listings').doc(item.id).set({
        'quantity': quantity,
        'price': rate,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock updated successfully')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed, please retry')),
      );
    }
  }

  Future<void> _onSplitLot(StockItem item) async {
    final splitCtrl = TextEditingController();
    final splitQty = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: _cardAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Split Lot / حصہ کریں',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: splitCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Split quantity',
                  labelStyle: const TextStyle(color: AppColors.secondaryText),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.4)),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _darkGreenStart,
                  ),
                  onPressed: () {
                    final value = double.tryParse(splitCtrl.text.trim());
                    if (value == null || value <= 0 || value >= item.quantity) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter valid split quantity')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, value);
                  },
                  child: const Text('Split'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (splitQty == null) return;

    final remaining = item.quantity - splitQty;
    try {
      final col = FirebaseFirestore.instance.collection('listings');
      await col.doc(item.id).set({
        'quantity': remaining,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await col.add({
        'sellerId': _uid,
        'product': item.productName,
        'mandiType': item.mandiType,
        'province': item.province,
        'district': item.district,
        'quantity': splitQty,
        'unit': item.unit,
        'price': item.rate,
        'marketRate': item.marketRate,
        'status': 'active',
        'paymentStatus': item.paymentStatus,
        'videoVerified': item.videoVerified,
        'gpsVerified': item.gpsVerified,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lot split successfully')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split failed, please retry')),
      );
    }
  }

  void _onViewDetails(StockItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.productName} details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('ID', item.id),
              _detailLine('Location', '${item.district}, ${item.province}'),
              _detailLine('Qty', '${item.quantity} ${item.unit}'),
              _detailLine('Rate', 'Rs. ${_money.format(item.rate)}'),
              _detailLine('Market', 'Rs. ${_money.format(item.marketRate)}'),
              _detailLine('Status', item.status),
              _detailLine(
                'Deal Status / سودے کی حالت',
                _phase1DealStatusLabel(item.paymentStatus),
              ),
              _detailLine('Created', DateFormat('dd MMM yyyy, hh:mm a').format(item.createdAt)),
              if (item.flags.isNotEmpty) _detailLine('Flags', item.flags.join(', ')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label: $value'),
    );
  }

  String _phase1DealStatusLabel(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'accepted' || normalized == 'bid_accepted') {
      return 'Accepted / قبول شدہ';
    }
    if (normalized == 'contact_unlocked' || normalized == 'unlocked') {
      return 'Contact Unlocked / رابطہ اَن لاک';
    }
    if (normalized == 'released' ||
        normalized == 'completed' ||
        normalized == 'paid' ||
        normalized == 'success') {
      return 'Offline Deal / براہِ راست سودا';
    }
    return 'Deal Status / سودے کی حالت';
  }

  Future<void> _onReverify(StockItem item) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Re-verify requested for ${item.productName}')),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final StockSummary summary;

  @override
  Widget build(BuildContext context) {
    final isPositive = summary.profitLoss >= 0;
    final color = isPositive ? const Color(0xFF8BE28B) : const Color(0xFFFF8A8A);
    final timeLabel = DateFormat('dd MMM yyyy, hh:mm a').format(summary.lastUpdated);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2A18), Color(0xFF153F28)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _SellerListingsScreenState._gold.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Portfolio Summary / خلاصہ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              _VerificationBadge(verified: summary.overallVerified),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            runSpacing: 10,
            spacing: 10,
            children: [
              _summaryStat('Total Stock Value', 'Rs. ${summary.money(summary.totalValue)}'),
              _summaryStat('Total Quantity', summary.quantityLabel),
              _summaryStat('Average Rate', 'Rs. ${summary.money(summary.averageRate)}'),
              _summaryStat('Current Market Value', 'Rs. ${summary.money(summary.marketValue)}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profit/Loss (Unrealized)',
                        style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${summary.profitLoss >= 0 ? '+' : '-'}Rs. ${summary.money(summary.profitLoss.abs())}',
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        '${summary.profitPercent >= 0 ? '+' : ''}${summary.profitPercent.toStringAsFixed(2)}%',
                        style: TextStyle(color: color, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: $timeLabel',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String title, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: verified ? const Color(0xFF2E7D32) : const Color(0xFF6D4C41),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        verified ? 'Verified ✅' : 'Needs Verify',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.money,
    required this.compact,
    required this.onReverify,
    required this.onMenuSelected,
    required this.runFraudChecks,
  });

  final StockItem item;
  final NumberFormat money;
  final NumberFormat compact;
  final VoidCallback onReverify;
  final ValueChanged<String> onMenuSelected;
  final List<String> Function(StockItem) runFraudChecks;

  String _phase1DealStatusLabel(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'accepted' || normalized == 'bid_accepted') {
      return 'Accepted / قبول شدہ';
    }
    if (normalized == 'contact_unlocked' || normalized == 'unlocked') {
      return 'Contact Unlocked / رابطہ اَن لاک';
    }
    if (normalized == 'released' ||
        normalized == 'completed' ||
        normalized == 'paid' ||
        normalized == 'success') {
      return 'Offline Deal / براہِ راست سودا';
    }
    return 'Deal Status / سودے کی حالت';
  }

  @override
  Widget build(BuildContext context) {
    final highRisk = item.fraudScore >= 0.7;
    final calcFlags = runFraudChecks(item);
    final mergedFlags = <String>{...item.flags, ...calcFlags}.toList(growable: false);
    final verificationMissing = !item.videoVerified || !item.gpsVerified;
    final profitPositive = item.profitLoss >= 0;
    final profitColor = profitPositive ? const Color(0xFF8BE28B) : const Color(0xFFFF8A8A);
    String fmt(DateTime? dt) {
      if (dt == null) return '--';
      return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
    }

    return Container(
      decoration: BoxDecoration(
        color: _SellerListingsScreenState._card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _SellerListingsScreenState._gold.withValues(alpha: 0.32)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _categoryIcon(item.mandiType),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(item.mandiType, _SellerListingsScreenState._gold),
                        _chip('${item.district}, ${item.province}', AppColors.secondaryText),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: const Color(0xFF20472F),
                iconColor: Colors.white,
                onSelected: onMenuSelected,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'bump_listing', child: Text('Bump Listing / اوپر کریں')),
                  PopupMenuItem(value: 'sell_now', child: Text('Add Listing / Sell Now')),
                  PopupMenuItem(value: 'edit_stock', child: Text('Edit Stock')),
                  PopupMenuItem(value: 'split_lot', child: Text('Split Lot')),
                  PopupMenuItem(value: 'view_details', child: Text('View Details')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Quantity: ${_qtyLabel(item.quantity, item.unit)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          if (_convertedQty(item.quantity, item.unit).isNotEmpty)
            Text(
              _convertedQty(item.quantity, item.unit),
              style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _valueBox(
                  'Your Rate / آپ کا ریٹ',
                  'Rs. ${money.format(item.rate)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _valueBox(
                  'Market Rate / مارکیٹ ریٹ',
                  'Rs. ${money.format(item.marketRate)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _valueBox(
                  'Your Total',
                  'Rs. ${money.format(item.totalValue)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _valueBox(
                  'Market Total',
                  'Rs. ${money.format(item.marketValue)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'P/L: ${item.profitLoss >= 0 ? '+' : '-'}Rs. ${money.format(item.profitLoss.abs())}',
                    style: TextStyle(color: profitColor, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${item.profitPercent >= 0 ? '+' : ''}${item.profitPercent.toStringAsFixed(2)}%',
                  style: TextStyle(color: profitColor, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                'Deal Status: ${_phase1DealStatusLabel(item.paymentStatus)}',
                const Color(0xFF81C784),
              ),
              _chip('Status: ${item.status}', const Color(0xFFFFB74D)),
              _chip(item.videoVerified ? 'Video ✅' : 'Video ❌', AppColors.secondaryText),
              _chip(item.gpsVerified ? 'GPS ✅' : 'GPS ❌', AppColors.secondaryText),
              _chip('Images: ${item.imagesCount}', AppColors.secondaryText),
              if (item.promotionType != 'none')
                _chip('Promotion: ${item.promotionType}', const Color(0xFF80CBC4)),
              if (item.promotionType != 'none')
                _chip('Promo Status: ${item.promotionStatus}', const Color(0xFF90CAF9)),
              if (item.promotionType != 'none')
                _chip('Promo Amount: Rs ${money.format(item.featuredCost)}', const Color(0xFFFFF59D)),
              if (item.promotionType != 'none')
                _chip('Requested: ${fmt(item.promotionRequestedAt)}', AppColors.secondaryText),
              if (item.promotionApprovedAt != null)
                _chip('Approved: ${fmt(item.promotionApprovedAt)}', const Color(0xFFA5D6A7)),
              if (item.promotionActivatedAt != null)
                _chip('Active Since: ${fmt(item.promotionActivatedAt)}', const Color(0xFF81D4FA)),
              if (item.promotionExpiresAt != null)
                _chip('Expires: ${fmt(item.promotionExpiresAt)}', const Color(0xFFFFCC80)),
            ],
          ),
          if (item.promotionStatus == 'active') ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _SellerListingsScreenState._gold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _SellerListingsScreenState._gold.withValues(alpha: 0.40),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: _SellerListingsScreenState._gold,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Featured listings get higher visibility on the home page.',
                      style: TextStyle(
                        color: _SellerListingsScreenState._gold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (highRisk || mergedFlags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: highRisk
                    ? AppColors.urgencyRed.withValues(alpha: 0.12)
                    : AppColors.accentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: highRisk ? AppColors.urgencyRed : AppColors.accentGoldAccent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highRisk
                        ? '⚠ High AI/Fraud Risk (${(item.fraudScore * 100).toStringAsFixed(0)}%)'
                        : 'Risk Flags',
                    style: TextStyle(
                      color: highRisk
                          ? AppColors.urgencyRed.withValues(alpha: 0.9)
                          : AppColors.accentGold.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (mergedFlags.isEmpty)
                    const Text(
                      'No explicit flags',
                      style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: mergedFlags
                          .map((f) => _chip(f, AppColors.secondaryText, isSmall: true))
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
          ],
          if (verificationMissing || highRisk) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReverify,
                icon: const Icon(Icons.verified_outlined, color: _SellerListingsScreenState._gold),
                label: const Text(
                  'Re-verify',
                  style: TextStyle(color: _SellerListingsScreenState._gold),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(item.createdAt),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            'Demand index: ${compact.format(item.demandScore)}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _categoryIcon(String category) {
    final key = category.toLowerCase();
    IconData icon;
    if (key.contains('livestock')) {
      icon = Icons.pets_rounded;
    } else if (key.contains('milk')) {
      icon = Icons.local_drink_rounded;
    } else if (key.contains('fruit')) {
      icon = Icons.apple_rounded;
    } else if (key.contains('vegetable')) {
      icon = Icons.eco_rounded;
    } else {
      icon = Icons.grass_rounded;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _SellerListingsScreenState._gold),
    );
  }

  Widget _chip(String text, Color color, {bool isSmall = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 7 : 8,
        vertical: isSmall ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: isSmall ? 11 : 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _valueBox(String title, String value) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _qtyLabel(double quantity, String unit) {
    final q = quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toStringAsFixed(2);
    return '$q $unit';
  }

  String _convertedQty(double quantity, String unit) {
    final lower = unit.toLowerCase();
    if (lower.contains('kg')) {
      final mann = quantity / 40;
      return mann > 0 ? '≈ ${mann.toStringAsFixed(2)} mann' : '';
    }
    if (lower.contains('mann') || lower.contains('mun')) {
      final kg = quantity * 40;
      return kg > 0 ? '≈ ${kg.toStringAsFixed(2)} kg' : '';
    }
    return '';
  }
}

class _CalculatorPanel extends StatelessWidget {
  const _CalculatorPanel({
    required this.isExpanded,
    required this.rateController,
    required this.qtyController,
    required this.selectedUnit,
    required this.marketRate,
    required this.onExpandedChanged,
    required this.onUnitChanged,
    required this.moneyFormatter,
  });

  final bool isExpanded;
  final TextEditingController rateController;
  final TextEditingController qtyController;
  final String selectedUnit;
  final double marketRate;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<String> onUnitChanged;
  final NumberFormat moneyFormatter;

  @override
  Widget build(BuildContext context) {
    final rate = double.tryParse(rateController.text.trim()) ?? 0;
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    final valid = rate > 0 && qty > 0;
    final total = valid ? rate * qty : 0;
    final marketTotal = valid ? marketRate * qty : 0;
    final diff = marketTotal - total;

    return Container(
      decoration: BoxDecoration(
        color: _SellerListingsScreenState._card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SellerListingsScreenState._gold.withValues(alpha: 0.35)),
      ),
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpandedChanged,
        collapsedIconColor: _SellerListingsScreenState._gold,
        iconColor: _SellerListingsScreenState._gold,
        title: const Text(
          'Calculator / کیلکولیٹر',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Row(
            children: [
              Expanded(
                child: _field(rateController, 'Rate / ریٹ'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(qtyController, 'Quantity / مقدار'),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  dropdownColor: const Color(0xFF20472F),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Unit'),
                  items: const [
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'mann', child: Text('mann')),
                  ],
                  onChanged: (v) {
                    if (v != null) onUnitChanged(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _calcStat('Total Value', 'Rs. ${moneyFormatter.format(total)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _calcStat('Market Value', 'Rs. ${moneyFormatter.format(marketTotal)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _calcStat(
                  'P/L',
                  '${diff >= 0 ? '+' : '-'}Rs. ${moneyFormatter.format(diff.abs())}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selectedUnit == 'kg'
                ? 'Helper: 1 mann = 40 kg'
                : 'Helper: 1 mann = 40 kg (${(qty * 40).toStringAsFixed(2)} kg)',
            style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          if (!valid)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Enter valid numeric rate and quantity.',
                style: TextStyle(color: AppColors.accentGoldAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label),
    );
  }

  Widget _calcStat(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      labelText: hint,
      labelStyle: const TextStyle(color: AppColors.secondaryText),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _SellerListingsScreenState._gold.withValues(alpha: 0.3)),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _TrustSection extends StatelessWidget {
  const _TrustSection({
    required this.items,
    required this.onRecordVideo,
    required this.onUpdateGps,
  });

  final List<StockItem> items;
  final VoidCallback onRecordVideo;
  final VoidCallback onUpdateGps;

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final videoOk = items.where((i) => i.videoVerified).length;
    final gpsOk = items.where((i) => i.gpsVerified).length;
    final timeOk = items.where((i) => i.createdAt.year > 2000).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _SellerListingsScreenState._card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SellerListingsScreenState._gold.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trust & Verification / تصدیق',
            style: TextStyle(color: _SellerListingsScreenState._gold, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('Video verified: $videoOk/$total', style: const TextStyle(color: AppColors.secondaryText)),
          Text('GPS verified: $gpsOk/$total', style: const TextStyle(color: AppColors.secondaryText)),
          Text('Timestamp verified: $timeOk/$total', style: const TextStyle(color: AppColors.secondaryText)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (videoOk < total)
                OutlinedButton.icon(
                  onPressed: onRecordVideo,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Record Verification Video (Required)'),
                ),
              if (gpsOk < total)
                OutlinedButton.icon(
                  onPressed: onUpdateGps,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Update GPS'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddStock});

  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460),
          decoration: BoxDecoration(
            color: _SellerListingsScreenState._card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _SellerListingsScreenState._gold.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 58, color: _SellerListingsScreenState._gold),
              const SizedBox(height: 10),
              const Text(
                'No stock yet / ابھی کوئی مال موجود نہیں',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start by adding your first stock item and keep it verified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _SellerListingsScreenState._gold,
                  foregroundColor: _SellerListingsScreenState._darkGreenStart,
                ),
                onPressed: onAddStock,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Add Stock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoFilteredResults extends StatelessWidget {
  const _NoFilteredResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _SellerListingsScreenState._card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'No items match current filters / موجودہ فلٹر سے کوئی نتیجہ نہیں',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.secondaryText, size: 52),
            const SizedBox(height: 8),
            const Text(
              'Connection issue / کنکشن مسئلہ',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({
    required this.text,
    required this.cachedAt,
    required this.refreshedAt,
  });

  final String text;
  final DateTime? cachedAt;
  final DateTime? refreshedAt;

  @override
  Widget build(BuildContext context) {
    final cached = cachedAt == null ? '--' : DateFormat('hh:mm a').format(cachedAt!);
    final refreshed = refreshedAt == null ? '--' : DateFormat('hh:mm a').format(refreshedAt!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentGoldAccent),
      ),
      child: Text(
        '$text • cached: $cached • refresh: $refreshed',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      children: [
        _skeletonBox(180),
        const SizedBox(height: 10),
        _skeletonBox(80),
        const SizedBox(height: 10),
        _skeletonBox(140),
        const SizedBox(height: 12),
        _skeletonBox(280),
        const SizedBox(height: 12),
        _skeletonBox(280),
      ],
    );
  }

  Widget _skeletonBox(double height) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.35, end: 0.65),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: value),
            borderRadius: BorderRadius.circular(14),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

class _SellerBackground extends StatelessWidget {
  const _SellerBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.background),
    );
  }
}

class StockItem {
  const StockItem({
    required this.id,
    required this.productName,
    required this.mandiType,
    required this.province,
    required this.district,
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.marketRate,
    required this.imagesCount,
    required this.videoVerified,
    required this.gpsVerified,
    required this.createdAt,
    required this.status,
    required this.paymentStatus,
    required this.fraudScore,
    required this.flags,
    required this.demandScore,
    required this.promotionType,
    required this.promotionStatus,
    required this.featuredCost,
    required this.promotionRequestedAt,
    required this.promotionApprovedAt,
    required this.promotionActivatedAt,
    required this.promotionExpiresAt,
  });

  final String id;
  final String productName;
  final String mandiType;
  final String province;
  final String district;
  final double quantity;
  final String unit;
  final double rate;
  final double marketRate;
  final int imagesCount;
  final bool videoVerified;
  final bool gpsVerified;
  final DateTime createdAt;
  final String status;
  final String paymentStatus;
  final double fraudScore;
  final List<String> flags;
  final double demandScore;
  final String promotionType;
  final String promotionStatus;
  final double featuredCost;
  final DateTime? promotionRequestedAt;
  final DateTime? promotionApprovedAt;
  final DateTime? promotionActivatedAt;
  final DateTime? promotionExpiresAt;

  double get totalValue => quantity * rate;
  double get marketValue => quantity * marketRate;
  double get profitLoss => marketValue - totalValue;
  double get profitPercent {
    final base = totalValue;
    if (base <= 0) return 0;
    return (profitLoss / base) * 100;
  }

  static StockItem fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final quantity = _readDouble(data['quantity']) ?? _readDouble(data['stockQty']) ?? 0;
    final rate = _readDouble(data['price']) ?? _readDouble(data['rate']) ?? 0;
    final marketRate = _readDouble(data['marketRate']) ?? _readDouble(data['market_average']) ?? rate;

    final imageUrls = data['imageUrls'];
    final imageCount = imageUrls is List ? imageUrls.length : _readInt(data['imagesCount']) ?? 0;

    final videoVerified = _readBool(data['videoVerified']) ||
        (_readDouble((data['verificationGeo'] as Map?)?['lat']) != null &&
            _readDouble((data['verificationGeo'] as Map?)?['lng']) != null);

    final gpsVerified = _readBool(data['gpsVerified']) ||
        (_readDouble((data['verificationGeo'] as Map?)?['lat']) != null &&
            _readDouble((data['verificationGeo'] as Map?)?['lng']) != null);

    final rawStatus = (data['status'] ?? 'active').toString().toLowerCase();
    final status = _normalizeStatus(rawStatus);

    final rawFraud = _readDouble(data['fraudScore']) ?? _readDouble(data['riskScore']) ?? 0;
    final fraudScore = rawFraud > 1 ? (rawFraud / 100).clamp(0.0, 1.0) : rawFraud.clamp(0.0, 1.0);

    final dynamic flagsRaw = data['flags'] ?? data['fraudFlags'] ?? data['riskFlags'];
    final flags = flagsRaw is List
        ? flagsRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false)
        : const <String>[];

    final createdAt = _readDate(data['updatedAt']) ??
        _readDate(data['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final rawPromotionType = (data['promotionType'] ?? '').toString().toLowerCase();
    final inferredPromotionType = (data['featuredAuction'] == true)
      ? 'featured_auction'
      : ((data['featured'] == true) ? 'featured_listing' : 'none');
    final promotionType = rawPromotionType.isEmpty ? inferredPromotionType : rawPromotionType;
    final rawPromotionStatus = (data['promotionStatus'] ?? '').toString().toLowerCase();
    final promotionStatus = rawPromotionStatus.isEmpty
      ? ((data['featured'] == true || data['featuredAuction'] == true) ? 'active' : 'none')
      : rawPromotionStatus;

    return StockItem(
      id: doc.id,
      productName: (data['product'] ?? data['productName'] ?? 'Unknown').toString(),
      mandiType: (data['mandiType'] ?? data['category'] ?? 'Crops').toString(),
      province: (data['province'] ?? '').toString(),
      district: (data['district'] ?? '').toString(),
      quantity: quantity,
      unit: ((data['unit'] ?? data['unitType'] ?? 'kg').toString()),
      rate: rate,
      marketRate: marketRate <= 0 ? rate : marketRate,
      imagesCount: math.max(0, imageCount),
      videoVerified: videoVerified,
      gpsVerified: gpsVerified,
      createdAt: createdAt,
      status: status,
      paymentStatus: (data['paymentStatus'] ?? 'pending').toString().toLowerCase(),
      fraudScore: fraudScore,
      flags: flags,
      demandScore: _readDouble(data['demandScore']) ?? _readDouble(data['views']) ?? 0,
      promotionType: promotionType,
      promotionStatus: promotionStatus,
      featuredCost: _readDouble(data['featuredCost']) ?? 0,
      promotionRequestedAt: _readDate(data['promotionRequestedAt']),
      promotionApprovedAt: _readDate(data['promotionApprovedAt']),
      promotionActivatedAt: _readDate(data['promotionActivatedAt']),
      promotionExpiresAt: _readDate(data['promotionExpiresAt']),
    );
  }

  static String _normalizeStatus(String raw) {
    if (raw.contains('sold') || raw.contains('completed') || raw.contains('closed')) {
      return 'sold';
    }
    if (raw.contains('expired')) {
      return 'expired';
    }
    return 'active';
  }

  static double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  static DateTime? _readDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class StockSummary {
  const StockSummary({
    required this.totalValue,
    required this.totalQuantityKg,
    required this.averageRate,
    required this.marketValue,
    required this.averageMarketRate,
    required this.profitLoss,
    required this.profitPercent,
    required this.lastUpdated,
    required this.overallVerified,
  });

  final double totalValue;
  final double totalQuantityKg;
  final double averageRate;
  final double marketValue;
  final double averageMarketRate;
  final double profitLoss;
  final double profitPercent;
  final DateTime lastUpdated;
  final bool overallVerified;

  String money(double value) => NumberFormat('#,##0.##', 'en_US').format(value);

  String get quantityLabel {
    final kg = totalQuantityKg;
    final mann = kg / 40;
    return '${kg.toStringAsFixed(2)} kg (≈ ${mann.toStringAsFixed(2)} mann)';
  }

  static StockSummary fromItems(List<StockItem> items) {
    if (items.isEmpty) {
      return StockSummary(
        totalValue: 0,
        totalQuantityKg: 0,
        averageRate: 0,
        marketValue: 0,
        averageMarketRate: 0,
        profitLoss: 0,
        profitPercent: 0,
        lastUpdated: DateTime.now(),
        overallVerified: false,
      );
    }

    double totalValue = 0;
    double totalQtyKg = 0;
    double weightedRate = 0;
    double marketValue = 0;
    double weightedMarketRate = 0;
    int verifiedCount = 0;
    DateTime latest = items.first.createdAt;

    for (final item in items) {
      totalValue += item.totalValue;
      final qtyKg = _toKg(item.quantity, item.unit);
      totalQtyKg += qtyKg;
      weightedRate += item.rate * qtyKg;
      marketValue += item.marketValue;
      weightedMarketRate += item.marketRate * qtyKg;
      if (item.videoVerified && item.gpsVerified) verifiedCount++;
      if (item.createdAt.isAfter(latest)) latest = item.createdAt;
    }

    final avgRate = totalQtyKg <= 0 ? 0.0 : weightedRate / totalQtyKg;
    final avgMarketRate = totalQtyKg <= 0 ? 0.0 : weightedMarketRate / totalQtyKg;
    final profitLoss = marketValue - totalValue;
    final profitPercent = totalValue <= 0 ? 0.0 : (profitLoss / totalValue) * 100;

    return StockSummary(
      totalValue: totalValue,
      totalQuantityKg: totalQtyKg,
      averageRate: avgRate,
      marketValue: marketValue,
      averageMarketRate: avgMarketRate,
      profitLoss: profitLoss,
      profitPercent: profitPercent,
      lastUpdated: latest,
      overallVerified: verifiedCount >= (items.length * 0.7),
    );
  }

  static double _toKg(double quantity, String unit) {
    final u = unit.toLowerCase();
    if (u.contains('kg')) return quantity;
    if (u.contains('mann') || u.contains('mun')) return quantity * 40;
    return quantity;
  }
}

List<String> runFraudChecks(StockItem item) {
  final flags = <String>[];
  final ratio = item.marketRate <= 0 ? 1.0 : (item.rate / item.marketRate);

  if (ratio > 1.5 || ratio < 0.6) {
    flags.add('price_anomaly');
  }
  if (item.district.trim().isEmpty || item.province.trim().isEmpty) {
    flags.add('location_mismatch');
  }
  if (item.imagesCount <= 0 && !item.videoVerified) {
    flags.add('repeated_media');
  }
  if (item.quantity <= 0 || item.quantity > 100000) {
    flags.add('suspicious_qty');
  }

  return flags;
}
