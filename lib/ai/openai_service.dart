import "dart:convert";
import "dart:io";

import "package:inventree/ai/ai_service.dart";
import "package:inventree/ai/claude_helpers.dart";
import "package:inventree/helpers.dart";
import "package:inventree/inventree/sentry.dart";

/*
 * Represents an OpenAI model available via the API.
 */
class OpenAIModel {
  OpenAIModel({required this.id});

  final String id;
}

/*
 * AI service implementation using OpenAI (GPT-4o) multimodal API.
 */
class OpenAIService extends AIService {
  OpenAIService({required this.apiKey, String? model})
    : model = model ?? defaultModel;

  final String apiKey;
  final String model;

  static const String _baseUrl = "api.openai.com";
  static const String defaultModel = "gpt-4o";

  @override
  String get providerName => "OpenAI";

  /*
   * Fetch available models from the OpenAI API.
   */
  static Future<List<OpenAIModel>> listModels(String apiKey) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final request = await client.getUrl(Uri.https(_baseUrl, "/v1/models"));

    request.headers.set("authorization", "Bearer $apiKey");

    final response = await request.close().timeout(const Duration(seconds: 15));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode != 200) {
      throw Exception(
        _extractApiErrorFromBody(responseBody, response.statusCode),
      );
    }

    final data = json.decode(responseBody) as Map<String, dynamic>;
    final modelsData = data["data"] as List<dynamic>? ?? [];

    List<OpenAIModel> models = [];
    for (final m in modelsData) {
      if (m is Map<String, dynamic>) {
        final id = m["id"] as String? ?? "";
        // Only include GPT models that support vision
        if (!id.startsWith("gpt-")) continue;
        models.add(OpenAIModel(id: id));
      }
    }

    // Sort alphabetically
    models.sort((a, b) => a.id.compareTo(b.id));

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
      "model": model,
      "max_tokens": 1024,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "image_url",
              "image_url": {"url": "data:$mimeType;base64,$base64Image"},
            },
            {
              "type": "text",
              "text": buildPartAnalysisPrompt(categoryNames: categoryNames),
            },
          ],
        },
      ],
    };

    try {
      final responseData = await _post(requestBody);
      final text = _extractText(responseData);
      return parsePartAnalysisFromText(text);
    } catch (e, stackTrace) {
      sentryReportError("OpenAIService.analyzePartImage", e, stackTrace);
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
      "model": model,
      "max_tokens": 1024,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "image_url",
              "image_url": {"url": "data:$mimeType;base64,$base64Image"},
            },
            {"type": "text", "text": buildStockCountPrompt(partName: partName)},
          ],
        },
      ],
    };

    try {
      final responseData = await _post(requestBody);
      final text = _extractText(responseData);
      return parseStockCountFromText(text);
    } catch (e, stackTrace) {
      sentryReportError("OpenAIService.analyzeStockCount", e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<bool> testConnection() async {
    final requestBody = {
      "model": model,
      "max_tokens": 32,
      "messages": [
        {"role": "user", "content": "Reply with just the word OK."},
      ],
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final request = await client.postUrl(
      Uri.https(_baseUrl, "/v1/chat/completions"),
    );

    request.headers.set("content-type", "application/json");
    request.headers.set("authorization", "Bearer $apiKey");

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

  /// Send a POST request to the OpenAI chat completions endpoint.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    final request = await client.postUrl(
      Uri.https(_baseUrl, "/v1/chat/completions"),
    );

    request.headers.set("content-type", "application/json; charset=utf-8");
    request.headers.set("authorization", "Bearer $apiKey");

    request.add(utf8.encode(json.encode(body)));

    final response = await request.close().timeout(const Duration(seconds: 60));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode != 200) {
      debug("OpenAI API error: ${response.statusCode} - $responseBody");
      throw Exception(
        _extractApiErrorFromBody(responseBody, response.statusCode),
      );
    }

    return json.decode(responseBody) as Map<String, dynamic>;
  }

  /// Extract the text content from an OpenAI chat completions response.
  String _extractText(Map<String, dynamic> responseData) {
    final choices = responseData["choices"] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception("Empty response from OpenAI");
    }

    final first = choices[0] as Map<String, dynamic>;
    final message = first["message"] as Map<String, dynamic>?;
    if (message == null) {
      throw Exception("No message in OpenAI response");
    }

    final text = message["content"] as String?;
    if (text == null || text.isEmpty) {
      throw Exception("No content in OpenAI response");
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

  /// Extract a human-readable error from an OpenAI API error response body.
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
    return "OpenAI API returned status $statusCode";
  }
}
