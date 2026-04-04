import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'export_buyer_detail_screen.dart';
import 'models/export_buyer_profile.dart';
import 'models/export_opportunity.dart';
import 'models/export_ready_product.dart';
import 'models/export_requirement_guide.dart';
import 'widgets/export_buyer_card.dart';
import 'widgets/export_card.dart';
import 'widgets/export_ready_product_card.dart';
import 'widgets/export_requirement_card.dart';
import 'widgets/export_section_header.dart';
import 'widgets/export_segmented_control.dart';

enum _ExportHubSection {
  opportunities,
  buyers,
  requirements,
  readyProducts,
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _verifiedOnly = false;
  _ExportHubSection _selectedSection = _ExportHubSection.opportunities;

  static const double _horizontalPadding = 16;
  static const double _sectionGap = 24;
  static const double _cardRadius = 18;
  static const double _innerSectionGap = 14;
  static const double _featuredRailHeight = 304;

  static const List<String> _sectionLabels = <String>[
    'Opportunities',
    'Buyers',
    'Requirements',
    'Ready Products',
  ];

  static const List<ExportOpportunity> _mockOpportunities = <ExportOpportunity>[
    ExportOpportunity(
      id: 'exp_1',
      commodity: 'Rice',
      country: 'Saudi Arabia',
      city: 'Jeddah',
      buyerType: 'Distributor',
      demand: '100 Tons',
      priceHint: 'Preference for IRRI and 1121 grades',
      verified: true,
      freshnessHours: 2,
      certificationsRequired: <String>['Halal', 'ISO 22000', 'Fumigation'],
      featured: true,
    ),
    ExportOpportunity(
      id: 'exp_2',
      commodity: 'Wheat Flour',
      country: 'UAE',
      city: 'Dubai',
      buyerType: 'Importer',
      demand: '40 Tons',
      priceHint: 'Containerized lots preferred with stable monthly supply',
      verified: true,
      freshnessHours: 3,
      certificationsRequired: <String>['ISO 22000', 'Fumigation'],
      featured: true,
    ),
    ExportOpportunity(
      id: 'exp_3',
      commodity: 'Mango',
      country: 'UK',
      city: 'London',
      buyerType: 'Retail Chain',
      demand: 'Seasonal pallets',
      priceHint: 'Chaunsa and Sindhri accepted with cold-chain handling',
      verified: true,
      freshnessHours: 7,
      certificationsRequired: <String>['GlobalG.A.P', 'BRC'],
      featured: true,
    ),
    ExportOpportunity(
      id: 'exp_4',
      commodity: 'Kinnow',
      country: 'UAE',
      city: 'Dubai',
      buyerType: 'Importer',
      demand: '30 Tons',
      priceHint: 'Strong preference for uniform Brix and size grading',
      verified: true,
      freshnessHours: 6,
      certificationsRequired: <String>['Phytosanitary'],
      featured: true,
    ),
    ExportOpportunity(
      id: 'exp_5',
      commodity: 'Potato',
      country: 'Oman',
      city: 'Muscat',
      buyerType: 'Wholesaler',
      demand: '40 Tons',
      priceHint: 'Washed and export-grade sorting requested',
      verified: true,
      freshnessHours: 10,
      certificationsRequired: <String>['Phytosanitary'],
      featured: false,
    ),
    ExportOpportunity(
      id: 'exp_6',
      commodity: 'Sesame',
      country: 'China',
      city: 'Guangzhou',
      buyerType: 'Processor',
      demand: 'Bulk container',
      priceHint: 'Purity and moisture specs required per contract lot',
      verified: true,
      freshnessHours: 4,
      certificationsRequired: <String>['SGS Test Report'],
      featured: false,
    ),
    ExportOpportunity(
      id: 'exp_7',
      commodity: 'Pink Salt',
      country: 'Germany',
      city: 'Hamburg',
      buyerType: 'Specialty Retailer',
      demand: '20 Tons',
      priceHint: 'Fine and coarse grind packs both accepted',
      verified: false,
      freshnessHours: 9,
      certificationsRequired: <String>[
        'Food Grade Analysis',
        'EU Label Compliance',
      ],
      featured: true,
    ),
  ];

