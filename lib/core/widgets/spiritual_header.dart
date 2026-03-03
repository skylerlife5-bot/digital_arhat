import 'package:flutter/material.dart';

class SpiritualHeader extends StatelessWidget {
  const SpiritualHeader({
    super.key,
    this.backgroundColor,
    this.borderColor,
  });

  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text(
            '�`�}ا أ�}�`�ُ�!�}ا ا���}ذِ�`� �} آ�&�}� ُ��ا ��}ا ت�}خُ��� ُ��ا ا����}�!�} ���}ا�ر��}سُ����} ���}ت�}خُ��� ُ��ا أ�}�&�}ا� �}اتُِْ�&� ���}أ�}� �تُ�&� ت�}ع���}�&ُ��� �}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFE082),
              fontSize: 19,
              height: 1.7,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Aye imaan walon! Allah aur uskay Rasool ki amanat mein khayanat na karo, aur na hi apni apsi amanaton mein khayanat karo halankay tum jantay ho. (Surah Al-Anfal: 27)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Amanat mein khayanat na karein. Ye Allah ka hukm hai aur Digital Arhat ki bunyad hai.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB2DFDB),
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

