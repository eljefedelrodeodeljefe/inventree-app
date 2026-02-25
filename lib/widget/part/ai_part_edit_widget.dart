import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/ai/ai_factory.dart";
import "package:inventree/ai/ai_service.dart";
import "package:inventree/api.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/preferences.dart";
import "package:inventree/inventree/company.dart";
import "package:inventree/inventree/part.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/widget/progress.dart";
import "package:inventree/widget/part/ai_part_category_picker.dart";
import "package:inventree/widget/part/ai_part_company_picker.dart";
import "package:inventree/widget/part/ai_part_item_count.dart";
import "package:inventree/widget/snacks.dart";

import "package:inventree/l10.dart";

class AIPartEditWidget extends StatefulWidget {
  const AIPartEditWidget({
    Key? key,
    required this.imageFile,
    required this.result,
    this.categoryId,
    this.categoryName,
    this.parentCategoryId,
    this.parentCategoryName,
    this.subCategories,
    this.onSubmitted,
  }) : super(key: key);

  final File imageFile;
  final AIPartResult result;
  final int? categoryId;
  final String? categoryName;
  final int? parentCategoryId;
  final String? parentCategoryName;
  final Map<String, int>? subCategories;
  final VoidCallback? onSubmitted;

  @override
  AIPartEditWidgetState createState() => AIPartEditWidgetState();
}

