import 'package:digital_arhat/services/ai_generative_service.dart';

Future<void> main() async {
  final service = AIGenerativeService();
  try {
    final result = await service.checkAiConnectivity();
    // ignore: avoid_print
    print('AI_CONNECTIVITY_SUCCESS: $result');
  } catch (e) {
    // ignore: avoid_print
    print('AI_CONNECTIVITY_FAILURE: $e');
  }
}
