import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'mandi_rates_seed.dart';

class MandiSeedUploader {
  const MandiSeedUploader._();

  static const String _collection = 'mandi_rates';
  static const String _city = 'Lahore';
  static const String _district = 'Lahore';
  static const String _province = 'Punjab';
  static const int _batchSize = 500;

  /// Uploads all items from [MandiRatesSeed.lahoreCatalog] to Firestore.
  ///
  /// Documents are written to the "mandi_rates" collection using deterministic
  /// IDs so re-running this is idempotent (set with merge: false).
  /// Only call this in debug mode — guard with [kDebugMode] at the call site.
  static Future<void> uploadToFirestore({
    FirebaseFirestore? db,
  }) async {
    final firestore = db ?? FirebaseFirestore.instance;
    final catalog = MandiRatesSeed.lahoreCatalog;

    debugPrint('[MandiSeedUploader] Starting upload of ${catalog.length} records...');

    var uploaded = 0;
    var batchIndex = 0;

    // Split into chunks of at most _batchSize (Firestore hard limit is 500).
    while (batchIndex < catalog.length) {
      final chunk = catalog.skip(batchIndex).take(_batchSize).toList(growable: false);
      final batch = firestore.batch();

      for (final seed in chunk) {
        final docId = 'amis_lahore_seed_${seed.id}';
        final ref = firestore.collection(_collection).doc(docId);

        batch.set(ref, <String, dynamic>{
          'commodityName': _englishCommodityForSeed(seed.id, seed.urduName),
          'commodityNameUr': seed.urduName,
          'city': _city,
          'district': _district,
          'province': _province,
          'price': seed.basePrice,
          'unit': seed.unit,
          'source': 'amis_lahore_official',
          'sourceId': docId,
          'sourceType': 'official',
          'sourcePriorityRank': 2,
          'contributorType': 'official',
          'verificationStatus': 'official verified',
          'acceptedBySystem': true,
          'acceptedByAdmin': true,
          'freshnessStatus': 'recent',
          'confidenceScore': 0.95,
          'syncedAt': FieldValue.serverTimestamp(),
          'metadata': <String, dynamic>{
            'urduName': seed.urduName,
            'seedFallback': true,
          },
          'isLive': false,
          'category': seed.group,
          'subcategory': seed.group,
        });
      }

      try {
        await batch.commit();
        uploaded += chunk.length;
        debugPrint('Uploaded $uploaded records to Firestore');
      } catch (e, stack) {
        debugPrint('[MandiSeedUploader] Batch commit failed at index $batchIndex: $e');
        debugPrintStack(stackTrace: stack);
        rethrow;
      }

      batchIndex += _batchSize;
    }

    debugPrint('[MandiSeedUploader] Done. Uploaded $uploaded records to Firestore (collection: $_collection)');
  }

  static String _englishCommodityForSeed(String id, String urduName) {
    switch (id) {
      case 'live_chicken':
        return 'Live Chicken';
      case 'chicken_meat':
        return 'Chicken Meat';
      case 'beef':
        return 'Beef';
      case 'mutton':
        return 'Mutton';
      case 'wheat':
        return 'Wheat';
      case 'rice_irri':
      case 'rice_basmati':
        return 'Rice';
      case 'sugar':
        return 'Sugar';
      case 'flour_20kg':
        return 'Flour';
      case 'milk':
        return 'Milk';
      case 'eggs':
        return 'Eggs';
      case 'potato':
        return 'Potato';
      case 'onion':
        return 'Onion';
      case 'tomato':
        return 'Tomato';
      case 'garlic':
        return 'Garlic';
      case 'ginger':
        return 'Ginger';
      case 'lemon':
        return 'Lemon';
      case 'spinach':
        return 'Spinach';
      case 'cauliflower':
        return 'Cauliflower';
      case 'ladyfinger':
        return 'Ladyfinger';
      case 'cabbage':
        return 'Cabbage';
      case 'carrot':
        return 'Carrot';
      case 'peas':
        return 'Peas';
      case 'green_chili':
        return 'Green Chili';
      case 'coriander':
        return 'Coriander';
      case 'apple':
        return 'Apple';
      case 'banana':
        return 'Banana';
      case 'guava':
        return 'Guava';
      case 'citrus':
      case 'orange':
        return 'Orange';
      case 'mango':
        return 'Mango';
      case 'pomegranate':
        return 'Pomegranate';
      case 'grapes':
        return 'Grapes';
      case 'chana_dal':
        return 'Daal Chana';
      case 'lentil_masoor':
      case 'masoor_dal':
        return 'Daal Masoor';
      case 'lentil_moong':
        return 'Daal Moong';
      case 'lentil_mash':
        return 'Daal Mash';
      case 'gram':
      case 'white_chana':
        return 'White Chana';
      case 'black_chana':
        return 'Black Chana';
      case 'cooking_oil_5l':
      case 'mustard_oil_5l':
        return 'Cooking Oil';
      case 'desi_ghee_1kg':
        return 'Ghee';
      case 'tea_900g':
        return 'Tea';
      case 'salt_800g':
        return 'Salt';
      case 'red_chili_powder':
        return 'Red Chili Powder';
      case 'turmeric_powder':
        return 'Turmeric Powder';
      default:
        return urduName;
    }
  }
}
