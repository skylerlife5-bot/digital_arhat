// ---------------------------------------------------------------------------
// AmisWheatScraperService
//
// Fetches real-time 40 kg Wheat (گندم) prices from public Pakistani
// agricultural sources.  Two sources are tried in order:
//
//   1. AMIS Punjab (www.amis.pk) — two-stage ASP.NET GET+POST flow.
//      Prices are published in Rs/100 Kg; the conversion is applied here:
//          price40kg = (price100kg / 100) * 40
//
//   2. UrduPoint Agriculture fallback if AMIS is unreachable.
//
// The returned LiveMandiRate is tagged:
//   - commodityRefId = 'WHEAT_GENERIC'
//   - metadata['canonicalId'] = 'WHEAT_GENERIC'
//   - sourcePriorityRank = 1
//   - rowConfidence = MandiRowConfidence.high
//   - sourceReliabilityLevel = MandiSourceReliabilityLevel.high
//   - unit = '40 kg'   (already converted — presenter must NOT re-convert)
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/live_mandi_rate.dart';

class AmisWheatScraperService {
  static const Duration _timeout = Duration(seconds: 14);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Fetches a live 40 kg Wheat rate.
  ///
  /// Returns `null` if all sources fail or return out-of-range data.
  static Future<LiveMandiRate?> fetchWheat40kgLiveRate() async {
    // Attempt 1 – AMIS Punjab
    try {
      final amisRate = await _fetchFromAmis();
      if (amisRate != null) {
        debugPrint(
          '[AmisWheatScraper] success via AMIS: ${amisRate.price.toStringAsFixed(0)} Rs/40kg',
        );
        return amisRate;
      }
    } catch (e) {
      debugPrint('[AmisWheatScraper] AMIS attempt failed: $e');
    }

    // Attempt 2 – UrduPoint Agriculture
    try {
      final upRate = await _fetchFromUrduPoint();
      if (upRate != null) {
        debugPrint(
          '[AmisWheatScraper] success via UrduPoint: ${upRate.price.toStringAsFixed(0)} Rs/40kg',
        );
        return upRate;
      }
    } catch (e) {
      debugPrint('[AmisWheatScraper] UrduPoint attempt failed: $e');
    }

    debugPrint('[AmisWheatScraper] all sources exhausted – returning null');
    return null;
  }

  // -------------------------------------------------------------------------
  // Source 1: AMIS Punjab (www.amis.pk)
  // -------------------------------------------------------------------------
  //
  // AMIS uses ASP.NET WebForms with UpdatePanel.  A two-step flow is needed:
  //   GET  → extract __VIEWSTATE / __VIEWSTATEGENERATOR / __EVENTVALIDATION
  //   POST → select Wheat commodity (ddlCommodity value "1")
  //
  // The response contains an HTML table with columns:
  //   City | Graph | Min | Max | FQP | Quantity   (all prices in Rs/100 Kg)
  //
  // We extract Min/Max/FQP from the first well-formed city row and convert
  // to 40 kg.

  static const String _amisBaseUrl = 'http://www.amis.pk/ViewPrices.aspx';

  // Sane range for wheat per 100 kg in Rs (2025 market band: ~7 000–22 000).
  static const double _amisMin100kg = 3000;
  static const double _amisMax100kg = 30000;

