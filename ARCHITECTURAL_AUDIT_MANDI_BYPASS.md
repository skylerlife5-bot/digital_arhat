# 🔴 ARCHITECTURAL AUDIT: Mandi Rates Data Pipeline Leak

**Date:** April 5, 2026  
**Finding:** CRITICAL - Legacy ticker in buyer_home_screen.dart is completely bypassing marketplace presenter logic  
**Severity:** P0 - All updated mandi_home_presenter.dart logic is ignored

---

## EXECUTIVE SUMMARY

Despite updating `mandi_home_presenter.dart` with commodity normalization and unit conversion logic, the home screen displays raw Firestore data because:

**The buyer_home_screen.dart has its own completely separate Mandi ticker implementation that:**
1. Fetches raw Firestore documents
2. Parses them without presenter normalization
3. Renders them using inline `_toUrduCommodityLabel()` function
4. **Completely bypasses all mandi_home_presenter.dart logic**

This legacy implementation was originally code from the patches (removed but internally rebuilt), and is running in **parallel with the marketplace LiveMandiRatesSection** component.

---

## 📍 ROOT CAUSE: Exact File and Line Numbers

### THE SMOKING GUN: buyer_home_screen.dart - String Checking Bypass

**File:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart)  
**Function:** `_toUrduCommodityLabel(String raw)`  
**LINE 3049:** Direct string matching that allows "Shimla Mirch" to render

```dart
// LINE 3049 - EXACT BYPASS LOCATION
if (lower.contains('shimla mirch')) return 'شملہ مرچ';
```

Also at **line 8202** (duplicate implementation of same function):
```dart
// LINE 8202 - SECOND OCCURRENCE OF SAME BYPASS  
if (lower.contains('shimla mirch')) return 'شملہ مرچ';
```

### THE CALL CHAIN: How "Shimla Mirch" Gets Rendered

```
lib/dashboard/buyer/buyer_home_screen.dart
│
├─ Line 3387: Calls _buildTopMandiTicker()
│
├─ Line 3773-3870: _buildTopMandiTicker() function
│  └─ Gets _liveMandiTickerItems (raw _MandiTickerItem objects)
│  └─ Calls _finalizeHomeVisibleItems()
│  └─ For each item, calls:
│
├─ Line 3939-3980: _formatTickerItemText(_MandiTickerItem item)
│  └─ Line 3961: Calls _toUrduCommodityLabel(item.crop)
│  │  (item.crop = raw "Capsicum (Shimla Mirch)" from Firestore)
│  │
│  └─ Line 3003-3086: _toUrduCommodityLabel(String raw)
│     └─ Line 3049: if (lower.contains('shimla mirch')) 
│        return 'شملہ مرچ';  ← RENDERING WITHOUT PRESENTER
│
└─ Result: "شملہ مرچ • فیصل آباد • 8500 روپے / 100 کلو"
   (Shimla Mirch • Faisalabad • 8500 PKR / 100kg)
```

---

## 4 AUDIT AREAS ANALYZED

### ✅ AREA 1: Call-Site Mismatch - VERIFIED

**Status:** DIFFERENT IMPLEMENTATIONS, NOT A SYNC ISSUE

**Finding:** There are TWO completely separate mandi ticker implementations:

| Component | Location | File | Implementation |
|-----------|----------|------|-----------------|
| **New Marketplace Ticker** | Marketplace home | [lib/marketplace/widgets/live_mandi_rates_section.dart](lib/marketplace/widgets/live_mandi_rates_section.dart) | Uses `MandiHomePresenter.buildDisplayRow()` ✅ |
| **Legacy Dashboard Ticker** | Buyer home screen | [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart) | Uses inline `_toUrduCommodityLabel()` ❌ |

**Evidence:**
- Line 15 of [live_mandi_rates_section.dart](lib/marketplace/widgets/live_mandi_rates_section.dart): Correctly imports `mandi_home_presenter.dart`
- Line 28 of [buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart): Also imports `mandi_home_presenter.dart` BUT DOESN'T USE IT for ticker rendering
- Line 3049 of [buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart): Has its own commodity translation logic

**Verdict:** ✅ Imports are CORRECT. The issue is that buyer_home_screen has parallel implementation.

---

### 🔴 AREA 2: Data Pipeline Leak - CRITICAL FINDING

**Status:** RAW FIRESTORE DATA FLOWS DIRECTLY TO RENDERING

