import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:inventree/ai/claude_helpers.dart";

void main() {
  group("buildPartAnalysisPrompt", () {
    test("no categories contains generic category instruction", () {
      final prompt = buildPartAnalysisPrompt();
      expect(prompt, contains("The most appropriate part category name"));
    });

    test("with categories contains category list", () {
      final prompt = buildPartAnalysisPrompt(categoryNames: ["Cat1", "Cat2"]);
      expect(
        prompt,
        contains(
          "Pick the most appropriate category from this list: Cat1, Cat2",
        ),
      );
    });

    test("contains required JSON fields", () {
      final prompt = buildPartAnalysisPrompt();
      expect(prompt, contains('"name"'));
      expect(prompt, contains('"description"'));
      expect(prompt, contains('"keywords"'));
      expect(prompt, contains('"item_count"'));
      expect(prompt, contains('"manufacturer_name"'));
      expect(prompt, contains('"MPN"'));
      expect(prompt, contains('"supplier_name"'));
      expect(prompt, contains('"SKU"'));
      expect(prompt, contains('"confidence"'));
      expect(prompt, contains('"is_component"'));
      expect(prompt, contains('"is_purchaseable"'));
      expect(prompt, contains('"category_suggestion"'));
    });
  });

  group("buildStockCountPrompt", () {
    test("no partName has no hint line", () {
      final prompt = buildStockCountPrompt();
      expect(prompt, isNot(contains("The items are expected to be:")));
    });

    test("with partName contains hint", () {
      final prompt = buildStockCountPrompt(partName: "M3 Bolt");
      expect(prompt, contains("The items are expected to be: M3 Bolt"));
    });

    test("contains required JSON fields", () {
      final prompt = buildStockCountPrompt();
      expect(prompt, contains('"count"'));
      expect(prompt, contains('"confidence"'));
      expect(prompt, contains('"description"'));
    });
  });

  group("parsePartAnalysisFromText", () {
    test("valid JSON parses correctly", () {
      final jsonText = json.encode({
        "name": "M3 Bolt",
        "description": "A small bolt",
        "keywords": "bolt,fastener",
        "category_suggestion": "Fasteners",
        "is_component": true,
        "is_purchaseable": true,
        "confidence": 0.9,
        "manufacturer_name": "Acme",
        "MPN": "M3-10",
        "supplier_name": "Digi-Key",
        "SKU": "DK-123",
        "item_count": 25,
      });

      final result = parsePartAnalysisFromText(jsonText);
      expect(result.name, "M3 Bolt");
      expect(result.description, "A small bolt");
      expect(result.keywords, "bolt,fastener");
      expect(result.categoryName, "Fasteners");
      expect(result.isComponent, true);
      expect(result.isPurchaseable, true);
      expect(result.confidence, 0.9);
      expect(result.manufacturerName, "Acme");
      expect(result.MPN, "M3-10");
      expect(result.supplierName, "Digi-Key");
      expect(result.SKU, "DK-123");
      expect(result.itemCount, 25);
    });

    test("markdown-fenced JSON strips fences and parses correctly", () {
      const jsonText =
          '```json\n{"name":"Resistor","description":"A resistor","confidence":0.8}\n```';
      final result = parsePartAnalysisFromText(jsonText);
      expect(result.name, "Resistor");
      expect(result.description, "A resistor");
      expect(result.confidence, 0.8);
    });

    test("with null optional fields preserves nulls", () {
      final jsonText = json.encode({
        "name": "Widget",
        "description": "A widget",
        "manufacturer_name": null,
        "MPN": null,
        "supplier_name": null,
        "SKU": null,
        "item_count": null,
      });
      final result = parsePartAnalysisFromText(jsonText);
      expect(result.manufacturerName, isNull);
      expect(result.MPN, isNull);
      expect(result.supplierName, isNull);
      expect(result.SKU, isNull);
      expect(result.itemCount, isNull);
    });

    test("invalid JSON returns fallback result", () {
      final result = parsePartAnalysisFromText("not valid json at all");
      expect(result.name, "Unknown Part");
      expect(result.confidence, 0.0);
      expect(result.rawAnalysis, "not valid json at all");
    });
  });

  group("parseStockCountFromText", () {
    test("valid JSON parses correctly", () {
      final jsonText = json.encode({
        "count": 12,
        "confidence": 0.85,
        "description": "12 resistors in a strip",
      });
      final result = parseStockCountFromText(jsonText);
      expect(result.count, 12);
      expect(result.confidence, 0.85);
      expect(result.description, "12 resistors in a strip");
    });

    test("markdown-fenced JSON strips fences and parses correctly", () {
      const jsonText =
          '```json\n{"count":5,"confidence":0.7,"description":"5 bolts"}\n```';
      final result = parseStockCountFromText(jsonText);
      expect(result.count, 5);
      expect(result.confidence, 0.7);
      expect(result.description, "5 bolts");
    });

    test("invalid JSON returns fallback", () {
      final result = parseStockCountFromText("this is not json");
      expect(result.count, 0);
      expect(result.confidence, 0.0);
      expect(result.rawAnalysis, "this is not json");
    });
  });

  group("parsePartAnalysisResponse (Claude envelope)", () {
    Map<String, dynamic> _wrap(String text) {
      return {
        "content": [
          {"type": "text", "text": text},
        ],
      };
    }

    test("valid Claude response parses correctly", () {
      final jsonText = json.encode({
        "name": "M3 Bolt",
        "description": "A small bolt",
        "confidence": 0.9,
      });

      final result = parsePartAnalysisResponse(_wrap(jsonText));
      expect(result.name, "M3 Bolt");
      expect(result.description, "A small bolt");
      expect(result.confidence, 0.9);
    });

    test("empty content list throws", () {
      expect(
        () => parsePartAnalysisResponse({"content": []}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            "message",
            contains("Empty response from Claude"),
          ),
        ),
      );
    });

    test("no text block throws", () {
      expect(
        () => parsePartAnalysisResponse({
          "content": [
            {"type": "image", "data": "abc"},
          ],
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            "message",
            contains("No text content"),
          ),
        ),
      );
    });
  });

  group("parseStockCountResponse (Claude envelope)", () {
    Map<String, dynamic> _wrap(String text) {
      return {
        "content": [
          {"type": "text", "text": text},
        ],
      };
    }

    test("valid Claude response parses correctly", () {
      final jsonText = json.encode({
        "count": 12,
        "confidence": 0.85,
        "description": "12 resistors in a strip",
      });
      final result = parseStockCountResponse(_wrap(jsonText));
      expect(result.count, 12);
      expect(result.confidence, 0.85);
      expect(result.description, "12 resistors in a strip");
    });

    test("empty content throws", () {
      expect(
        () => parseStockCountResponse({"content": []}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            "message",
            contains("Empty response from Claude"),
          ),
        ),
      );
    });
  });
}