  static const List<ExportBuyerProfile> _mockBuyers = <ExportBuyerProfile>[
    ExportBuyerProfile(
      id: 'buyer_1',
      companyName: 'Al Noor Grain Trading',
      country: 'UAE',
      city: 'Dubai',
      buyerType: 'Importer',
      commodities: <String>['Wheat Flour', 'Rice'],
      verified: true,
      lastActiveHours: 2,
      minOrder: '40 Tons',
      certificationsPreferred: <String>['ISO 22000', 'Fumigation'],
      summary: 'Regular container buyer focused on consistent food-grade lots.',
    ),
    ExportBuyerProfile(
      id: 'buyer_2',
      companyName: 'Riyadh Pantry Distribution',
      country: 'Saudi Arabia',
      city: 'Riyadh',
      buyerType: 'Distributor',
      commodities: <String>['Rice'],
      verified: true,
      lastActiveHours: 4,
      minOrder: '80 Tons',
      certificationsPreferred: <String>['Halal', 'ISO 22000'],
      summary: 'Seeks repeat rice programs for retail and horeca channels.',
    ),
    ExportBuyerProfile(
      id: 'buyer_3',
      companyName: 'Thames Fresh Retail',
      country: 'UK',
      city: 'London',
      buyerType: 'Retail Chain',
      commodities: <String>['Mango'],
      verified: true,
      lastActiveHours: 6,
      minOrder: 'Seasonal pallets',
      certificationsPreferred: <String>['GlobalG.A.P', 'BRC'],
      summary: 'Looking for premium mango programs with cold-chain discipline.',
    ),
    ExportBuyerProfile(
      id: 'buyer_4',
      companyName: 'Muscat Fresh Wholesale',
      country: 'Oman',
      city: 'Muscat',
      buyerType: 'Wholesaler',
      commodities: <String>['Potato'],
      verified: true,
      lastActiveHours: 9,
      minOrder: '35 Tons',
      certificationsPreferred: <String>['Phytosanitary'],
      summary: 'Prefers washed, graded potato shipments on reliable schedules.',
    ),
    ExportBuyerProfile(
      id: 'buyer_5',
      companyName: 'Guangzhou Sesame Processing Co.',
      country: 'China',
      city: 'Guangzhou',
      buyerType: 'Processor',
      commodities: <String>['Sesame'],
      verified: true,
      lastActiveHours: 5,
      minOrder: '1 container',
      certificationsPreferred: <String>['SGS Test Report'],
      summary: 'Interested in moisture-stable sesame lots for processing runs.',
    ),
    ExportBuyerProfile(
      id: 'buyer_6',
      companyName: 'Nordmarkt Specialty Imports',
      country: 'Germany',
      city: 'Hamburg',
      buyerType: 'Specialty Importer',
      commodities: <String>['Pink Salt'],
      verified: false,
      lastActiveHours: 8,
      minOrder: '20 Tons',
      certificationsPreferred: <String>[
        'Food Grade Analysis',
        'EU Label Compliance',
      ],
      summary: 'Sources premium pink salt formats for specialty retail shelves.',
    ),
  ];

  static const List<ExportRequirementGuide> _mockRequirements =
      <ExportRequirementGuide>[
    ExportRequirementGuide(
      id: 'req_1',
      country: 'Saudi Arabia',
      commodity: 'Rice',
      keyRequirements: <String>[
        'Buyer-approved grain specs and broken percentage limits',
        'Arabic-ready labeling and shipment documentation',
        'Lot traceability aligned with food import review',
      ],
      preferredCertifications: <String>['Halal', 'ISO 22000'],
      packagingNotes: 'Retail-ready or distributor bags with clear labeling.',
      statusNote: 'Guidance only. Buyer pack specs often decide final approval.',
    ),
    ExportRequirementGuide(
      id: 'req_2',
      country: 'UAE',
      commodity: 'Wheat Flour',
      keyRequirements: <String>[
        'Stable flour specs with consistent protein and ash profile',
        'Commercial invoice and origin documents matched to shipment lot',
        'Clean palletization and moisture-safe storage before dispatch',
      ],
      preferredCertifications: <String>['ISO 22000', 'Fumigation'],
      packagingNotes: '25 kg and 50 kg export sacks remain common.',
      statusNote: 'Guidance only. Final importer specs vary by application use.',
    ),
    ExportRequirementGuide(
      id: 'req_3',
      country: 'UK',
      commodity: 'Mango',
      keyRequirements: <String>[
        'Cold-chain discipline from packhouse to arrival',
        'Uniform size grading and visual quality standards',
        'Traceability and buyer-approved residue management practices',
      ],
      preferredCertifications: <String>['GlobalG.A.P', 'BRC'],
      packagingNotes:
          'Ventilated cartons with export-grade cushioning are preferred.',
      statusNote: 'Guidance only. SPS acceptance and retailer QC remain buyer-specific.',
    ),
    ExportRequirementGuide(
      id: 'req_4',
      country: 'UAE',
      commodity: 'Kinnow',
      keyRequirements: <String>[
        'Uniform color, Brix, and size sorting across cartons',
        'Clean fruit finish with export-grade wax or polish where requested',
        'Shipment timing aligned with market arrival windows',
      ],
      preferredCertifications: <String>['Phytosanitary'],
      packagingNotes: 'Ventilated citrus cartons with consistent count packs.',
      statusNote: 'Guidance only. Importer appearance standards can be strict.',
    ),
    ExportRequirementGuide(
      id: 'req_5',
      country: 'Oman',
      commodity: 'Potato',
      keyRequirements: <String>[
        'Washed and graded export lots with low visible damage',
        'Stable bagging format and dispatch schedule by buyer program',
        'Shipment records aligned to lot and farm-source traceability',
      ],
      preferredCertifications: <String>['Phytosanitary'],
      packagingNotes: 'Mesh bags or buyer-branded sacks are commonly requested.',
      statusNote: 'Guidance only. Confirm final grade and packing terms with buyer.',
    ),
    ExportRequirementGuide(
      id: 'req_6',
      country: 'China',
      commodity: 'Sesame',
      keyRequirements: <String>[
        'Purity and moisture specs verified per shipment lot',
        'Contamination control and sealed bulk handling',
        'Clear test-report linkage to each commercial container',
      ],
      preferredCertifications: <String>['SGS Test Report'],
      packagingNotes: 'Bulk container loads or lined bags based on processor needs.',
      statusNote: 'Guidance only. Final processor specs drive acceptance.',
    ),
  ];