**Flow:**
```
1. buyer_home_screen.dart Line 600-620:
   ├─ Calls _fetchMandiDocsByStrictLocationStages()
   └─ Returns raw Firestore QueryDocumentSnapshot[] directly

2. Line 406:
   ├─ Calls _parseMandiTickerItemsDetailed(strategy.docs)
   └─ Parses documents into _MandiTickerItem objects
   └─ ** DOES NOT call MandiHomePresenter.buildDisplayRow() **

3. Line 1746-1770:
   ├─ Creates _MandiTickerItem with:
   │  ├─ crop: raw commodityName from Firestore
   │  ├─ unit: raw unit from Firestore  
   │  └─ location: raw city from Firestore
   │
   └─ ** NO NORMALIZATION, NO ALLOWLIST CHECK **

4. Line 555:
   ├─ Sets _liveMandiTickerItems = parsed
   
5. Line 3387:
   ├─ Calls _buildTopMandiTicker()
   
6. Line 3961:
   ├─ Calls _toUrduCommodityLabel(item.crop)
   ├─ item.crop = "Capsicum (Shimla Mirch)" (raw from Firestore!)
   └─ Returns "شملہ مرچ" WITHOUT presenter normalization

7. Line 3978-3980:
   └─ Returns display line with RAW UNIT from Firestore:
      "شملہ مرچ • Faisalabad • 8500 روپے / 100 کلو"
```

**Key Evidence:** Line 1746-1770 in [buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):
```dart
candidates.add(
  _TickerCandidate(
    item: _MandiTickerItem(
      crop: crop,  // ← RAW VALUE FROM FIRESTORE
      location: location,  // ← RAW VALUE FROM FIRESTORE
      unit: resolvedUnit,  // ← PARTIALLY PROCESSED BUT NOT CONVERTED
    ),
    // ... rest of candidate
  ),
);
```

**Verdict:** 🔴 **CRITICAL BYPASS** - Raw Firestore data enters rendering system without MandiHomePresenter logic.

---

### ✅ AREA 3: Location Binding - VERIFIED WORKING

**Status:** Location filtering EXISTS but is bypassed by empty userCity

**Finding:** The home screen has location context, but city filtering doesn't prevent unauthorized locations:

**Evidence at Line 1082-1110:**
```dart
int locationTier(Map<String, dynamic> map) {
  final cityTarget = _firstNonEmpty(<String?>[
    _selectedCityFilter,  // User's selected city
    (widget.userData['city'] ?? '').toString(),  // User's account city
    (widget.userData['cityVillage'] ?? '').toString(),
  ]);
  
  // Fetches docs by cityTarget...
  if (locationMatches(city, cityTarget)) {
    return 1;  // Exact match
  }
  // Falls through to broader matches if no exact match
}
```

**Problem:** If `cityTarget` is empty (user hasn't selected city and account city not set), the location tier becomes broader, and Faisalabad/Okara docs pass through.

**Verdict:** ✅ Location binding exists but can be bypassed if accountCity is not set properly.

---

### 🔴 AREA 4: Redundant UI Components - CRITICAL FINDING

**Status:** TWO TICKER IMPLEMENTATIONS ACTIVE IN PARALLEL

**Component 1 - LEGACY (Currently Active):**
- **Location:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart)
- **Function:** `_buildTopMandiTicker()` (Line 3773)
- **Rendering Method:** `_toUrduCommodityLabel()` (Line 3003-3086)
- **Status:** ✅ **CURRENTLY RENDERING** (Line 3387 called in build())
- **Presenter Usage:** ❌ DOES NOT use presenter

**Component 2 - NEW (Also Active):**
- **Location:** [lib/marketplace/widgets/live_mandi_rates_section.dart](lib/marketplace/widgets/live_mandi_rates_section.dart)
- **Function:** Included as a marketplace component
- **Rendering Method:** `MandiHomePresenter.buildDisplayRow()` (Line 407-430)
- **Status:** ✅ **CORRECTLY USING PRESENTER**
- **Presenter Usage:** ✅ USES presenter normalization

**Verdict:** 🔴 **BOTH ARE RUNNING** - The legacy implementation in buyer_home_screen is rendering on the home screen's "آج کی بہترین منڈی آفرز" section, while the new marketplace component is separate.

---

## 🎯 EXACTLY WHERE "SHIMLA MIRCH" IS ALLOWED TO RENDER

### Direct String Matching Bypass

**File:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart)  
**Function:** `_toUrduCommodityLabel(String raw)` (Lines 3003-3086 and 8140-8186)

