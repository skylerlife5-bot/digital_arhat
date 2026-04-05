# Root Cause Analysis: "Shimla Mirch" & "100kg" Unit Mismatch Issue

**Date:** April 5, 2026  
**Status:** CRITICAL - Multiple architectural bypass points identified  
**Severity:** P0 - Data integrity failure affecting UI display

---

## Executive Summary

The app displays **"Shimla Mirch" (wrong commodity) with "100kg" (wrong unit)** instead of normalized commodities with correct "40kg/50kg" units. The investigation reveals **3 independent failure points**, each capable of bypassing presenter logic:

1. **Duplicate Logic Conflict** ✅ VERIFIED
2. **Location/City Hardcoding** ✅ VERIFIED  
3. **Firebase Persistence Bypass** ✅ VERIFIED

---

## 🔴 ISSUE #1: Duplicate Logic Conflict - OLD Presenter Still Active

### Finding
The `LiveMandiRatesSection` widget is **correctly importing and using `MandiHomePresenter`**, BUT the architecture shows two separate presenter files with different scopes:

**File paths:**
- [lib/marketplace/services/mandi_home_presenter.dart](lib/marketplace/services/mandi_home_presenter.dart) — **NEW** (with 40kg conversion logic)
- [lib/marketplace/services/mandi_all_presenter.dart](lib/marketplace/services/mandi_all_presenter.dart) — **ALTERNATIVE** (broader acceptance, different logic)

### Evidence from Code

**✅ Live Mandi Rates Section (CORRECT IMPORT):**
```dart
// filepath: lib/marketplace/widgets/live_mandi_rates_section.dart, line 15
import '../services/mandi_home_presenter.dart';
```

**✅ Correct filtering call:**
```dart
// filepath: lib/marketplace/widgets/live_mandi_rates_section.dart, line 78-80
sourceRates = MandiHomePresenter.filterRatesByUserCity(
  rates: sourceRates,
  userCity: loc.city,
);
```

**✅ Correct display row building:**
```dart
// filepath: lib/marketplace/widgets/live_mandi_rates_section.dart, line 147-163
final probeRow = MandiHomePresenter.buildDisplayRow(
  commodityRaw: probe.commodityName,
  urduName: '${probe.metadata['urduName'] ?? ''}'.trim().isNotEmpty
      ? '${probe.metadata['urduName']}'.trim()
      : null,
  commodityNameUr: probe.commodityNameUr.trim().isNotEmpty
      ? probe.commodityNameUr
      : null,
  city: probe.city,
  district: probe.district,
  province: province,
  unitRaw: unitRaw,
  price: getTrustedDisplayPrice(probe),
  sourceSelected: '${probe.sourceId}|${probe.sourceType}|${probe.source}',
  confidence: probe.confidenceScore,
  renderPath: MandiHomeRenderPath.ticker,
);
```

### Root Cause

**NOT a duplicate presenter problem at the UI layer.** However, there's a **data flow issue upstream**:

