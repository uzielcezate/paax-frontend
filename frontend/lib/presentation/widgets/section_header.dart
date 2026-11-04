import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import 'paax_pill.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const SectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // V4 §4: headings share the floating bars' horizontal inset.
      padding: EdgeInsets.fromLTRB(
          PaaxLayout.contentHorizontalInset(context),
          Responsive.value(context, mobile: 24, tablet: 32),
          PaaxLayout.contentHorizontalInset(context),
          Responsive.value(context, mobile: 16, tablet: 20)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
               fontSize: Responsive.fontSize(context, 24, min: 20, max: 32)
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                "See all",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.primaryEnd, 
                  fontWeight: FontWeight.bold,
                  fontSize: Responsive.fontSize(context, 14, min: 12, max: 16)
                ),
              ),
            ),
        ],
      ),
    );
  }
}
