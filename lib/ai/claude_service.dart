import "dart:convert";
import "dart:io";

import "package:inventree/ai/ai_service.dart";
import "package:inventree/ai/claude_helpers.dart";
import "package:inventree/helpers.dart";
import "package:inventree/inventree/sentry.dart";

/*
 * Represents a Claude model available via the API.
 */
class ClaudeModel {
  ClaudeModel({
    required this.id,
    required this.displayName,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String createdAt;
}

/*
 * AI service implementation using Claude (Anthropic) multimodal API.
 */
class ClaudeService extends AIService {
  ClaudeService({required this.apiKey, String? model})
    : model = model ?? defaultModel;

  final String apiKey;
  final String model;

  static const String _baseUrl = "api.anthropic.com";
  static const String defaultModel = "claude-sonnet-4-20250514";
  static const String _apiVersion = "2023-06-01";

  @override
  String get providerName => "Claude";

  /*
   * Fetch available models from the Anthropic API.
   */
  static Future<List<ClaudeModel>> listModels(String apiKey) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final request = await client.getUrl(Uri.https(_baseUrl, "/v1/models"));

    request.headers.set("x-api-key", apiKey);
    request.headers.set("anthropic-version", _apiVersion);

    final response = await request.close().timeout(const Duration(seconds: 15));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode != 200) {
      throw Exception("Failed to list models: HTTP ${response.statusCode}");
    }

    final data = json.decode(responseBody) as Map<String, dynamic>;
    final modelsData = data["data"] as List<dynamic>? ?? [];

    List<ClaudeModel> models = [];
    for (final m in modelsData) {
      if (m is Map<String, dynamic>) {
        models.add(
          ClaudeModel(
            id: m["id"] as String? ?? "",
            displayName:
                m["display_name"] as String? ?? m["id"] as String? ?? "",
            createdAt: m["created_at"] as String? ?? "",
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

    // Determine media type from file extension
    final ext = imageFile.path.split(".").last.toLowerCase();
    String mediaType;
    switch (ext) {
      case "png":
        mediaType = "image/png";
      case "gif":
        mediaType = "image/gif";
      case "webp":
        mediaType = "image/webp";
      default:
        mediaType = "image/jpeg";
    }

    final requestBody = {
      "model": model,
      "max_tokens": 1024,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": mediaType,
                "data": base64Image,
              },
            },
            {
              "type": "text",
              "text": _buildPrompt(categoryNames: categoryNames),
            },
          ],
        },
      ],
    };

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.postUrl(Uri.https(_baseUrl, "/v1/messages"));

      request.headers.set("content-type", "application/json; charset=utf-8");
      request.headers.set("x-api-key", apiKey);
      request.headers.set("anthropic-version", _apiVersion);

      request.add(utf8.encode(json.encode(requestBody)));

      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );

      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        debug("Claude API error: ${response.statusCode} - $responseBody");
        throw Exception(_extractApiError(responseBody, response.statusCode));
      }

      final responseData = json.decode(responseBody) as Map<String, dynamic>;
      return _parseResponse(responseData);
    } catch (e, stackTrace) {
      sentryReportError("ClaudeService.analyzePartImage", e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<bool> testConnection() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final requestBody = {
      "model": model,
      "max_tokens": 32,
      "messages": [
        {"role": "user", "content": "Reply with just the word OK."},
      ],
    };

    final request = await client.postUrl(Uri.https(_baseUrl, "/v1/messages"));

    request.headers.set("content-type", "application/json");
    request.headers.set("x-api-key", apiKey);
    request.headers.set("anthropic-version", _apiVersion);

    request.write(json.encode(requestBody));

    final response = await request.close().timeout(const Duration(seconds: 15));

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200) {
      return true;
    }

    // Extract error message from API response
    String errorMsg = "HTTP ${response.statusCode}";
    try {
      final errorData = json.decode(responseBody) as Map<String, dynamic>;
      final apiError = errorData["error"] as Map<String, dynamic>?;
      if (apiError != null) {
        errorMsg = apiError["message"] as String? ?? errorMsg;
      }
    } catch (_) {
      // Use the raw status code message
    }

    throw Exception(errorMsg);
  }

  @override
  Future<AIStockCountResult> analyzeStockCount(
    File imageFile, {
    String? partName,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // Determine media type from file extension
    final ext = imageFile.path.split(".").last.toLowerCase();
    String mediaType;
    switch (ext) {
      case "png":
        mediaType = "image/png";
      case "gif":
        mediaType = "image/gif";
      case "webp":
        mediaType = "image/webp";
      default:
        mediaType = "image/jpeg";
    }

    final requestBody = {
      "model": model,
      "max_tokens": 1024,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": mediaType,
                "data": base64Image,
              },
            },
            {
              "type": "text",
              "text": _buildStockCountPrompt(partName: partName),
            },
          ],
        },
      ],
    };

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.postUrl(Uri.https(_baseUrl, "/v1/messages"));

      request.headers.set("content-type", "application/json; charset=utf-8");
      request.headers.set("x-api-key", apiKey);
      request.headers.set("anthropic-version", _apiVersion);

      request.add(utf8.encode(json.encode(requestBody)));

      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );

      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        debug("Claude API error: ${response.statusCode} - $responseBody");
        throw Exception(_extractApiError(responseBody, response.statusCode));
      }

      final responseData = json.decode(responseBody) as Map<String, dynamic>;
      return _parseStockCountResponse(responseData);
    } catch (e, stackTrace) {
      sentryReportError("ClaudeService.analyzeStockCount", e, stackTrace);
      rethrow;
    }
  }

  String _buildStockCountPrompt({String? partName}) =>
      buildStockCountPrompt(partName: partName);

  AIStockCountResult _parseStockCountResponse(
    Map<String, dynamic> responseData,
  ) => parseStockCountResponse(responseData);

  String _buildPrompt({List<String>? categoryNames}) =>
      buildPartAnalysisPrompt(categoryNames: categoryNames);

  AIPartResult _parseResponse(Map<String, dynamic> responseData) =>
      parsePartAnalysisResponse(responseData);

  /// Extract a human-readable error message from an Anthropic API error response.
  String _extractApiError(String responseBody, int statusCode) {
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
    return "Claude API returned status $statusCode";
  }
}
