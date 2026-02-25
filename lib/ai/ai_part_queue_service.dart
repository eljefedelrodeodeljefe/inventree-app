import "dart:io";

import "package:flutter/foundation.dart";

import "package:inventree/ai/ai_factory.dart";
import "package:inventree/ai/ai_service.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/l10.dart";

enum AIPartQueueStatus { pending, analyzing, success, error }

class AIPartQueueItem {
  AIPartQueueItem({required this.id, required this.imageFile});

  final String id;
  final File imageFile;
  AIPartQueueStatus status = AIPartQueueStatus.pending;
  AIPartResult? result;
  String? errorMessage;
}

class AIPartQueueService extends ChangeNotifier {
  final List<AIPartQueueItem> _items = [];
  AIService? _service;
  bool _initialized = false;
  List<String>? _categoryNames;

  List<AIPartQueueItem> get items => List.unmodifiable(_items);

  Future<void> initialize({List<String>? categoryNames}) async {
    _categoryNames = categoryNames;
    if (_initialized) return;
    _service = await AIServiceFactory.create();
    _initialized = true;
  }

  int _nextId = 0;

  void enqueue(File imageFile) {
    final item = AIPartQueueItem(
      id: (_nextId++).toString(),
      imageFile: imageFile,
    );
    _items.insert(0, item);
    notifyListeners();
    _analyze(item);
  }

  Future<void> _analyze(AIPartQueueItem item) async {
    item.status = AIPartQueueStatus.analyzing;
    notifyListeners();

    try {
      if (_service == null) {
        item.status = AIPartQueueStatus.error;
        item.errorMessage = L10().aiServiceNotConfigured;
        notifyListeners();
        return;
      }

      final result = await _service!.analyzePartImage(
        item.imageFile,
        categoryNames: _categoryNames,
      );
      item.result = result;
      item.status = AIPartQueueStatus.success;
    } catch (e, stackTrace) {
      sentryReportError("AIPartQueueService._analyze", e, stackTrace);
      item.status = AIPartQueueStatus.error;
      item.errorMessage = "${L10().aiAnalysisFailed}: $e";
    }

    notifyListeners();
  }

  void retryItem(String id) {
    final item = _items.where((i) => i.id == id).firstOrNull;
    if (item != null) {
      item.errorMessage = null;
      _analyze(item);
    }
  }

  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    notifyListeners();
  }
}
