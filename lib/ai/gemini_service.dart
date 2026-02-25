import "dart:convert";
import "dart:io";

import "package:inventree/ai/ai_service.dart";
import "package:inventree/ai/claude_helpers.dart";
import "package:inventree/helpers.dart";
import "package:inventree/inventree/sentry.dart";

/*
 * Represents a Gemini model available via the API.
 */
class GeminiModel {
  GeminiModel({required this.name, required this.displayName});

  final String name;
  final String displayName;
}

/*
 * AI service implementation using Gemini (Google) multimodal API.
 */
class GeminiService extends AIService {
  GeminiService({required this.apiKey, String? model})
    : model = model ?? defaultModel;

  final String apiKey;
  final String model;

  static const String _baseUrl = "generativelanguage.googleapis.com";
  static const String defaultModel = "gemini-2.5-flash";

  @override
  String get providerName => "Gemini";

  /*
   * Fetch available models from the Gemini API.
   */
  static Future<List<GeminiModel>> listModels(String apiKey) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final request = await client.getUrl(Uri.https(_baseUrl, "/v1beta/models"));

    request.headers.set("x-goog-api-key", apiKey);

    final response = await request.close().timeout(const Duration(seconds: 15));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode != 200) {
      throw Exception(
        _extractApiErrorFromBody(responseBody, response.statusCode),
      );
    }

    final data = json.decode(responseBody) as Map<String, dynamic>;
    final modelsData = data["models"] as List<dynamic>? ?? [];

    List<GeminiModel> models = [];
    for (final m in modelsData) {
      if (m is Map<String, dynamic>) {
        final name = m["name"] as String? ?? "";
        // name is "models/gemini-2.5-flash" — strip prefix for display
        final shortName = name.startsWith("models/")
            ? name.substring("models/".length)
            : name;
        // Only include models that support generateContent
        final methods = m["supportedGenerationMethods"] as List<dynamic>? ?? [];
        if (!methods.contains("generateContent")) continue;
        models.add(
          GeminiModel(
            name: shortName,
            displayName: m["displayName"] as String? ?? shortName,
          ),
        );
      }
    }

    return models;
  }

  @override
  Future<AIPartResult> analyzePartImage(
    File imageFile, {
    List<String>? categoryNames,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final mimeType = _mimeType(imageFile.path);

    final requestBody = {
      "contents": [
        {
          "parts": [
            {
              "inline_data": {"mime_type": mimeType, "data": base64Image},
            },
            {"text": buildPartAnalysisPrompt(categoryNames: categoryNames)},
          ],
        },
      ],
    };

    try {
      final responseData = await _post(model, requestBody);
      final text = _extractText(responseData);
      return parsePartAnalysisFromText(text);
    } catch (e, stackTrace) {
      sentryReportError("GeminiService.analyzePartImage", e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<AIStockCountResult> analyzeStockCount(
    File imageFile, {
    String? partName,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final mimeType = _mimeType(imageFile.path);

    final requestBody = {
      "contents": [
        {
          "parts": [
            {
              "inline_data": {"mime_type": mimeType, "data": base64Image},
            },
            {"text": buildStockCountPrompt(partName: partName)},
          ],
        },
      ],
    };

    try {
      final responseData = await _post(model, requestBody);
      final text = _extractText(responseData);
      return parseStockCountFromText(text);
    } catch (e, stackTrace) {
      sentryReportError("GeminiService.analyzeStockCount", e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<bool> testConnection() async {
    final requestBody = {
      "contents": [
        {
          "parts": [
            {"text": "Reply with just the word OK."},
          ],
        },
      ],
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final request = await client.postUrl(
      Uri.https(_baseUrl, "/v1beta/models/$model:generateContent"),
    );

    request.headers.set("content-type", "application/json");
    request.headers.set("x-goog-api-key", apiKey);

    request.write(json.encode(requestBody));

    final response = await request.close().timeout(const Duration(seconds: 15));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200) {
      return true;
    }

    throw Exception(
      _extractApiErrorFromBody(responseBody, response.statusCode),
    );
  }

  /// Send a POST request to the Gemini generateContent endpoint.
  Future<Map<String, dynamic>> _post(
    String model,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    final request = await client.postUrl(
      Uri.https(_baseUrl, "/v1beta/models/$model:generateContent"),
    );

    request.headers.set("content-type", "application/json; charset=utf-8");
    request.headers.set("x-goog-api-key", apiKey);

    request.add(utf8.encode(json.encode(body)));

    final response = await request.close().timeout(const Duration(seconds: 60));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode != 200) {
      debug("Gemini API error: ${response.statusCode} - $responseBody");
      throw Exception(
        _extractApiErrorFromBody(responseBody, response.statusCode),
      );
    }

    return json.decode(responseBody) as Map<String, dynamic>;
  }

  /// Extract the text content from a Gemini API response.
  String _extractText(Map<String, dynamic> responseData) {
    final candidates = responseData["candidates"] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception("Empty response from Gemini");
    }

    final first = candidates[0] as Map<String, dynamic>;
    final content = first["content"] as Map<String, dynamic>?;
    if (content == null) {
      throw Exception("No content in Gemini response");
    }

    final parts = content["parts"] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception("No parts in Gemini response");
    }

    final text = (parts[0] as Map<String, dynamic>)["text"] as String?;
    if (text == null || text.isEmpty) {
      throw Exception("No text in Gemini response");
    }

    return text;
  }

  /// Determine MIME type from a file path extension.
  String _mimeType(String path) {
    final ext = path.split(".").last.toLowerCase();
    switch (ext) {
      case "png":
        return "image/png";
      case "gif":
        return "image/gif";
      case "webp":
        return "image/webp";
      default:
        return "image/jpeg";
    }
  }

  /// Extract a human-readable error from a Gemini API error response body.
  static String _extractApiErrorFromBody(String responseBody, int statusCode) {
    try {
      final errorData = json.decode(responseBody) as Map<String, dynamic>;
      final apiError = errorData["error"] as Map<String, dynamic>?;
      if (apiError != null) {
        final message = apiError["message"] as String?;
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {}
    return "Gemini API returned status $statusCode";
  }
}
