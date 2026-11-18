import 'package:material_ui/material_ui.dart';

/// Shared Stage 0..[maxStage] pill breakdown for a Station 2 POP anatomical
/// compartment (Anterior Wall, Middle/Apical Compartment, or Posterior Wall).
class PopCompartmentStagePills extends StatelessWidget {
  final Map<int, int> stageCounts;
  final int maxStage;
  final double spacing;

  const PopCompartmentStagePills({
    super.key,
    required this.stageCounts,
    this.maxStage = 3,
    this.spacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (int s = 0; s <= maxStage; s++)
          _buildStagePill(s, stageCounts[s] ?? 0),
      ],
    );
  }

  Widget _buildStagePill(int stage, int count) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;

    if (count <= 0) {
      bgColor = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFE2E8F0);
      textColor = const Color(0xFF94A3B8);
    } else if (stage == 0) {
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      textColor = const Color(0xFF047857);
    } else if (stage == 1) {
      bgColor = const Color(0xFFECFEFF);
      borderColor = const Color(0xFFA5F3FC);
      textColor = const Color(0xFF0E7490);
    } else if (stage == 2) {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFDE68A);
      textColor = const Color(0xFFB45309);
    } else {
      bgColor = const Color(0xFFFEE2E2);
      borderColor = const Color(0xFFFECACA);
      textColor = const Color(0xFFB91C1C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        'St $stage: $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: count > 0 ? FontWeight.bold : FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}
