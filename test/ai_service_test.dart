import "package:flutter_test/flutter_test.dart";
import "package:inventree/ai/ai_service.dart";

void main() {
  group("AIPartResult", () {
    test("construction with all fields", () {
      final result = AIPartResult(
        name: "M3 Bolt",
        description: "A small bolt",
        keywords: "bolt,fastener",
        categoryName: "Fasteners",
        isComponent: true,
        isPurchaseable: true,
        rawAnalysis: "raw",
        confidence: 0.95,
        manufacturerName: "Acme",
        MPN: "M3-10",
        supplierName: "Digi-Key",
        SKU: "DK-123",
        itemCount: 50,
      );

      expect(result.name, "M3 Bolt");
      expect(result.description, "A small bolt");
      expect(result.keywords, "bolt,fastener");
      expect(result.categoryName, "Fasteners");
      expect(result.isComponent, true);
      expect(result.isPurchaseable, true);
      expect(result.rawAnalysis, "raw");
      expect(result.confidence, 0.95);
      expect(result.manufacturerName, "Acme");
      expect(result.MPN, "M3-10");
      expect(result.supplierName, "Digi-Key");
      expect(result.SKU, "DK-123");
      expect(result.itemCount, 50);
    });

    test("construction with required fields only uses defaults", () {
      final result = AIPartResult(name: "Widget", description: "A widget");

      expect(result.name, "Widget");
      expect(result.description, "A widget");
      expect(result.keywords, isNull);
      expect(result.categoryName, isNull);
      expect(result.isComponent, isNull);
      expect(result.isPurchaseable, isNull);
      expect(result.rawAnalysis, isNull);
      expect(result.confidence, 0.0);
      expect(result.manufacturerName, isNull);
      expect(result.MPN, isNull);
      expect(result.supplierName, isNull);
      expect(result.SKU, isNull);
      expect(result.itemCount, isNull);
    });

    test("itemCount field exists and is nullable", () {
      final withCount = AIPartResult(
        name: "Part",
        description: "Desc",
        itemCount: 10,
      );
      expect(withCount.itemCount, 10);

      final withoutCount = AIPartResult(name: "Part", description: "Desc");
      expect(withoutCount.itemCount, isNull);
    });
  });

  group("AIStockCountResult", () {
    test("construction with all fields", () {
      final result = AIStockCountResult(
        count: 42,
        confidence: 0.9,
        description: "42 screws",
        rawAnalysis: "raw text",
      );

      expect(result.count, 42);
      expect(result.confidence, 0.9);
      expect(result.description, "42 screws");
      expect(result.rawAnalysis, "raw text");
    });

    test("default confidence is 0.0", () {
      final result = AIStockCountResult(count: 5);

      expect(result.count, 5);
      expect(result.confidence, 0.0);
      expect(result.description, isNull);
      expect(result.rawAnalysis, isNull);
    });
  });
}