class AIPartEditWidgetState extends State<AIPartEditWidget> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _ipnController = TextEditingController();
  final _keywordsController = TextEditingController();
  final _mpnController = TextEditingController();
  final _skuController = TextEditingController();
  final _manufacturerSearchController = TextEditingController();
  final _supplierSearchController = TextEditingController();

  bool _active = true;
  bool _component = true;
  bool _purchaseable = true;
  bool _salable = false;
  bool _trackable = false;

  double _confidence = 0.0;
  String? _categorySuggestion;
  int? _categoryId;
  String? _categoryName;
  bool _submitting = false;
  bool _reanalyzing = false;
  String? _pendingCategoryCreation;
  int _itemCount = 0;
  bool _createStock = false;

  // Duplicate detection
  List<InvenTreePart> _duplicates = [];
  bool _searchingDuplicates = false;
  bool _duplicatesDismissed = false;

  // Manufacturer & Supplier
  InvenTreeCompany? _selectedManufacturer;
  InvenTreeCompany? _selectedSupplier;
  List<InvenTreeCompany> _manufacturerResults = [];
  List<InvenTreeCompany> _supplierResults = [];
  bool _searchingManufacturers = false;
  bool _searchingSuppliers = false;
  bool _creatingManufacturer = false;
  bool _creatingSupplier = false;
  bool _manufacturerExpanded = false;
  bool _supplierExpanded = false;
  String? _aiManufacturerName;
  String? _aiSupplierName;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _categoryName = widget.categoryName;
    _populateFromResult(widget.result);
    _searchDuplicates(widget.result.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _ipnController.dispose();
    _keywordsController.dispose();
    _mpnController.dispose();
    _skuController.dispose();
    _manufacturerSearchController.dispose();
    _supplierSearchController.dispose();
    super.dispose();
  }

  void _populateFromResult(AIPartResult result) {
    _nameController.text = result.name;
    _descriptionController.text = result.description.length > 250
        ? result.description.substring(0, 250)
        : result.description;
    _keywordsController.text = result.keywords ?? "";
    _categorySuggestion = result.categoryName;
    _component = result.isComponent ?? true;
    _purchaseable = result.isPurchaseable ?? true;
    _confidence = result.confidence;
    _itemCount = result.itemCount ?? 0;

    // Manufacturer & Supplier from AI
    _mpnController.text = result.MPN ?? "";
    _skuController.text = result.SKU ?? "";
    _aiManufacturerName = result.manufacturerName;
    _aiSupplierName = result.supplierName;
    _selectedManufacturer = null;
    _selectedSupplier = null;
    _manufacturerResults = [];
    _supplierResults = [];
    _manufacturerSearchController.text = result.manufacturerName?.trim() ?? "";
    _supplierSearchController.text = result.supplierName?.trim() ?? "";

    if (result.manufacturerName != null &&
        result.manufacturerName!.trim().isNotEmpty) {
      _manufacturerExpanded = true;
      _searchCompanies(result.manufacturerName!.trim(), isManufacturer: true);
    } else {
      _manufacturerExpanded = false;
    }

    if (result.supplierName != null && result.supplierName!.trim().isNotEmpty) {
      _supplierExpanded = true;
      _searchCompanies(result.supplierName!.trim(), isManufacturer: false);
    } else {
      _supplierExpanded = false;
    }
  }

  /// Test-only helper to set internal state without triggering async searches.
  @visibleForTesting
  void setTestState({
    InvenTreeCompany? selectedManufacturer,
    InvenTreeCompany? selectedSupplier,
    String? mpn,
    String? sku,
    bool? createStock,
    int? itemCount,
    int? categoryId,
    String? categoryName,
    String? pendingCategoryCreation,
    bool? duplicatesDismissed,
    List<InvenTreePart>? duplicates,
  }) {
    setState(() {
      if (selectedManufacturer != null) {
        _selectedManufacturer = selectedManufacturer;
        _manufacturerExpanded = true;
      }
      if (selectedSupplier != null) {
        _selectedSupplier = selectedSupplier;
        _supplierExpanded = true;
      }
      if (mpn != null) _mpnController.text = mpn;
      if (sku != null) _skuController.text = sku;
      if (createStock != null) _createStock = createStock;
      if (itemCount != null) _itemCount = itemCount;
      if (categoryId != null) _categoryId = categoryId;
      if (categoryName != null) _categoryName = categoryName;
      if (pendingCategoryCreation != null) {
        _pendingCategoryCreation = pendingCategoryCreation;
      }
      if (duplicatesDismissed != null) {
        _duplicatesDismissed = duplicatesDismissed;
      }
      if (duplicates != null) _duplicates = duplicates;
    });
  }

  /// Test-only: trigger part submission outside of gesture handling.
  @visibleForTesting
  Future<void> submitForTest() => _submitPart();

  /// Test-only: trigger update-existing-part flow.
  @visibleForTesting
  Future<void> updateExistingForTest(InvenTreePart part) =>
      _updateExistingPart(part);

  Future<void> _searchDuplicates(String name) async {
    if (name.trim().isEmpty) return;

    setState(() {
      _searchingDuplicates = true;
      _duplicatesDismissed = false;
    });

    try {
      final results = await InvenTreePart().search(name.trim(), limit: 5);

      if (!mounted) return;

      setState(() {
        _duplicates = results.cast<InvenTreePart>();
        _searchingDuplicates = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchingDuplicates = false;
        });
      }
    }
  }

  Future<void> _searchCompanies(
    String name, {
    required bool isManufacturer,
  }) async {
    if (name.trim().isEmpty) return;

    setState(() {
      if (isManufacturer) {
        _searchingManufacturers = true;
      } else {
        _searchingSuppliers = true;
      }
    });

    try {
      final filterKey = isManufacturer ? "is_manufacturer" : "is_supplier";
      final results = await InvenTreeCompany().search(
        name.trim(),
        filters: {filterKey: "true"},
        limit: 5,
      );

      if (!mounted) return;

      final companies = results.cast<InvenTreeCompany>();

      // Auto-select an exact name match so the AI suggestion is pre-filled.
      InvenTreeCompany? autoMatch;
      for (final c in companies) {
        if (c.name.toLowerCase() == name.toLowerCase()) {
          autoMatch = c;
          break;
        }
      }

      setState(() {
        if (isManufacturer) {
          _searchingManufacturers = false;
          if (autoMatch != null) {
            _selectedManufacturer = autoMatch;
            _manufacturerResults = [];
          } else {
            _manufacturerResults = companies;
          }
        } else {
          _searchingSuppliers = false;
          if (autoMatch != null) {
            _selectedSupplier = autoMatch;
            _supplierResults = [];
          } else {
            _supplierResults = companies;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isManufacturer) {
            _searchingManufacturers = false;
          } else {
            _searchingSuppliers = false;
          }
        });
      }
    }
  }

  Future<void> _createCompany(
    String name, {
    required bool isManufacturer,
  }) async {
    if (isManufacturer ? _creatingManufacturer : _creatingSupplier) return;

    setState(() {
      if (isManufacturer) {
        _creatingManufacturer = true;
      } else {
        _creatingSupplier = true;
      }
    });

    try {
      final body = {
        "name": name,
        "description": name,
        "is_manufacturer": isManufacturer,
        "is_supplier": !isManufacturer,
      };

      final response = await InvenTreeAPI().post(
        "company/",
        body: body,
        expectedStatusCode: null,
      );

      if (!mounted) return;

      if (response.successful()) {
        final data = response.asMap();
        final company = InvenTreeCompany.fromJson(data);

        setState(() {
          if (isManufacturer) {
            _selectedManufacturer = company;
            _manufacturerResults = [];
            // Auto-suggest as supplier too
            if (_selectedSupplier == null && !_supplierExpanded) {
              _supplierExpanded = true;
              _selectedSupplier = company;
            }
          } else {
            _selectedSupplier = company;
            _supplierResults = [];
          }
        });

        showSnackIcon(L10().aiCompanyCreated, success: true);
      } else {
        _showErrorSnack(
          L10().aiCompanyCreateFailed,
          _parseErrorResponse(response),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnack(L10().aiCompanyCreateFailed, "$e");
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isManufacturer) {
            _creatingManufacturer = false;
          } else {
            _creatingSupplier = false;
          }
        });
      }
    }
  }

  String _parseErrorResponse(APIResponse response) {
    if (response.isMap()) {
      final errors = response.asMap();
      List<String> errorParts = [];
      for (final entry in errors.entries) {
        if (entry.value is List) {
          errorParts.add("${entry.key}: ${(entry.value as List).join(", ")}");
        } else {
          errorParts.add("${entry.key}: ${entry.value}");
        }
      }
      if (errorParts.isNotEmpty) {
        return errorParts.join("\n");
      }
    }
    return "HTTP ${response.statusCode}";
  }

  Future<int?> _createCategory(String name, int? parentId) async {
    try {
      Map<String, dynamic> body = {"name": name};
      if (parentId != null && parentId > 0) {
        body["parent"] = parentId;
      }

      final response = await InvenTreeAPI().post(
        "part/category/",
        body: body,
        expectedStatusCode: null,
      );

      if (response.successful()) {
        final data = response.asMap();
        if (data.containsKey("pk")) {
          return data["pk"] as int;
        }
      }
    } catch (e, stackTrace) {
      sentryReportError("AIPartEditWidget._createCategory", e, stackTrace);
    }
    return null;
  }

  void _showErrorSnack(String title, String details) {
    showSnackIcon(
      title,
      success: false,
      onAction: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(details)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text("OK"),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createInitialStock(int partPk) async {
    try {
      final body = <String, dynamic>{"part": partPk, "quantity": _itemCount};

      // Use the part's default location if available, otherwise no location
      final response = await InvenTreeAPI().post(
        "stock/",
        body: body,
        expectedStatusCode: null,
      );

      if (!response.successful()) {
        _showErrorSnack(
          L10().aiInitialStockFailed,
          _parseErrorResponse(response),
        );
      }
    } catch (e) {
      _showErrorSnack(L10().aiInitialStockFailed, "$e");
    }
  }

  Future<void> _createLinkedParts(int partPk) async {
    int? manufacturerPartPk;

    // Create ManufacturerPart
    if (_selectedManufacturer != null &&
        _mpnController.text.trim().isNotEmpty) {
      try {
        final response = await InvenTreeAPI().post(
          "company/part/manufacturer/",
          body: {
            "part": partPk,
            "manufacturer": _selectedManufacturer!.pk,
            "MPN": _mpnController.text.trim(),
          },
          expectedStatusCode: null,
        );

        if (response.successful()) {
          final data = response.asMap();
          manufacturerPartPk = data["pk"] as int?;
        } else {
          _showErrorSnack(
            L10().aiManufacturerPartCreateFailed,
            _parseErrorResponse(response),
          );
        }
      } catch (e) {
        _showErrorSnack(L10().aiManufacturerPartCreateFailed, "$e");
      }
    }

    // Create SupplierPart
    if (_selectedSupplier != null && _skuController.text.trim().isNotEmpty) {
      try {
        final body = <String, dynamic>{
          "part": partPk,
          "supplier": _selectedSupplier!.pk,
          "SKU": _skuController.text.trim(),
        };

        if (manufacturerPartPk != null) {
          body["manufacturer_part"] = manufacturerPartPk;
        }

        final response = await InvenTreeAPI().post(
          "company/part/",
          body: body,
          expectedStatusCode: null,
        );

        if (!response.successful()) {
          _showErrorSnack(
            L10().aiSupplierPartCreateFailed,
            _parseErrorResponse(response),
          );
        }
      } catch (e) {
        _showErrorSnack(L10().aiSupplierPartCreateFailed, "$e");
      }
    }
  }

  Future<void> _updateExistingPart(InvenTreePart existing) async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
    });

    try {
      showLoadingOverlay();

      final response = await existing.update(
        values: {
          "description": _descriptionController.text.trim(),
          if (_keywordsController.text.trim().isNotEmpty)
            "keywords": _keywordsController.text.trim(),
        },
      );

      if (response.successful()) {
        await existing.uploadImage(widget.imageFile);
        hideLoadingOverlay();
        showSnackIcon(L10().aiPartUpdated, success: true);
        widget.onSubmitted?.call();
        if (mounted) {
          Navigator.of(context).pop();
          existing.goToDetailPage(context);
        }
      } else {
        hideLoadingOverlay();
        _showErrorSnack(
          L10().aiPartUpdateFailed,
          "HTTP ${response.statusCode}",
        );
      }
    } catch (e, stackTrace) {
      hideLoadingOverlay();
      sentryReportError("AIPartEditWidget._updateExistingPart", e, stackTrace);
      _showErrorSnack(L10().aiPartUpdateFailed, "$e");
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _reanalyze() async {
    setState(() {
      _reanalyzing = true;
    });

    try {
      final service = await AIServiceFactory.create();
      if (service == null) {
        showSnackIcon(L10().aiServiceNotConfigured, success: false);
        return;
      }

      final result = await service.analyzePartImage(widget.imageFile);
      if (!mounted) return;

      setState(() {
        _populateFromResult(result);
      });
    } catch (e, stackTrace) {
      sentryReportError("AIPartEditWidget._reanalyze", e, stackTrace);
      showSnackIcon("${L10().aiReanalysisFailed}: $e", success: false);
    } finally {
      if (mounted) {
        setState(() {
          _reanalyzing = false;
        });
      }
    }
  }

  Future<void> _submitPart() async {
    if (!_formKey.currentState!.validate()) return;
    if (_submitting) return;

    setState(() {
      _submitting = true;
    });

    try {
      Map<String, dynamic> body = {
        "name": _nameController.text.trim(),
        "description": _descriptionController.text.trim(),
        "active": _active,
        "component": _component,
        "purchaseable": _purchaseable,
        "salable": _salable,
        "trackable": _trackable,
      };

      String ipn = _ipnController.text.trim();
      if (ipn.isNotEmpty) {
        body["IPN"] = ipn;
      }

      String keywords = _keywordsController.text.trim();
      if (keywords.isNotEmpty) {
        body["keywords"] = keywords;
      }

      // Create pending category if user selected an AI suggestion
      int? effectiveCategoryId = _categoryId;
      if (_pendingCategoryCreation != null &&
          _pendingCategoryCreation!.isNotEmpty) {
        final newCatId = await _createCategory(
          _pendingCategoryCreation!,
          widget.parentCategoryId,
        );
        if (newCatId != null) {
          effectiveCategoryId = newCatId;
        }
      }

      if (effectiveCategoryId != null && effectiveCategoryId > 0) {
        body["category"] = effectiveCategoryId;
      }

      showLoadingOverlay();

      final APIResponse response = await InvenTreeAPI().post(
        "part/",
        body: body,
        expectedStatusCode: null,
      );

      hideLoadingOverlay();

      if (response.successful()) {
        final data = response.asMap();
        if (data.containsKey("pk")) {
          final part = InvenTreePart.fromJson(data);
          await part.uploadImage(widget.imageFile);

          // Inject forced AI tag (best-effort, don't block on failure)
          final String forceTag =
              await InvenTreeSettingsManager().getValue(
                    INV_AI_FORCE_TAG,
                    INV_AI_FORCE_TAG_DEFAULT,
                  )
                  as String;
          if (forceTag.isNotEmpty) {
            try {
              await InvenTreeAPI().patch(
                "part/${part.pk}/",
                body: {
                  "tags": [forceTag],
                },
                expectedStatusCode: null,
              );
            } catch (_) {}
          }

          // Create linked manufacturer/supplier parts
          await _createLinkedParts(part.pk);

          // Create initial stock if toggle is enabled
          if (_createStock && _itemCount > 0) {
            await _createInitialStock(part.pk);
          }

          showSnackIcon(L10().aiPartCreatedSuccess, success: true);

          widget.onSubmitted?.call();

          if (mounted) {
            Navigator.of(context).pop();
            part.goToDetailPage(context);
          }
        } else {
          showSnackIcon(L10().aiPartCreated, success: true);
          widget.onSubmitted?.call();
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } else {
        _showErrorSnack(
          L10().aiPartCreateFailed,
          _parseErrorResponse(response),
        );
      }
    } catch (e, stackTrace) {
      hideLoadingOverlay();
      sentryReportError("AIPartEditWidget._submitPart", e, stackTrace);
      _showErrorSnack(L10().aiPartCreateFailed, "$e");
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Color badgeColor = _confidence >= 0.7
        ? COLOR_SUCCESS
        : _confidence >= 0.4
        ? COLOR_WARNING
        : COLOR_DANGER;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10().aiEditPart),
        backgroundColor: COLOR_APP_BAR,
        actions: [
          IconButton(
            icon: Icon(TablerIcons.refresh),
            tooltip: L10().aiReanalyze,
            onPressed: _reanalyzing ? null : _reanalyze,
          ),
          IconButton(
            icon: Icon(TablerIcons.device_floppy),
            tooltip: L10().aiSubmit,
            onPressed: _submitting ? null : _submitPart,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image preview
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        widget.imageFile,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    SizedBox(height: 8),

                    // Confidence badge
                    Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              TablerIcons.circle_check,
                              color: COLOR_SUCCESS,
                            ),
                            SizedBox(width: 8),
                            Text(L10().aiAnalysisComplete),
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withAlpha(40),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                L10().aiConfidencePercent(
                                  (_confidence * 100).toInt(),
                                ),
                                style: TextStyle(
                                  color: badgeColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),

                    // Duplicate detection
                    if (_searchingDuplicates)
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(L10().aiCheckingDuplicates),
                            ],
                          ),
                        ),
                      ),
                    if (!_searchingDuplicates &&
                        _duplicates.isNotEmpty &&
                        !_duplicatesDismissed)
                      Card(
                        color: COLOR_WARNING.withAlpha(25),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    TablerIcons.alert_triangle,
                                    color: COLOR_WARNING,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    L10().aiPossibleDuplicates,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Spacer(),
                                  InkWell(
                                    onTap: () => setState(
                                      () => _duplicatesDismissed = true,
                                    ),
                                    child: Icon(
                                      TablerIcons.x,
                                      size: 18,
                                      color: COLOR_GRAY_LIGHT,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              ..._duplicates.map(
                                (part) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: InvenTreeAPI().getThumbnail(
                                    part.thumbnail,
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          part.fullname,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!part.isActive)
                                        Container(
                                          margin: EdgeInsets.only(left: 6),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: COLOR_DANGER.withAlpha(30),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            L10().inactive,
                                            style: TextStyle(
                                              color: COLOR_DANGER,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    part.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          TablerIcons.eye,
                                          color: COLOR_ACTION,
                                        ),
                                        tooltip: L10().aiViewPart,
                                        onPressed: () =>
                                            part.goToDetailPage(context),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          TablerIcons.replace,
                                          color: COLOR_WARNING,
                                        ),
                                        tooltip: L10().aiUpdateThisPart,
                                        onPressed: () =>
                                            _updateExistingPart(part),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Category dropdown
                    AIPartCategoryPicker(
                      categoryId: _categoryId,
                      categoryName: _categoryName,
                      pendingCategoryCreation: _pendingCategoryCreation,
                      categorySuggestion: _categorySuggestion,
                      parentCategoryId: widget.parentCategoryId,
                      parentCategoryName: widget.parentCategoryName,
                      subCategories: widget.subCategories,
                      onPicked: (id, name, pending) {
                        setState(() {
                          _pendingCategoryCreation = pending;
                          _categoryId = id;
                          _categoryName = name;
                        });
                      },
                    ),

                    SizedBox(height: 8),

                    // Form fields
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: L10().aiPartName,
                        hintText: L10().aiPartNameHint,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return L10().valueRequired;
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: L10().aiPartDescription,
                        hintText: L10().aiPartDescriptionHint,
                        counterText: "",
                      ),
                      maxLength: 250,
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return L10().valueRequired;
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _ipnController,
                      decoration: InputDecoration(
                        labelText: L10().aiIpn,
                        hintText: L10().aiIpnHint,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _keywordsController,
                      decoration: InputDecoration(
                        labelText: L10().keywords,
                        hintText: L10().aiKeywordsHint,
                        suffixIcon: _keywordsController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(TablerIcons.x, size: 18),
                                tooltip: L10().aiClearKeywords,
                                onPressed: () {
                                  setState(() {
                                    _keywordsController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Manufacturer section
                    AIPartCompanyPicker(
                      icon: TablerIcons.building_factory,
                      label: L10().manufacturer,
                      addLabel: L10().aiAddManufacturer,
                      companyTypeLabel: L10().manufacturer,
                      selected: _selectedManufacturer,
                      searchController: _manufacturerSearchController,
                      searchResults: _manufacturerResults,
                      isSearching: _searchingManufacturers,
                      isCreating: _creatingManufacturer,
                      isExpanded: _manufacturerExpanded,
                      aiName: _aiManufacturerName,
                      searchingLabel: L10().aiSearchingManufacturers,
                      noMatchLabel: L10().aiNoMatchingManufacturers,
                      onSelected: (company) {
                        setState(() {
                          _selectedManufacturer = company;
                          _manufacturerResults = [];
                          // Auto-suggest as supplier if applicable
                          if (!_supplierExpanded && company.isSupplier) {
                            _supplierExpanded = true;
                            _selectedSupplier = company;
                          }
                        });
                      },
                      onCleared: () => setState(() {
                        _selectedManufacturer = null;
                        _manufacturerResults = [];
                        _aiManufacturerName = null;
                        _manufacturerSearchController.clear();
                      }),
                      onSearch: (query) {
                        setState(() {
                          _aiManufacturerName = query;
                        });
                        _searchCompanies(query, isManufacturer: true);
                      },
                      onCreate: (name) =>
                          _createCompany(name, isManufacturer: true),
                      onExpand: () =>
                          setState(() => _manufacturerExpanded = true),
                      extraFieldController: _mpnController,
                      extraFieldLabel: L10().aiMpn,
                      extraFieldHint: L10().aiMpnHint,
                    ),
                    SizedBox(height: 8),

                    // Supplier section
                    AIPartCompanyPicker(
                      icon: TablerIcons.truck,
                      label: L10().supplier,
                      addLabel: L10().aiAddSupplier,
                      companyTypeLabel: L10().supplier,
                      selected: _selectedSupplier,
                      searchController: _supplierSearchController,
                      searchResults: _supplierResults,
                      isSearching: _searchingSuppliers,
                      isCreating: _creatingSupplier,
                      isExpanded: _supplierExpanded,
                      aiName: _aiSupplierName,
                      searchingLabel: L10().aiSearchingSuppliers,
                      noMatchLabel: L10().aiNoMatchingSuppliers,
                      onSelected: (company) => setState(() {
                        _selectedSupplier = company;
                        _supplierResults = [];
                      }),
                      onCleared: () => setState(() {
                        _selectedSupplier = null;
                        _supplierResults = [];
                        _aiSupplierName = null;
                        _supplierSearchController.clear();
                      }),
                      onSearch: (query) {
                        setState(() {
                          _aiSupplierName = query;
                        });
                        _searchCompanies(query, isManufacturer: false);
                      },
                      onCreate: (name) =>
                          _createCompany(name, isManufacturer: false),
                      onExpand: () => setState(() => _supplierExpanded = true),
                      extraFieldController: _skuController,
                      extraFieldLabel: L10().aiSpn,
                      extraFieldHint: L10().aiSpnHint,
                    ),
                    SizedBox(height: 8),

                    // Item count section
                    AIPartItemCount(
                      aiCount: widget.result.itemCount,
                      currentCount: _itemCount,
                      createStock: _createStock,
                      onCountChanged: (count) =>
                          setState(() => _itemCount = count),
                      onCreateStockChanged: (v) =>
                          setState(() => _createStock = v),
                    ),
                    SizedBox(height: 8),

                    // Checkbox fields
                    CheckboxListTile(
                      title: Text(L10().aiActive),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v ?? true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: Text(L10().aiComponent),
                      subtitle: Text(L10().aiComponentDetail),
                      value: _component,
                      onChanged: (v) => setState(() => _component = v ?? true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: Text(L10().aiPurchaseable),
                      subtitle: Text(L10().aiPurchaseableDetail),
                      value: _purchaseable,
                      onChanged: (v) =>
                          setState(() => _purchaseable = v ?? true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: Text(L10().aiSalable),
                      subtitle: Text(L10().aiSalableDetail),
                      value: _salable,
                      onChanged: (v) => setState(() => _salable = v ?? false),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: Text(L10().aiTrackable),
                      subtitle: Text(L10().aiTrackableDetail),
                      value: _trackable,
                      onChanged: (v) => setState(() => _trackable = v ?? false),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: Icon(TablerIcons.device_floppy),
                  label: Text(L10().aiSavePart, style: TextStyle(fontSize: 16)),
                  onPressed: _submitting ? null : _submitPart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: COLOR_SUCCESS,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