  static const List<ExportReadyProduct> _mockReadyProducts =
      <ExportReadyProduct>[
    ExportReadyProduct(
      id: 'prod_1',
      commodity: 'Rice',
      suggestedMarkets: <String>['Saudi Arabia', 'UAE', 'Qatar'],
      idealSupplyFormat: 'Containerized bulk and private-label retail programs',
      packagingType: '5 kg, 10 kg, 25 kg, and distributor sacks',
      shelfLifeNote:
          'Strong readiness when moisture and bag integrity stay controlled.',
      readinessLevel: 'strong',
    ),
    ExportReadyProduct(
      id: 'prod_2',
      commodity: 'Wheat Flour',
      suggestedMarkets: <String>['UAE', 'Oman'],
      idealSupplyFormat: 'Food-service and importer-grade sacks',
      packagingType: '25 kg and 50 kg sacks with moisture-safe liner options',
      shelfLifeNote: 'Moderate-to-strong readiness with stable milling specs.',
      readinessLevel: 'strong',
    ),
    ExportReadyProduct(
      id: 'prod_3',
      commodity: 'Mango',
      suggestedMarkets: <String>['UK', 'UAE'],
      idealSupplyFormat: 'Seasonal premium cartons with cold-chain support',
      packagingType: 'Ventilated fruit cartons with protective inserts',
      shelfLifeNote: 'Strong readiness only with disciplined cold-chain execution.',
      readinessLevel: 'moderate',
    ),
    ExportReadyProduct(
      id: 'prod_4',
      commodity: 'Kinnow',
      suggestedMarkets: <String>['UAE', 'Malaysia'],
      idealSupplyFormat: 'Count-based citrus carton programs',
      packagingType: 'Ventilated citrus cartons',
      shelfLifeNote:
          'Moderate readiness depending on sorting and appearance control.',
      readinessLevel: 'moderate',
    ),
    ExportReadyProduct(
      id: 'prod_5',
      commodity: 'Potato',
      suggestedMarkets: <String>['Oman', 'UAE'],
      idealSupplyFormat: 'Washed and graded wholesale sacks',
      packagingType: 'Mesh bags and export sacks',
      shelfLifeNote:
          'Moderate readiness with dependable grading and transit planning.',
      readinessLevel: 'moderate',
    ),
    ExportReadyProduct(
      id: 'prod_6',
      commodity: 'Sesame',
      suggestedMarkets: <String>['China', 'Middle East'],
      idealSupplyFormat: 'Bulk processor lots and container shipments',
      packagingType: 'Lined bags or bulk container loads',
      shelfLifeNote:
          'Strong readiness where purity and moisture controls are proven.',
      readinessLevel: 'strong',
    ),
    ExportReadyProduct(
      id: 'prod_7',
      commodity: 'Pink Salt',
      suggestedMarkets: <String>['Germany', 'UAE'],
      idealSupplyFormat: 'Food-service and specialty retail packs',
      packagingType: 'Retail jars, pouches, and food-service bags',
      shelfLifeNote:
          'Basic-to-moderate readiness depending on packaging compliance.',
      readinessLevel: 'basic',
    ),
  ];

