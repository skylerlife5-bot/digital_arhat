import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class ExportSegmentedControl extends StatelessWidget {
  const ExportSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const selectedStyle = TextStyle(
      color: AppColors.accentGold,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    const unselectedStyle = TextStyle(
      color: AppColors.primaryText,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    double measureLabelWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(style: unselectedStyle, text: text),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.softGlassBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPillPadding = 24.0;
          const interItemSpacing = 6.0;

          final minPillWidths = labels
              .map(
                (label) =>
                    (measureLabelWidth(label) + horizontalPillPadding).ceilToDouble(),
              )
              .toList(growable: false);

          final spacingWidth = (labels.length - 1) * interItemSpacing;
          final widestPill = minPillWidths.fold<double>(0, (a, b) => a > b ? a : b);
          final equalItemWidth = (constraints.maxWidth - spacingWidth) / labels.length;
          final canShowWithoutScroll = equalItemWidth >= widestPill;

          final children = List<Widget>.generate(labels.length, (index) {
            final selected = index == selectedIndex;
            return Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : interItemSpacing,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    constraints: BoxConstraints(
                      minHeight: 42,
                      minWidth: canShowWithoutScroll
                          ? equalItemWidth
                          : minPillWidths[index],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accentGold.withValues(alpha: 0.2)
                          : AppColors.background.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: selected
                            ? AppColors.accentGold.withValues(alpha: 0.38)
                            : AppColors.softGlassBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        labels[index],
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: selected ? selectedStyle : unselectedStyle,
                      ),
                    ),
                  ),
                ),
              ),
            );
          });

          if (canShowWithoutScroll) {
            return Row(children: children);
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          );
        },
      ),
    );
  }
}