  static Future<LiveMandiRate?> _fetchFromAmis() async {
    // --- Step 1: GET initial page ----------------------------------------
    final pageUri = Uri.parse(_amisBaseUrl);
    final getResp = await http
        .get(pageUri, headers: _baseHeaders())
        .timeout(_timeout);

    if (getResp.statusCode != 200) {
      debugPrint('[AmisWheatScraper] AMIS GET returned ${getResp.statusCode}');
      return null;
    }

    final pageHtml = _decodeBody(getResp.bodyBytes);
    final viewState = _extractHiddenField(pageHtml, '__VIEWSTATE');
    if (viewState == null || viewState.isEmpty) {
      debugPrint('[AmisWheatScraper] AMIS: no __VIEWSTATE found in GET');
      return null;
    }

    final vsGen = _extractHiddenField(pageHtml, '__VIEWSTATEGENERATOR') ?? '';
    final evValidation =
        _extractHiddenField(pageHtml, '__EVENTVALIDATION') ?? '';

    // --- Step 2: POST to select Wheat (commodity dropdown value = "1") ----
    final postResp = await http
        .post(
          pageUri,
          headers: {
            ..._baseHeaders(),
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-MicrosoftAjax': 'Delta=true',
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: {
            '__VIEWSTATE': viewState,
            '__VIEWSTATEGENERATOR': vsGen,
            '__EVENTVALIDATION': evValidation,
            '__EVENTTARGET': r'ctl00$cphPage$ddlCommodity',
            '__EVENTARGUMENT': '',
            '__ASYNCPOST': 'true',
            r'ctl00$cphPage$ddlCommodity': '1', // 1 = Wheat in AMIS
          },
        )
        .timeout(_timeout);

    if (postResp.statusCode != 200) {
      debugPrint('[AmisWheatScraper] AMIS POST returned ${postResp.statusCode}');
      return null;
    }

    final postBody = _decodeBody(postResp.bodyBytes);

    // The UpdatePanel sends back a delta response; extract the HTML fragment.
    final fragment = _extractUpdatePanelHtml(postBody) ?? postBody;

    return _parseAmisWheatRow(fragment);
  }

  /// Parses AMIS HTML (or UpdatePanel fragment) for the first city row
  /// containing three consecutive numeric price cells (Min, Max, FQP).
  static LiveMandiRate? _parseAmisWheatRow(String fragment) {
    final doc = html_parser.parse(fragment);
    final rows = doc.querySelectorAll('tr');

    String? city;
    double? min100kg;
    double? max100kg;
    double? fqp100kg;

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) continue;

      // City cell is always first and contains a bold <a> tag.
      final cityAnchor = cells[0].querySelector('a');
      final candidateCity = cityAnchor?.text.trim() ??
          cells[0].text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (candidateCity.isEmpty) continue;

      // Cells 2, 3, 4 → Min, Max, FQP (0-indexed: skip Date/City + Graph)
      // Layout: td[city] td[graph] td[min] td[max] td[fqp] td[qty]
      final minTxt = _cellText(cells, 2);
      final maxTxt = _cellText(cells, 3);
      final fqpTxt = _cellText(cells, 4);

      final minVal = double.tryParse(minTxt.replaceAll(',', ''));
      final maxVal = double.tryParse(maxTxt.replaceAll(',', ''));
      final fqpVal = double.tryParse(fqpTxt.replaceAll(',', ''));

      if (fqpVal == null || fqpVal < _amisMin100kg || fqpVal > _amisMax100kg) {
        continue;
      }

      city = candidateCity;
      min100kg = (minVal != null && minVal > 0) ? minVal : null;
      max100kg = (maxVal != null && maxVal > 0) ? maxVal : null;
      fqp100kg = fqpVal;
      debugPrint(
        '[AmisWheatScraper] parsed row city=$city '
        'min100=$min100kg max100=$max100kg fqp100=$fqp100kg',
      );
      break;
    }

    if (fqp100kg == null) {
      // Fallback: scan raw text for three consecutive 4-6 digit numbers that
      // look like wheat prices — handles UpdatePanel plain-text responses.
      final rawRows = _scanRawPriceTriples(fragment);
      if (rawRows == null) {
        debugPrint('[AmisWheatScraper] AMIS: no valid price row found');
        return null;
      }
      min100kg = rawRows[0];
      max100kg = rawRows[1];
      fqp100kg = rawRows[2];
      city = 'Lahore'; // Default city when raw scan is used
    }

    // Convert Rs/100 Kg → Rs/40 Kg
    //   Proof: (fqp100kg / 100) * 40 = fqp100kg * 0.4
    //   Example: 9000 Rs/100kg → (9000 / 100) * 40 = 3600 Rs/40kg
    final fqp40kg = (fqp100kg! / 100.0) * 40.0;
    final min40kg = min100kg != null ? (min100kg / 100.0) * 40.0 : null;
    final max40kg = max100kg != null ? (max100kg / 100.0) * 40.0 : null;

    debugPrint(
      '[AmisWheatScraper] AMIS conversion: '
      '${fqp100kg.toStringAsFixed(0)} Rs/100kg '
      '→ ${fqp40kg.toStringAsFixed(0)} Rs/40kg',
    );