**Line 3049** - PRIMARY BYPASS:
```dart
String _toUrduCommodityLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  
  // ... various checks ...
  
  final lower = value.toLowerCase();
  // ... many if statements ...
  
  if (lower.contains('shimla mirch')) return 'شملہ مرچ';  // ← LINE 3049
  
  // ... more translations ...
  
  return 'اجناس';  // fallback
}
```

**Line 8202** - DUPLICATE BYPASS:
```dart
// Same function, lines 8140-8186, duplicate code with:
if (lower.contains('shimla mirch')) return 'شملہ مرچ';  // ← LINE 8202
```

### Why This Bypasses the Presenter

1. **Raw Firestore value:** `"Capsicum (Shimla Mirch)"`
2. **Enters _toUrduCommodityLabel()** at line 3961
3. **Simple string check:** `if (lower.contains('shimla mirch'))`
4. **Returns Urdu directly:** `'شملہ مرچ'`
5. **NO NORMALIZATION:** Never calls `MandiHomePresenter.normalizeCommodityKey()`
6. **NO ALLOWLIST CHECK:** Never validates if commodity is in `homeCommodityAllowlist`
7. **NO UNIT CONVERSION:** Returns raw unit "100 کلو" from Firestore without conversion

---

## DATA FLOW DIAGRAM: The Bypass Route

```
Firestore mandi_rates Collection
│
├─ Document: {
│   commodityName: "Capsicum (Shimla Mirch)",
│   unit: "100 kg",
│   city: "Faisalabad",
│   price: 8500
│ }
│
├─ ROUTE A (CORRECT - but currently unused)
│  buyer_home_screen.dart → marketplace LiveMandiRatesSection
│  ✅ Calls MandiHomePresenter.buildDisplayRow()
│  ✅ Normalizes "Capsicum..." → "capsicum"
│  ✅ Checks allowlist
│  ✅ Converts unit "100 kg" → "40 کلو"
│  ✅ Converts price: 8500/100*40 = 3400
│  Result: "شملہ مرچ • لاہور • 3400 روپے / 40 کلو" ✅
│
├─ ROUTE B (INCORRECT - currently ACTIVE!)
│  buyer_home_screen.dart → _parseMandiTickerItemsDetailed()
│  ⚠️ Stores raw values in _MandiTickerItem
│  ├─ crop: "Capsicum (Shimla Mirch)" (unmodified)
│  ├─ unit: raw "100 kg" (unmodified)
│  ├─ location: raw "Faisalabad" (may be modified by tier)
│  │
│  ├─ _buildTopMandiTicker()
│  │ ├─ _formatTickerItemText()
│  │ └─ _toUrduCommodityLabel(item.crop)
│  │    └─ Line 3049: if (lower.contains('shimla mirch'))
│  │       return 'شملہ مرچ';
│  │
│  └─ Result: "شملہ مرچ • Faisalabad • 8500 روپے / 100 کلو" ❌
│     └─ PROBLEM: Raw unit, location not Lahore, no conversion
│
└─ Output: User sees "Shimla Mirch • 100kg" instead of normalized data
```

---

## SUMMARY TABLE: Audit Findings

| Area | Issue | Root Cause | Currently Active | Fix Required |
|------|-------|-----------|------------------|--------------|
| **1. Call-Site** | Import is correct | Not a sync issue | ✅ | None |
| **2. Data Pipeline** | Raw Firestore bypasses presenter | `_parseMandiTickerItemsDetailed()` doesn't use presenter | 🔴 YES | Route through presenter |
| **3. Location Binding** | Can show non-Lahore cities | Empty cityTarget allows broader matches | ✅ | Ensure accountCity is set |
| **4. Redundant Components** | Two ticker implementations | `_buildTopMandiTicker()` in buyer_home_screen | 🔴 YES | Remove legacy ticker |

---

## EVIDENCE FILES

- **Bypass Location:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):3049
- **Data Pipeline Entry:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):1746
- **Rendering Call:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):3961
- **Display Builder:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):3939
- **Ticker Render:** [lib/dashboard/buyer/buyer_home_screen.dart](lib/dashboard/buyer/buyer_home_screen.dart):3387

---

## CONCLUSION

The "Shimla Mirch" and "100kg" display is caused by a **complete architectural bypass in buyer_home_screen.dart**. The updated `mandi_home_presenter.dart` is never invoked for the home screen ticker. Instead, a legacy inline implementation renders raw Firestore data with basic string matching, allowing any commodity containing "shimla mirch" to pass through.

**The presenter logic updates are correct but unreachable from the home screen.**