  List<ExportOpportunity> get _sortedOpportunities {
    final list = List<ExportOpportunity>.from(_mockOpportunities);
    list.sort((a, b) {
      final tierCompare = _tierRank(a.commodity).compareTo(_tierRank(b.commodity));
      if (tierCompare != 0) return tierCompare;

      final verifiedCompare = _verifiedRank(a.verified).compareTo(
        _verifiedRank(b.verified),
      );
      if (verifiedCompare != 0) return verifiedCompare;

      final freshnessCompare = a.freshnessHours.compareTo(b.freshnessHours);
      if (freshnessCompare != 0) return freshnessCompare;

      return a.commodity.compareTo(b.commodity);
    });
    return list;
  }

  List<ExportOpportunity> get _featuredOpportunities {
    final list = _sortedOpportunities
        .where((opportunity) => opportunity.featured)
        .toList(growable: false);
    final sortedFeatured = List<ExportOpportunity>.from(list)
      ..sort((a, b) {
        final featuredCompare = _featuredRank(a.featured).compareTo(
          _featuredRank(b.featured),
        );
        if (featuredCompare != 0) return featuredCompare;

        final tierCompare = _tierRank(a.commodity).compareTo(_tierRank(b.commodity));
        if (tierCompare != 0) return tierCompare;

        final verifiedCompare = _verifiedRank(a.verified).compareTo(
          _verifiedRank(b.verified),
        );
        if (verifiedCompare != 0) return verifiedCompare;

        final freshnessCompare = a.freshnessHours.compareTo(b.freshnessHours);
        if (freshnessCompare != 0) return freshnessCompare;

        return a.commodity.compareTo(b.commodity);
      });
    return sortedFeatured.take(5).toList(growable: false);
  }

  List<ExportBuyerProfile> get _sortedBuyers {
    final list = List<ExportBuyerProfile>.from(_mockBuyers);
    list.sort((a, b) {
      final verifiedCompare = _verifiedRank(a.verified).compareTo(
        _verifiedRank(b.verified),
      );
      if (verifiedCompare != 0) return verifiedCompare;

      final commodityCompare = _buyerPriorityTier(a).compareTo(
        _buyerPriorityTier(b),
      );
      if (commodityCompare != 0) return commodityCompare;

      final freshnessCompare = a.lastActiveHours.compareTo(b.lastActiveHours);
      if (freshnessCompare != 0) return freshnessCompare;

      return a.companyName.compareTo(b.companyName);
    });
    return list;
  }

  List<ExportRequirementGuide> get _sortedRequirements {
    final list = List<ExportRequirementGuide>.from(_mockRequirements);
    list.sort((a, b) {
      final tierCompare = _tierRank(a.commodity).compareTo(_tierRank(b.commodity));
      if (tierCompare != 0) return tierCompare;
      return a.country.compareTo(b.country);
    });
    return list;
  }

  List<ExportReadyProduct> get _sortedReadyProducts {
    final list = List<ExportReadyProduct>.from(_mockReadyProducts);
    list.sort((a, b) {
      final tierCompare = _tierRank(a.commodity).compareTo(_tierRank(b.commodity));
      if (tierCompare != 0) return tierCompare;

      final readinessCompare = _readinessRank(a.readinessLevel).compareTo(
        _readinessRank(b.readinessLevel),
      );
      if (readinessCompare != 0) return readinessCompare;

      return a.commodity.compareTo(b.commodity);
    });
    return list;
  }

  int _tierRank(String commodityRaw) {
    final commodity = commodityRaw.trim().toLowerCase();
    if (commodity == 'rice' || commodity.contains('wheat')) {
      return 1;
    }
    if (commodity.contains('mango') || commodity.contains('kinnow')) {
      return 2;
    }
    if (commodity.contains('potato') ||
        commodity.contains('onion') ||
        commodity.contains('sesame')) {
      return 3;
    }
    if (commodity.contains('pink salt')) {
      return 4;
    }
    return 4;
  }

  int _verifiedRank(bool isVerified) => isVerified ? 0 : 1;
  int _featuredRank(bool isFeatured) => isFeatured ? 0 : 1;

  int _readinessRank(String readinessLevel) {
    switch (readinessLevel.toLowerCase()) {
      case 'strong':
        return 0;
      case 'moderate':
        return 1;
      default:
        return 2;
    }
  }