    return _buildWheatRate(
      price40kg: fqp40kg,
      min40kg: min40kg,
      max40kg: max40kg,
      city: city ?? 'Lahore',
      source: 'amis_pk_live',
      sourceId: 'amis_pk',
    );
  }

  // -------------------------------------------------------------------------
  // Source 2: UrduPoint Agriculture fallback
  // -------------------------------------------------------------------------

  static const String _urduPointWheatUrl =
      'https://www.urdupoint.com/agriculture/today-wheat-rate-in-pakistan.html';

  // UrduPoint wheat rate range for 40 kg in Rs (approximate 2025 band).
  static const double _upMin40kg = 1200;
  static const double _upMax40kg = 12000;

  static Future<LiveMandiRate?> _fetchFromUrduPoint() async {
    final uri = Uri.parse(_urduPointWheatUrl);
    final resp = await http
        .get(uri, headers: _baseHeaders())
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      debugPrint('[AmisWheatScraper] UrduPoint GET returned ${resp.statusCode}');
      return null;
    }

    final body = _decodeBody(resp.bodyBytes);
    return _parseUrduPointWheat(body);
  }

  static LiveMandiRate? _parseUrduPointWheat(String html) {
    final doc = html_parser.parse(html);

    // UrduPoint renders price data in `<table>` rows or <div> blocks.
    // Strategy: find all numeric tokens in the range [_upMin40kg, _upMax40kg]
    // that appear after any element containing "Lahore" or "Wheat" keywords.

    // Try table rows first.
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;

      String? city;
      double? price40kg;

      for (int i = 0; i < cells.length; i++) {
        final text = cells[i].text.trim();
        if (city == null && _isPakistaniCity(text)) {
          city = text;
          continue;
        }
        if (city != null) {
          final num = _extractNumeric(text);
          if (num != null && num >= _upMin40kg && num <= _upMax40kg) {
            price40kg = num;
            break;
          }
        }
      }

      if (city != null && price40kg != null) {
        debugPrint(
          '[AmisWheatScraper] UrduPoint parsed: city=$city '
          'price40kg=${price40kg.toStringAsFixed(0)} Rs',
        );
        return _buildWheatRate(
          price40kg: price40kg,
          city: city,
          source: 'urdupoint_live',
          sourceId: 'urdupoint_agri',
        );
      }
    }

    // Fallback: scan entire page text for the first numeric in valid range.
    final allText = doc.body?.text ?? '';
    final allNums = RegExp(r'\b(\d[\d,]+)\b').allMatches(allText);
    for (final m in allNums) {
      final val = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (val != null && val >= _upMin40kg && val <= _upMax40kg) {
        debugPrint(
          '[AmisWheatScraper] UrduPoint raw-text scan: '
          'price40kg=${val.toStringAsFixed(0)} Rs',
        );
        return _buildWheatRate(
          price40kg: val,
          city: 'Pakistan',
          source: 'urdupoint_live',
          sourceId: 'urdupoint_agri',
        );
      }
    }

    debugPrint('[AmisWheatScraper] UrduPoint: no valid price found in page');
    return null;
  }

  // -------------------------------------------------------------------------
  // LiveMandiRate factory — always 40 kg, WHEAT_GENERIC canonical ID
  // -------------------------------------------------------------------------

  static LiveMandiRate _buildWheatRate({
    required double price40kg,
    double? min40kg,
    double? max40kg,
    required String city,
    required String source,
    required String sourceId,
  }) {
    final now = DateTime.now().toUtc();
    final cityClean = city.trim().isEmpty ? 'Pakistan' : city.trim();

    return LiveMandiRate(
      id: 'wheat_generic_scraped_${now.millisecondsSinceEpoch}',
      commodityName: 'Wheat',
      commodityNameUr: 'گندم',
      categoryName: 'Grains',
      subCategoryName: 'Wheat',
      mandiName: '$sourceId Wheat',
      city: cityClean,
      district: cityClean,
      province: 'Punjab',
      latitude: 31.5204,
      longitude: 74.3587,
      // price is ALREADY per 40 kg — presenter must NOT convert again.
      price: price40kg,
      previousPrice: null,
      unit: '40 kg', // Explicit 40 kg to skip any further conversion
      trend: 'stable',
      source: source,
      sourceId: sourceId,
      sourceType: 'official_government',
      lastUpdated: now,
      syncedAt: now,
      freshnessStatus: MandiFreshnessStatus.live,
      sourcePriorityRank: 1,
      isNearby: false,
      isAiCleaned: false,
      metadata: <String, dynamic>{
        'canonicalId': 'WHEAT_GENERIC',
        'canonicalCommodityId': 'WHEAT_GENERIC',
        'commodityCanonicalId': 'WHEAT_GENERIC',
        'sourceTier': 1,
        'scraperSource': source,
        'averagePrice': price40kg,
      },
      categoryId: 'grains',
      subCategoryId: 'wheat',
      mandiId: '${sourceId}_wheat',
      currency: 'PKR',
      confidenceScore: 0.92,
      isLive: true,
      commodityRefId: 'WHEAT_GENERIC',
      minPrice: min40kg,
      maxPrice: max40kg,
      rowConfidence: MandiRowConfidence.high,
      sourceReliabilityLevel: MandiSourceReliabilityLevel.high,
      flags: const <String>[],
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static Map<String, String> _baseHeaders() => const <String, String>{
        'User-Agent':
            'Mozilla/5.0 (compatible; DigitalArhat/1.0; Pakistan Agri App)',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  /// Decodes HTTP response bytes, preferring UTF-8 with Latin-1 fallback.
  static String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Extracts a hidden-field value from ASP.NET form HTML.
  static String? _extractHiddenField(String html, String name) {
    final pattern = RegExp(
      'name="$name"[^>]*?value="([^"]*)"',
      caseSensitive: true,
      dotAll: true,
    );
    final match = pattern.firstMatch(html);
    if (match != null) return match.group(1);

    // Some renderers emit value before name
    final altPattern = RegExp(
      'id="$name"[^>]*?value="([^"]*)"',
      caseSensitive: true,
      dotAll: true,
    );
    return altPattern.firstMatch(html)?.group(1);
  }

  /// Extracts the HTML content from an ASP.NET UpdatePanel delta response.
  ///
  /// Format: `LENGTH|updatePanel|PANEL_ID|HTML_CONTENT|LENGTH|TYPE|...`
  static String? _extractUpdatePanelHtml(String body) {
    // Find the first "updatePanel" segment and extract its content block.
    final segments = body.split('|updatePanel|');
    if (segments.length < 2) return null;

    // segments[1] = "PANEL_ID|CONTENT|..."
    final afterId = segments[1].indexOf('|');
    if (afterId < 0) return null;

    final rest = segments[1].substring(afterId + 1);

    // Content ends at the next segment boundary: a digit-run followed by "|"
    // at the start of a new segment.
    final endPattern = RegExp(r'\|\d+\|');
    final endMatch = endPattern.firstMatch(rest);
    return endMatch != null ? rest.substring(0, endMatch.start) : rest;
  }

  /// Returns trimmed, non-HTML text of the Nth cell.
  static String _cellText(List cells, int index) {
    if (index >= cells.length) return '';
    return cells[index].text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// True if the string looks like a known Pakistani city name.
  static bool _isPakistaniCity(String s) {
    const cities = <String>{
      'lahore',
      'gujranwala',
      'faisalabad',
      'multan',
      'rawalpindi',
      'karachi',
      'okara',
      'sahiwal',
      'bahawalpur',
      'sargodha',
      'hyderabad',
      'peshawar',
      'quetta',
      'pakistan',
    };
    return cities.contains(s.toLowerCase().trim());
  }

  /// Extracts the first numeric value from a string (removes commas/Rs/PKR).
  static double? _extractNumeric(String s) {
    final clean = s
        .replaceAll(RegExp(r'[Rr][Ss]\.?\s*'), '')
        .replaceAll(RegExp(r'PKR', caseSensitive: false), '')
        .replaceAll(',', '')
        .trim();
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(clean);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  /// Scans raw text for the first group of three consecutive 4-6-digit numbers
  /// that all fall in the wheat 100 kg price band.
  ///
  /// Returns [min, max, fqp] or null.
  static List<double>? _scanRawPriceTriples(String text) {
    final matches = RegExp(r'(\d{4,6})').allMatches(text).toList();
    for (int i = 0; i + 2 < matches.length; i++) {
      final a = double.tryParse(matches[i].group(1)!);
      final b = double.tryParse(matches[i + 1].group(1)!);
      final c = double.tryParse(matches[i + 2].group(1)!);
      if (a == null || b == null || c == null) continue;
      if (a < _amisMin100kg || a > _amisMax100kg) continue;
      if (b < _amisMin100kg || b > _amisMax100kg) continue;
      if (c < _amisMin100kg || c > _amisMax100kg) continue;
      // Expect min ≤ max, and fqp in [min, max] range.
      if (a > b || c < a || c > b) continue;
      return [a, b, c];
    }
    return null;
  }
}
