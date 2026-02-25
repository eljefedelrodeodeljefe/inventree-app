import "dart:io";

/*
 * Data class representing the result of an AI part analysis.
 */
class AIPartResult {
  AIPartResult({
    required this.name,
    required this.description,
    this.keywords,
    this.categoryName,
    this.isComponent,
    this.isPurchaseable,
    this.rawAnalysis,
    this.confidence = 0.0,
    this.manufacturerName,
    this.MPN,
    this.supplierName,
    this.SKU,
    this.itemCount,
  });

  String name;
  String description;
  String? keywords;
  String? categoryName;
  bool? isComponent;
  bool? isPurchaseable;
  String? rawAnalysis;
  double confidence;
  String? manufacturerName;
  String? MPN;
  String? supplierName;
  String? SKU;
  int? itemCount;
}

/*
 * Data class representing the result of an AI stock count analysis.
 */
class AIStockCountResult {
  AIStockCountResult({
    required this.count,
    this.confidence = 0.0,
    this.description,
    this.rawAnalysis,
  });

  int count;
  double confidence;
  String? description;
  String? rawAnalysis;
}

/*
 * Abstract interface for AI services that can analyze part images.
 */
abstract class AIService {
  String get providerName;

  Future<AIPartResult> analyzePartImage(
    File imageFile, {
    List<String>? categoryNames,
  });

  Future<AIStockCountResult> analyzeStockCount(
    File imageFile, {
    String? partName,
  });

  Future<bool> testConnection();
}
