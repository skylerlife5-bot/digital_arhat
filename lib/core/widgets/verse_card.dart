import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VerseCard extends StatelessWidget {
  const VerseCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '���}أ�}���فُ��ا ا��ْ�}�`���} ���}ا���&ِ�`ز�}ا� �} بِا���ِس�طِ',
            textAlign: TextAlign.right,
            style: GoogleFonts.notoNaskhArabic(
              color: const Color(0xFFFFD700),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ا��ر ا� صاف ک� ساتھ � اپ ت��� پ��را کر���',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'Jameel Noori',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Surah Al-An\'am: 152',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

