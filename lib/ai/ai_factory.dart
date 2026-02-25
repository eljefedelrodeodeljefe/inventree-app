import "package:inventree/ai/ai_service.dart";
import "package:inventree/ai/claude_service.dart";
import "package:inventree/ai/gemini_service.dart";
import "package:inventree/ai/openai_service.dart";
import "package:inventree/preferences.dart";

/*
 * Factory class to create the appropriate AI service based on user settings.
 */
class AIServiceFactory {
  /*
   * Create an AI service instance based on the current settings.
   * Returns null if AI is not enabled or not properly configured.
   */
  static Future<AIService?> create() async {
    final settings = InvenTreeSettingsManager();

    final bool enabled = await settings.getBool(INV_AI_ENABLED, false);
    if (!enabled) return null;

    final int provider =
        await settings.getValue(INV_AI_PROVIDER, AI_PROVIDER_CLAUDE) as int;

    switch (provider) {
      case AI_PROVIDER_CLAUDE:
        final apiKey =
            await settings.getValue(INV_AI_CLAUDE_API_KEY, "") as String;
        if (apiKey.isEmpty) return null;
        final model =
            await settings.getValue(INV_AI_CLAUDE_MODEL, "") as String;
        return ClaudeService(
          apiKey: apiKey,
          model: model.isNotEmpty ? model : null,
        );

      case AI_PROVIDER_GEMINI:
        final apiKey =
            await settings.getValue(INV_AI_GEMINI_API_KEY, "") as String;
        if (apiKey.isEmpty) return null;
        final model =
            await settings.getValue(INV_AI_GEMINI_MODEL, "") as String;
        return GeminiService(
          apiKey: apiKey,
          model: model.isNotEmpty ? model : null,
        );

      case AI_PROVIDER_OPENAI:
        final apiKey =
            await settings.getValue(INV_AI_OPENAI_API_KEY, "") as String;
        if (apiKey.isEmpty) return null;
        final model =
            await settings.getValue(INV_AI_OPENAI_MODEL, "") as String;
        return OpenAIService(
          apiKey: apiKey,
          model: model.isNotEmpty ? model : null,
        );

      default:
        return null;
    }
  }
}