  int _buyerPriorityTier(ExportBuyerProfile profile) {
    return profile.commodities
        .map(_tierRank)
        .fold<int>(4, (best, current) => current < best ? current : best);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                _horizontalPadding,
                16,
                _horizontalPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Export Opportunities',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Local supply se global buyer tak',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ExportSegmentedControl(
                      labels: _sectionLabels,
                      selectedIndex: _selectedSection.index,
                      onSelected: (index) {
                        setState(
                          () => _selectedSection = _ExportHubSection.values[index],
                        );
                      },
                    ),
                    const SizedBox(height: _sectionGap),
                  ],
                ),
              ),
            ),
            ..._buildSegmentSlivers(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSegmentSlivers() {
    switch (_selectedSection) {
      case _ExportHubSection.opportunities:
        return _buildOpportunitySlivers();
      case _ExportHubSection.buyers:
        return _buildBuyerSlivers();
      case _ExportHubSection.requirements:
        return _buildRequirementSlivers();
      case _ExportHubSection.readyProducts:
        return _buildReadyProductSlivers();
    }
  }

  List<Widget> _buildOpportunitySlivers() {
    final sorted = _sortedOpportunities;
    final featured = _featuredOpportunities;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildFilterBar(),
              const SizedBox(height: _sectionGap),
              const ExportSectionHeader(
                title: 'Featured Opportunities',
                subtitle: 'Curated high-priority leads for Pakistani exporters',
              ),
              const SizedBox(height: _innerSectionGap),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(_cardRadius),
                  border: Border.all(
                    color: AppColors.accentGold.withValues(alpha: 0.22),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _featuredRailHeight),
                  child: SizedBox(
                    height: _featuredRailHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: featured.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return ExportCard(
                          opportunity: featured[index],
                          compact: true,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _sectionGap),
              const ExportSectionHeader(
                title: 'All Opportunities',
                subtitle: 'Sorted opportunities with trust and freshness signals',
              ),
              const SizedBox(height: _innerSectionGap),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return ExportCard(opportunity: sorted[index]);
          }, childCount: sorted.length),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 10, _horizontalPadding, 20),
        sliver: SliverToBoxAdapter(
          child: Text(
            'Curated opportunities for Pakistani exporters',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildBuyerSlivers() {
    final buyers = _sortedBuyers;

    return <Widget>[
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 14),
        sliver: SliverToBoxAdapter(
          child: ExportSectionHeader(
            title: 'Verified Buyers',
            subtitle: 'High-trust buyers actively sourcing from Pakistan',
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return ExportBuyerCard(
              profile: buyers[index],
              onViewBuyer: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExportBuyerDetailScreen(
                      profile: buyers[index],
                    ),
                  ),
                );
              },
            );
          }, childCount: buyers.length),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 10, _horizontalPadding, 20),
        sliver: SliverToBoxAdapter(
          child: Text(
            'Buyer discovery only. Final commercial checks stay buyer-specific.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildRequirementSlivers() {
    final guides = _sortedRequirements;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDisclaimerBanner(
                title: 'Guidance only',
                body:
                    'Always confirm final import and SPS requirements with official authorities and buyers.',
              ),
              const SizedBox(height: _sectionGap),
              const ExportSectionHeader(
                title: 'Country Requirements',
                subtitle: 'Practical guidance for market-ready documentation and handling',
              ),
              const SizedBox(height: _innerSectionGap),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return ExportRequirementCard(guide: guides[index]);
          }, childCount: guides.length),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 10, _horizontalPadding, 20),
        sliver: SliverToBoxAdapter(
          child: Text(
            'Confirm final SPS, customs, certification, and buyer-specific requirements with official sources.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildReadyProductSlivers() {
    final products = _sortedReadyProducts;

    return <Widget>[
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 14),
        sliver: SliverToBoxAdapter(
          child: ExportSectionHeader(
            title: 'Export Ready Products',
            subtitle: 'Readiness signals by commodity, market fit, and supply format',
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return ExportReadyProductCard(product: products[index]);
          }, childCount: products.length),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, 10, _horizontalPadding, 20),
        sliver: SliverToBoxAdapter(
          child: Text(
            'Readiness signals are directional and help prioritize where export prep should start.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildDisclaimerBanner({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.softGlassBorder.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.softGlassBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _filterChip('Commodity'),
          _filterChip('Country'),
          _filterChip('MOQ'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Verified only',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Transform.scale(
                scale: 0.85,
                child: Switch.adaptive(
                  value: _verifiedOnly,
                  onChanged: (value) => setState(() => _verifiedOnly = value),
                  activeThumbColor: AppColors.accentGold,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.secondaryText,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.1,
        ),
      ),
    );
  }
}