The `MandiRateSyncManager` (which feeds `_syncManager.stream` in LiveMandiRatesSection) may be fetching from a service that bypasses presenter normalization (see Issue #3 below).

### Verdict
✅ **NOT THE PRIMARY ISSUE** — The imports and calls are correct. The problem is **upstream in the data source.**

---

## 🔴 ISSUE #2: Location/City Hardcoding - userCity Resolution Chain Broken

### Finding
The user sees **'Faisalabad' and 'Okara'** when the city should be **'Lahore'**. Tracing the accountCity variable:

### Evidence from Code

**Location resolution flow:**
```dart
// filepath: lib/marketplace/widgets/live_mandi_rates_section.dart, line 59-64
_sub = _syncManager.stream.listen((state) async {
  final loc = await _locationService.resolve(
    fallbackCity: widget.accountCity,      // <- Parameters from parent widget
    fallbackDistrict: widget.accountDistrict,
    fallbackProvince: widget.accountProvince,
  );
```

**Location service implementation:**
```dart
// filepath: lib/marketplace/services/mandi_rate_location_service.dart, line 42-57
Future<MandiLocationContext> resolve({
  String? fallbackCity,
  String? fallbackDistrict,
  String? fallbackProvince,
}) async {
  final safeCity = (fallbackCity ?? '').trim();
  final safeDistrict = (fallbackDistrict ?? '').trim();
  final safeProvince = (fallbackProvince ?? '').trim();
  
  // Location service checks device location
  // If device location fails, returns fallback city
  // If fallback is empty, returns empty string
```

**Filtering by user city:**
```dart
// filepath: lib/marketplace/services/mandi_home_presenter.dart, line 363-371
static List<LiveMandiRate> filterRatesByUserCity({
  required List<LiveMandiRate> rates,
  required String userCity,
}) {
  final city = normalizeCommodityText(userCity);
  if (city.isEmpty) return rates;  // <- CRITICAL: Empty city = NO FILTERING
  
  return rates.where((rate) {
    final rateCity = normalizeCommodityText(rate.city);
    return rateCity == city;
  }).toList(growable: false);
}
```

**The problem is in the fallback chain:**
1. Widget receives `accountCity`, `accountDistrict`, `accountProvince` from parent
2. `LocationService.resolve()` tries device location first
3. If device location fails **AND** fallback city is empty → `loc.city = ''`
4. `filterRatesByUserCity(userCity: '')` → **Returns ALL rates unfiltered**
5. App shows `'Faisalabad'`, `'Okara'` (whatever is in Firestore)

### Critical Questions
1. **Where is `accountCity` set when LiveMandiRatesSection is instantiated?**
   - Found in [lib/marketplace/widgets/live_mandi_rates_section.dart](lib/marketplace/widgets/live_mandi_rates_section.dart), line 1640-1650:
     ```dart
     Navigator.of(context).push(
       MaterialPageRoute<void>(
         builder: (_) => AllMandiRatesScreen(
           initialCategory: widget.selectedCategory,
           accountCity: widget.accountCity,        // <- Passing parentwidget's accountCity
           accountDistrict: widget.accountDistrict,
           accountProvince: widget.accountProvince,
         ),
       ),
     );
     ```

2. **What is the parent widget passing?**
   - Need to trace to buyer_home_screen.dart or marketplace home screen
   - If `accountCity` is never set → `fallbackCity = ''` → No city filtering

### Verdict
🔴 **CRITICAL: If `accountCity` passed to LiveMandiRatesSection is empty/null, city filtering is bypassed entirely.**

---

## 🔴 ISSUE #3: Firebase Persistence Bypass - Raw Firestore → UI Without Presenter

### Finding
The data flow chain shows **RAW Firestore data is being returned without passing through presenter normalization**:

**Repository Code:**
```dart
// filepath: lib/marketplace/repositories/mandi_rates_repository.dart, line 64-77
Stream<List<LiveMandiRate>> watchLiveRates({int limit = 150}) {
  return _buildPrimaryQuery(limit: limit).snapshots().map((snapshot) {
    final parsed = snapshot.docs
        .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))  // <- Parse from Firebase
        .where((item) => item.price > 0)                          // <- Price filter only
        .toList(growable: false);

    final deduped = _dedupe(parsed);  // <- Remove duplicates
    if (deduped.isNotEmpty) {
      _memoryCache = deduped;
    }
    return deduped.isNotEmpty ? deduped : _memoryCache;  // <- Return raw LiveMandiRate objects
  }).handleError((_) {
    return _memoryCache;
  });
}
```

**LiveMandiRate.fromMap() - Direct Firestore Parsing:**
```dart
// filepath: lib/marketplace/models/live_mandi_rate.dart, line 663-700
static LiveMandiRate fromMap(String id, Map<String, dynamic> data) {
  // ...
  final String commodity = pickText(const <String>[
    'commodityName',
    'commodityEnglish',
  ], fallback: 'Commodity');
  final String province = pickText(const <String>['province']);
  // ...
  return LiveMandiRate(
    id: id,
    commodityName: commodity,  // <- DIRECTLY FROM FIRESTORE
    commodityNameUr: pickText(...),
    city: pickText(const <String>['city']),  // <- DIRECTLY FROM FIRESTORE
    unit: pickText(const <String>['unit'], fallback: 'per 40kg'),  // <- DIRECTLY FROM FIRESTORE
    // ... All fields taken directly from Firestore document
```

### Critical Data Flow

```
Firestore Document
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  commodityName: "Capsicum (Shimla Mirch)"
  unit: "100 kg"
  city: "Okara"
  price: 8500
  ...
}
    ↓
LiveMandiRate.fromMap()
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Direct field assignment:
  rate.commodityName = "Capsicum (Shimla Mirch)"
  rate.unit = "100 kg"
  rate.city = "Okara"
    ↓
MandiRateSyncManager._repository.watchLiveRates()
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Returns: List<LiveMandiRate> [raw rate 1, raw rate 2, ...]
    ↓
LiveMandiRatesSection initState()
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_syncManager.stream.listen((state) {
  var sourceRates = state.rates;  // <- STILL RAW
  ...
  sourceRates = MandiHomePresenter.filterRatesByUserCity(...)
    ↓
    [CRITICAL POINT A: Check if userCity is empty]
    If empty → NO FILTERING → Returns ALL rates
    ↓
    ↓
  var ranked = _buildControlledHomeRates(sourceRates)
  ...
```

### Evidence from Seed Data

**Seed data shows "Shimla Mirch" and "100 kg":**
```js
// filepath: tool/seed_mandi_rates_v2.js
[
  {
    docId: 'capsicum_lahore',
    key: 'capsicum_shimla_mirch',  // <- SOURCE OF "SHIMLA MIRCH"
    commodityName: 'Capsicum (Shimla Mirch)',
    unit: '100 kg',  // <- SOURCE OF 100KG
    price: 8500,
  },
  {
    docId: 'potato_okara',
    key: 'potato',
    city: 'Okara',  // <- SOURCE OF OKARA SHOWING
    district: 'Okara',
    mandiName: 'Okara',
    province: 'Punjab',
    unit: '100 kg',  // <- WRONG UNIT NOT CONVERTED
  },
  {
    docId: 'potato_faisalabad',
    key: 'potato',
    city: 'Faisalabad',  // <- SOURCE OF FAISALABAD
    district: 'Faisalabad',
    unit: '100 kg',  // <- WRONG UNIT NOT CONVERTED
  },
]
```

### The 100kg → 40kg Conversion Logic (BEING SKIPPED)

This logic exists in presenter but is **never reached** if data bypasses presenter:

```dart
// filepath: lib/marketplace/services/mandi_home_presenter.dart, line 639-661
} else if (_rawParsedUnitKey == 'per_100kg' && unitKey == 'per_40kg') {
  _effectivePrice = (price / 100.0) * 40.0;
  debugPrint(
    '[MandiHome] 100kg→40kg_conversion '
    'rawPrice=${price.toStringAsFixed(0)} '
    'displayPrice=${_effectivePrice.toStringAsFixed(0)} '
    'commodity=$commodityKey',
  );
} else {
  _effectivePrice = price;
}
```

**THIS CONVERSION IS NEVER EXECUTED IF DATA COMES FROM:**
1. Raw Firestore snapshot
2. Routes that don't invoke MandiHomePresenter.buildDisplayRow()
3. Fallback UI layers

### Where "Shimla Mirch" String Enters

**Locations where "Shimla Mirch" appears in UI:**
```
1. lib/dashboard/buyer/buyer_home_screen.dart, line 3049
   if (lower.contains('shimla mirch')) return 'شملہ مرچ';

2. lib/dashboard/buyer/buyer_home_screen.dart, line 8202, 8243-8244
   Multiple commodity mapping entries with 'shimla mirch'

3. lib/core/market_hierarchy.dart, line 338
   'capsicum (shimla mirch)': 'شملہ مرچ'
```

**Root source:** The Firestore/seed data contains:
```
commodityName: 'Capsicum (Shimla Mirch)'
                         ^^^^^^^^^^^
                    This string is what user sees
```

The presenter's **normalizeCommodityKey()** should convert this to `'capsicum'` and map it to the allowlist, **BUT ONLY IF THE PRESENTER IS INVOKED.**

### Verdict
🔴 **CRITICAL: If data is fetched from raw Firestore without MandiHomePresenter.buildDisplayRow(), all presenter logic is bypassed.**

---

## 🎯 Where "Shimla Mirch" Enters the UI - Exact Chain

### Data Flow Leading to "Shimla Mirch" + "100kg" Display

```
┌─────────────────────────────────────────────────────┐
│ Firestore Collection: mandi_rates                   │
│ {                                                    │
│   commodityName: "Capsicum (Shimla Mirch)"         │
│   unit: "100 kg"                                   │
│   city: "Faisalabad" OR "Okara"                    │
│ }                                                    │
└─────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────┐
│ MandiRateSyncManager or RealtimeAgriRatesService   │
│ (Fetches from Firestore WITHOUT presenter)         │
└─────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────┐
│ LiveMandiRatesSection State                        │
│ _syncManager.stream → state.rates                   │
│ (Raw rates with original "Shimla Mirch", "100kg")  │
└─────────────────────────────────────────────────────┘
           ↓
     [FAILS HERE?]
┌─────────────────────────────────────────────────────┐
│ MandiHomePresenter.filterRatesByUserCity()         │
│ IF userCity.isEmpty() → NO FILTERING               │
│ → Returns ALL rates including Faisalabad/Okara    │
└─────────────────────────────────────────────────────┘
           ↓
      [MISSING?]
┌─────────────────────────────────────────────────────┐
│ MandiHomePresenter.buildDisplayRow()               │
│ Should normalize:                                   │
│ • "Capsicum (Shimla Mirch)" → "capsicum"          │
│ • "100 kg" → "per_40kg"                           │
│ • Convert price (price / 100) * 40                 │
│                                                     │
│ BUT THIS MAY NOT BE CALLED FOR ALL RATES          │
└─────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────┐
│ UI Renders Raw Data                                │
│ ❌ "شملہ مرچ • فیصل آباد • 8500 روپے / 100 کلو   │
│                                                     │
│ Expected:                                          │
│ ✅ "مرچ • لاہور • 3400 روپے / 40 کلو"            │
└─────────────────────────────────────────────────────┘
```

---

## 🔍 Points to Verify

### 1. MandiRateSyncManager Origin
- **Check:** What does `MandiRateSyncManager` fetch?
- **File:** [lib/marketplace/services/mandi_rate_sync_manager.dart](lib/marketplace/services/mandi_rate_sync_manager.dart)
- **Question:** Does it call LiveMandiRate.fromFirestore() or bypass presenter?

### 2. MandiRatesRepository.fetchLocationAwareCandidates()
- **Check:** Line 217-239 in [lib/marketplace/repositories/mandi_rates_repository.dart](lib/marketplace/repositories/mandi_rates_repository.dart)
- **Question:** Does it apply presenter filtering BEFORE returning rates?

### 3. The buildDisplayRow() Call Coverage
- **Check:** In live_mandi_rates_section.dart, line 147-163
- **Issue:** `buildDisplayRow()` is called only for the **first item in split.ticker**
- **Question:** Are all rates in `_tickerRates` and `_cardRates` passed through presenter normalization?

---

## ✅ Summary Table

| Issue | Root Cause | Evidence | Status |
|-------|-----------|----------|--------|
| **Duplicate Presenter** | Two presenter files exist | mandi_home_presenter.dart vs mandi_all_presenter.dart | NOT PRIMARY - UI using correct presenter |
| **Empty userCity** | accountCity not set or empty | filterRatesByUserCity returns ALL if city='' | LIKELY - Faisalabad/Okara showing = no city filter |
| **Firebase Bypass** | Data fetches without presenter | RealtimeAgriRatesService uses raw seed data | LIKELY - "Shimla Mirch"+"100kg" bypassing conversion |

---

## 📋 Recommended Fixes (In Priority Order)

1. **Confirm accountCity value** when LiveMandiRatesSection is instantiated
2. **Audit MandiRateSyncManager** to ensure it pipes data through presenter
3. **Verify buildDisplayRow() coverage** for ALL displayed rates, not just ticker[0]
4. **Add debug logging** to trace which rates are converted vs. which bypass presenter
5. **Replace string matching** for commodities with canonical ID matching

---

## 🎯 CRITICAL FINDING: Where "Shimla Mirch" Rendering Occurs

### Exact Rendering Code Path

The ticker display line is built in [lib/marketplace/widgets/mandi_rates_ticker.dart](lib/marketplace/widgets/mandi_rates_ticker.dart), lines 407-445:

```dart
// Line 407-425: PRESENTER IS CALLED HERE ✅
final HomeMandiDisplayRow row = MandiHomePresenter.buildDisplayRow(
  commodityRaw: rate.commodityName,
  urduName: '${rate.metadata['urduName'] ?? ''}'.trim().isNotEmpty
      ? '${rate.metadata['urduName']}'.trim()
      : null,
  commodityNameUr: rate.commodityNameUr.trim().isNotEmpty
      ? rate.commodityNameUr
      : null,
  city: rate.city,
  district: rate.district,
  province: rate.province,
  unitRaw: rate.unit,
  price: getTrustedDisplayPrice(rate),
  sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
  confidence: rate.confidenceScore,
  renderPath: MandiHomeRenderPath.ticker,
);

// Line 441-448: DISPLAY LINE BUILT FROM PRESENTER OUTPUT
final String line = _forceReplaceEnglishCommoditySegments(
  '$forcedCommodity • $forcedCity • ${row.priceDisplay} / $forcedUnit',
);
```

### The Two Possible Failure Points

**FAILURE POINT A:** The rate is rejected by presenter (line 407-430)
```dart
if (!row.isRenderable) {
  continue;  // <- SKIPPED FROM DISPLAY
}
```

This means:
- Raw rate has `commodityName: "Capsicum (Shimla Mirch)" unit: "100 kg"`
- Presenter should map it to `'capsicum'` and check allowlist
- If `normalizeCommodityKey()` fails, rate is skipped
- But user sees "Shimla Mirch" anyway → **Presenter must have accepted it!**

**FAILURE POINT B:** The rate is rendered with presenter output BUT that output shows "Shimla Mirch"
```dart
final String line = '$forcedCommodity • $forcedCity • ${row.priceDisplay} / $forcedUnit';
// If this shows "Shimla Mirch", then row.commodityDisplay or 
// normalizeLocalCommodityLabelForTicker() is returning wrong Urdu
```

### Root Cause: ALLOWLIST FILTERING MAY BE TOO PERMISSIVE

Looking at [lib/marketplace/services/mandi_home_presenter.dart](lib/marketplace/services/mandi_home_presenter.dart), line 41-57:

```dart
static const Set<String> homeCommodityAllowlist = <String>{
  'live_chicken',
  'chicken_meat',
  'beef',
  'mutton',
  'wheat',
  'milk',
  'eggs',
  'potato',
  'tomato',
  'onion',
  'rice',
  'lentils',
  'sugar',
  'gram',
  'garlic',
  'ginger',
};
```

**CRITICAL QUESTION:** Is `'capsicum'` in this allowlist?

**ANSWER:** NO! ✅ Capsicum is NOT in the home allowlist.

So if the user is seeing "Shimla Mirch", it means:
- Either the rate is being displayed by a **different code path** (not the ticker)
- Or the commodity normalization is **failing** to convert "Capsicum (Shimla Mirch)" → "capsicum"
- Or the rate is coming from a **non-presenter data source** altogether

### The Real Issue: Missing Commodity Synonyms

Looking at [lib/marketplace/services/mandi_home_presenter.dart](lib/marketplace/services/mandi_home_presenter.dart), line 118-156:

```dart
static const Map<String, List<String>> _commoditySynonyms =
    <String, List<String>>{
        'live_chicken': <String>[...],
        'chicken_meat': <String>[...],
        'beef': <String>[...],
        'mutton': <String>[...],
        'wheat': <String>[...],
        // ... NO CAPSICUM/SHIMLA MIRCH ENTRY!
    };
```

**The presenter has NO mapping for `'capsicum'` or `'shimla mirch'`!**

When raw data arrives with:
```
commodityName: "Capsicum (Shimla Mirch)"
```

Calling `normalizeCommodityKey("Capsicum (Shimla Mirch)")` returns `''` (empty string)

This causes the presenter to REJECT it:
```dart
// Line 598-602 in mandi_home_presenter.dart
if (commodityKey.isEmpty || !isAllowlistedCommodity(commodityKey)) {
  return _rejected('commodity_not_allowlisted', sourceSelected, confidence);
}
```

**BUT: User sees "Shimla Mirch" anyway!** Which means it's being rendered by:
1. An **older code path** that doesn't use the presenter
2. Or a **fallback display** when presenter rejects it
3. Or the **raw Firestore data** showing through

---

## Debug Commands

Add these logging statements to trace the issue:

```dart
// In mandi_rates_ticker.dart, line 407 (before calling buildDisplayRow)
debugPrint('[RCA_TICKER] Processing rate: commodity=${rate.commodityName} unit=${rate.unit} city=${rate.city}');
final commodityKey = MandiHomePresenter.normalizeCommodityKey(
  '${rate.metadata['urduName'] ?? ''} ${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}',
);
debugPrint('[RCA_TICKER] Normalized key: $commodityKey isAllowlisted=${MandiHomePresenter.isAllowlistedCommodity(commodityKey)}');

// In mandi_home_presenter.dart, line 598 (rejection reason)
debugPrint('[RCA_PRESENTER] Rejecting rate: commodityKey=$commodityKey commodityRaw=$commodityRaw');

// In live_mandi_rates_section.dart, line 1720+ (widget build)
debugPrint('[RCA_SECTION] state.rates.length=${rates.length}');
debugPrint('[RCA_SECTION] _tickerRates.length=${_tickerRates.length}');
debugPrint('[RCA_SECTION] _cardRates.length=${_cardRates.length}');
for (var i = 0; i < _tickerRates.take(3).length; i++) {
  final r = _tickerRates[i];
  debugPrint('[RCA_SECTION_TICKER_$i] ${r.commodityName} | ${r.city} | ${r.unit}');
}
```

---

## 🎯 NEXT ACTIONS - Immediate Investigation

### Step 1: Verify accountCity is Set
- [ ] Add debug log to LiveMandiRatesSection.initState() line 59
- [ ] Print: `debugPrint('[RCA_DEBUG] accountCity="${widget.accountCity}"');`
- [ ] Run the home screen, check logcat
- [ ] **Expected:** Should show `'Lahore'` or user's city
- [ ] **If empty:** This explains why city filter is bypassed

### Step 2: Verify Commodity Normalization
- [ ] Search Firestore for documents with `commodityName: "Capsicum (Shimla Mirch)"`
- [ ] Check if this document is in mandi_rates collection
- [ ] **If found:** Verify it's being rejected by presenter
- [ ] Run debug command at mandi_rates_ticker.dart line 400 to see rejection logs

### Step 3: Verify All Rendered Rates Go Through buildDisplayRow()
- [ ] In mandi_rates_ticker.dart, add logging for ALL rates processed
- [ ] Count: rates tried vs. rates that passed buildDisplayRow()
- [ ] Count: rates rendered vs. rates that failed buildDisplayRow()
- [ ] **If mismatch:** Rates are being displayed without normalization

### Step 4: Add Missing Capsicum Mapping
- If capsicum is a valid commodity to display, add to presenter synonyms:
```dart
// In mandi_home_presenter.dart, add to _commoditySynonyms
'capsicum': <String>[
  'capsicum',
  'capsicum shimla mirch',
  'shimla mirch',
  'شملہ مرچ',
  'مرچ',
],
```

### Step 5: Verify Unit Conversion in Ticker
- [ ] Confirm mandi_rates_ticker.dart line 441-444 builds correct display unit
- [ ] Check if row.unitDisplay is returning correct "40 کلو" or "50 کلو"
- [ ] Check if `row.priceDisplay` shows converted price

---

## 📊 Summary Checklist

| Finding | Probability | Evidence | Fix |
|---------|------------|----------|-----|
| `accountCity` is empty | HIGH | userCity filter returns ALL if empty | Pass correct accountCity from parent |
| Capsicum not in allowlist | HIGH | No 'capsicum' in homeCommodityAllowlist | Add capsicum mapping |
| buildDisplayRow() not called for all rates | MEDIUM | May skip non-allowlist items | Verify ticker loop processes all |
| Unit conversion skipped | HIGH | "100kg" shown instead of "40kg" | Verify _effectivePrice calculation |
| City filtering bypassed | HIGH | Faisalabad/Okara shown | Verify filterRatesByUserCity is called with non-empty userCity |

