import "dart:convert";

import "package:inventree/ai/ai_service.dart";
import "package:inventree/helpers.dart";

/// Build the prompt for part analysis.
String buildPartAnalysisPrompt({List<String>? categoryNames}) {
  String categoryInstruction;
  if (categoryNames != null && categoryNames.isNotEmpty) {
    categoryInstruction =
        '- "category_suggestion": Pick the most appropriate category from this list: ${categoryNames.join(", ")}. If none fit, suggest a new name.';
  } else {
    categoryInstruction =
        '- "category_suggestion": The most appropriate part category name (e.g. "Fasteners", "Resistors", "Connectors")';
  }

  return """
Analyze this image of a physical part or component. Identify what the part is and provide structured data about it.

Respond ONLY with a JSON object (no markdown, no code fences) with these fields:
- "name": A concise name for the part (e.g. "M3x10 Socket Head Cap Screw")
- "description": A brief description of the part, its material, and typical use
- "keywords": Comma-separated keywords for searching (e.g. "screw,fastener,M3,socket head")
$categoryInstruction
- "is_component": true if this is a component used in assemblies, false otherwise
- "is_purchaseable": true if this is typically a purchased part, false if custom/fabricated
- "confidence": A number from 0.0 to 1.0 indicating how confident you are in the identification
- "manufacturer_name": Manufacturer or brand name if a logo or label is visible on the part or packaging (null if not visible)
- "MPN": Manufacturer part number if printed on the part or packaging (null if not visible)
- "supplier_name": Distributor or supplier if visible, e.g. Digi-Key bag, Mouser label (null if not visible)
- "SKU": Supplier part number or SKU if visible on packaging (null if not visible)
- "item_count": Number of items visible or stated on packaging (e.g. "100 pcs" on a bag means 100). Count individual items if visible, read the quantity from labels/packaging if present. null if cannot be determined.

Example response:
{"name":"M3x10 Socket Head Cap Screw","description":"Stainless steel M3x10mm socket head cap screw, commonly used in mechanical assemblies","keywords":"screw,fastener,M3,socket head,stainless steel","category_suggestion":"Fasteners","is_component":true,"is_purchaseable":true,"confidence":0.85,"manufacturer_name":null,"MPN":null,"supplier_name":null,"SKU":null,"item_count":25}""";
}

/// Build the prompt for stock counting.
String buildStockCountPrompt({String? partName}) {
  final partHint = partName != null && partName.isNotEmpty
      ? "\nThe items are expected to be: $partName"
      : "";

  return """
Count the individual items visible in this image.$partHint

Counting instructions:
- Scan the image systematically from left to right, top to bottom
- Count each individual item one by one — do not estimate or group
- Watch for partially hidden or overlapping items and include them
- Watch for items that appear separate but are actually one item (e.g. reflections)
- If items are in packaging, count only the actual items, not the packaging

Respond ONLY with a JSON object (no markdown, no code fences) with these fields:
- "count": The exact number of individual items you counted (integer)
- "confidence": A number from 0.0 to 1.0 indicating how confident you are in the count (lower if items overlap or are partially hidden)
- "description": A short description of what you counted (e.g. "12 resistors in a strip", "5 bolts on a table")

Example response:
{"count":12,"confidence":0.85,"description":"12 resistors in a strip"}""";
}

/// Parse raw AI text into an [AIPartResult].
///
/// Shared between all AI providers — strips markdown fences, decodes JSON,
/// and maps the fields to an [AIPartResult].
AIPartResult parsePartAnalysisFromText(String textContent) {
  Map<String, dynamic> parsed;
  try {
    String cleanText = textContent.trim();
    if (cleanText.startsWith("```")) {
      cleanText = cleanText.replaceFirst(RegExp(r"^```\w*\n?"), "");
      cleanText = cleanText.replaceFirst(RegExp(r"\n?```$"), "");
      cleanText = cleanText.trim();
    }
    parsed = json.decode(cleanText) as Map<String, dynamic>;
  } catch (e) {
    debug("Failed to parse AI JSON response: $textContent");
    return AIPartResult(
      name: "Unknown Part",
      description: textContent,
      rawAnalysis: textContent,
      confidence: 0.0,
    );
  }

  return AIPartResult(
    name: (parsed["name"] as String?) ?? "Unknown Part",
    description: (parsed["description"] as String?) ?? "",
    keywords: parsed["keywords"] as String?,
    categoryName: parsed["category_suggestion"] as String?,
    isComponent: parsed["is_component"] as bool?,
    isPurchaseable: parsed["is_purchaseable"] as bool?,
    rawAnalysis: textContent,
    confidence: ((parsed["confidence"] as num?) ?? 0.0).toDouble(),
    manufacturerName: parsed["manufacturer_name"] as String?,
    MPN: parsed["MPN"] as String?,
    supplierName: parsed["supplier_name"] as String?,
    SKU: parsed["SKU"] as String?,
    itemCount: (parsed["item_count"] as num?)?.toInt(),
  );
}

/// Parse a Claude API response into an [AIPartResult].
AIPartResult parsePartAnalysisResponse(Map<String, dynamic> responseData) {
  final textContent = _extractClaudeText(responseData);
  return parsePartAnalysisFromText(textContent);
}

/// Parse raw AI text into an [AIStockCountResult].
///
/// Shared between all AI providers — strips markdown fences, decodes JSON,
/// and maps the fields to an [AIStockCountResult].
AIStockCountResult parseStockCountFromText(String textContent) {
  Map<String, dynamic> parsed;
  try {
    String cleanText = textContent.trim();
    if (cleanText.startsWith("```")) {
      cleanText = cleanText.replaceFirst(RegExp(r"^```\w*\n?"), "");
      cleanText = cleanText.replaceFirst(RegExp(r"\n?```$"), "");
      cleanText = cleanText.trim();
    }
    parsed = json.decode(cleanText) as Map<String, dynamic>;
  } catch (e) {
    debug("Failed to parse AI JSON response: $textContent");
    return AIStockCountResult(
      count: 0,
      confidence: 0.0,
      description: textContent,
      rawAnalysis: textContent,
    );
  }

  return AIStockCountResult(
    count: (parsed["count"] as num?)?.toInt() ?? 0,
    confidence: ((parsed["confidence"] as num?) ?? 0.0).toDouble(),
    description: parsed["description"] as String?,
    rawAnalysis: textContent,
  );
}

/// Parse a Claude API response into an [AIStockCountResult].
AIStockCountResult parseStockCountResponse(Map<String, dynamic> responseData) {
  final textContent = _extractClaudeText(responseData);
  return parseStockCountFromText(textContent);
}

/// Extract the text content from a Claude API response envelope.
String _extractClaudeText(Map<String, dynamic> responseData) {
  final content = responseData["content"] as List<dynamic>?;
  if (content == null || content.isEmpty) {
    throw Exception("Empty response from Claude");
  }

  String? textContent;
  for (final block in content) {
    if (block is Map<String, dynamic> && block["type"] == "text") {
      textContent = block["text"] as String?;
      break;
    }
  }

  if (textContent == null || textContent.isEmpty) {
    throw Exception("No text content in Claude response");
  }

  return textContent;
}
