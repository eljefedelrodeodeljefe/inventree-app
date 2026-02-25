// Tests for AIPartEditWidget submission logic.
//
// Verifies exactly which API calls are made for every meaningful combination
// of inputs (14 cases). Uses a real dart:io HttpServer as a mock backend.
// These run as plain `test()` cases (not testWidgets) to avoid FakeAsync
// complications with real HTTP I/O. We directly invoke the same methods the
// widget calls, using the same InvenTreeAPI singleton.
import "package:flutter_test/flutter_test.dart";

import "package:inventree/api.dart";
import "package:inventree/user_profile.dart";

import "mock_server.dart";
import "setup.dart";

/// Mirrors the submission logic of AIPartEditWidget._submitPart().
///
/// Returns the pk of the created part, or null if creation failed.
Future<int?> _submitPart(
  MockInvenTreeServer server, {
  required String name,
  required String description,
  int? categoryId,
  String? pendingCategoryCreation,
  int? parentCategoryId,
  int? selectedManufacturerPk,
  String? mpn,
  int? selectedSupplierPk,
  String? sku,
  bool createStock = false,
  int itemCount = 0,
}) async {
  final api = InvenTreeAPI();

  Map<String, dynamic> body = {
    "name": name,
    "description": description,
    "active": true,
    "component": true,
    "purchaseable": true,
    "salable": false,
    "trackable": false,
  };

  // Create pending category if needed
  int? effectiveCategoryId = categoryId;
  if (pendingCategoryCreation != null && pendingCategoryCreation.isNotEmpty) {
    Map<String, dynamic> catBody = {"name": pendingCategoryCreation};
    if (parentCategoryId != null && parentCategoryId > 0) {
      catBody["parent"] = parentCategoryId;
    }

    final catResponse = await api.post(
      "part/category/",
      body: catBody,
      expectedStatusCode: null,
    );

    if (catResponse.successful()) {
      final data = catResponse.asMap();
      if (data.containsKey("pk")) {
        effectiveCategoryId = data["pk"] as int;
      }
    }
  }

  if (effectiveCategoryId != null && effectiveCategoryId > 0) {
    body["category"] = effectiveCategoryId;
  }

  final response = await api.post(
    "part/",
    body: body,
    expectedStatusCode: null,
  );

  if (!response.successful()) {
    return null;
  }

  final data = response.asMap();
  if (!data.containsKey("pk")) return null;

  final partPk = data["pk"] as int;

  // Tag injection (best-effort)
  const String forceTag = "system:ai";
  if (forceTag.isNotEmpty) {
    try {
      await api.patch(
        "part/$partPk/",
        body: {
          "tags": [forceTag],
        },
        expectedStatusCode: null,
      );
    } catch (_) {}
  }

  // Create linked manufacturer/supplier parts
  int? manufacturerPartPk;

  if (selectedManufacturerPk != null && mpn != null && mpn.trim().isNotEmpty) {
    final mfrResponse = await api.post(
      "company/part/manufacturer/",
      body: {
        "part": partPk,
        "manufacturer": selectedManufacturerPk,
        "MPN": mpn.trim(),
      },
      expectedStatusCode: null,
    );

    if (mfrResponse.successful()) {
      final mfrData = mfrResponse.asMap();
      manufacturerPartPk = mfrData["pk"] as int?;
    }
  }

  if (selectedSupplierPk != null && sku != null && sku.trim().isNotEmpty) {
    final supplierBody = <String, dynamic>{
      "part": partPk,
      "supplier": selectedSupplierPk,
      "SKU": sku.trim(),
    };

    if (manufacturerPartPk != null) {
      supplierBody["manufacturer_part"] = manufacturerPartPk;
    }

    await api.post(
      "company/part/",
      body: supplierBody,
      expectedStatusCode: null,
    );
  }

  // Create initial stock
  if (createStock && itemCount > 0) {
    await api.post(
      "stock/",
      body: {"part": partPk, "quantity": itemCount},
      expectedStatusCode: null,
    );
  }

  return partPk;
}

/// Mirrors AIPartEditWidget._updateExistingPart().
Future<bool> _updateExistingPart(
  MockInvenTreeServer server, {
  required int partPk,
  required String description,
  String? keywords,
}) async {
  final api = InvenTreeAPI();

  Map<String, dynamic> values = {"description": description};
  if (keywords != null && keywords.isNotEmpty) {
    values["keywords"] = keywords;
  }

  // InvenTreeModel.update() calls api.patch("part/<pk>/", body: values)
  final response = await api.patch(
    "part/$partPk/",
    body: values,
    expectedStatusCode: null,
  );

  return response.successful();
}

/// Configure standard mock routes for a successful creation flow.
void _configureStandardRoutes(MockInvenTreeServer server) {
  server.respondTo("GET", "/api/part/", body: {"results": [], "count": 0});
  server.respondTo("GET", "/api/company/", body: {"results": [], "count": 0});

  server.respondTo(
    "POST",
    r"/api/part/$",
    statusCode: 201,
    body: {
      "pk": 1,
      "name": "Test Part",
      "description": "A test part",
      "active": true,
      "thumbnail": "",
      "image": "",
    },
  );

  server.respondTo(
    "POST",
    r"/api/part/category/$",
    statusCode: 201,
    body: {"pk": 10, "name": "New Category"},
  );

  server.respondTo(
    "PATCH",
    r"/api/part/\d+/",
    statusCode: 200,
    body: {
      "pk": 1,
      "name": "Test Part",
      "tags": ["system:ai"],
    },
  );

  server.respondTo(
    "POST",
    r"/api/company/part/manufacturer/$",
    statusCode: 201,
    body: {"pk": 100, "part": 1, "manufacturer": 5, "MPN": "RC0805"},
  );

  server.respondTo(
    "POST",
    r"/api/company/part/$",
    statusCode: 201,
    body: {"pk": 200, "part": 1, "supplier": 6, "SKU": "DK-123"},
  );

  server.respondTo(
    "POST",
    r"/api/stock/$",
    statusCode: 201,
    body: {"pk": 300, "part": 1, "quantity": 10},
  );
}

void main() {
  final server = MockInvenTreeServer();

  setupTestEnv();

  setUpAll(() async {
    await server.start();
    InvenTreeAPI().profile = UserProfile(
      server: server.baseUrl,
      token: "test-token",
    );
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() {
    server.reset();
    _configureStandardRoutes(server);
  });

  // =========================================================================
  group("Core creation paths", () {
    // Case 1: Duplicate detected, dismissed → bare save (POST part/ only)
    test("Case 1: Duplicate, bare save", () async {
      await _submitPart(
        server,
        name: "Resistor",
        description: "10k Ohm resistor",
        categoryId: 5,
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should POST to part/",
      );
      expect(
        server.requestsTo("POST", r"/api/part/category/$"),
        isEmpty,
        reason: "Should NOT create category",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock",
      );
    });

    // Case 2: New, everything (category + part + mfr + supplier + stock)
    test("Case 2: New, everything", () async {
      await _submitPart(
        server,
        name: "Capacitor",
        description: "100nF ceramic capacitor",
        pendingCategoryCreation: "Capacitors",
        parentCategoryId: 1,
        selectedManufacturerPk: 5,
        mpn: "GRM188R71C104KA01D",
        selectedSupplierPk: 6,
        sku: "490-1234-1-ND",
        createStock: true,
        itemCount: 50,
      );

      expect(
        server.requestsTo("POST", r"/api/part/category/$"),
        isNotEmpty,
        reason: "Should create category",
      );
      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isNotEmpty,
        reason: "Should create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isNotEmpty,
        reason: "Should create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isNotEmpty,
        reason: "Should create stock",
      );

      // Verify manufacturer part body contents
      final mfrBody = server
          .requestsTo("POST", r"/api/company/part/manufacturer/$")
          .first
          .body!;
      expect(
        mfrBody["manufacturer"],
        equals(5),
        reason: "Manufacturer part should reference manufacturer pk",
      );
      expect(
        mfrBody["MPN"],
        equals("GRM188R71C104KA01D"),
        reason: "Manufacturer part should have MPN",
      );
      expect(
        mfrBody["part"],
        equals(1),
        reason: "Manufacturer part should reference created part pk",
      );

      // Verify supplier part body contents
      final supBody = server
          .requestsTo("POST", r"/api/company/part/$")
          .first
          .body!;
      expect(
        supBody["supplier"],
        equals(6),
        reason: "Supplier part should reference supplier pk",
      );
      expect(
        supBody["SKU"],
        equals("490-1234-1-ND"),
        reason: "Supplier part should have SKU",
      );
      expect(
        supBody["part"],
        equals(1),
        reason: "Supplier part should reference created part pk",
      );
      expect(
        supBody["manufacturer_part"],
        equals(100),
        reason:
            "Supplier part should link to manufacturer part when both are created",
      );

      // Verify stock body contents
      final stockBody = server.requestsTo("POST", r"/api/stock/$").first.body!;
      expect(stockBody["part"], equals(1));
      expect(stockBody["quantity"], equals(50));
    });

    // Case 3: New, bare minimum (existing category, no mfr/supplier/stock)
    test("Case 3: New, bare minimum", () async {
      await _submitPart(
        server,
        name: "Widget",
        description: "A simple widget",
        categoryId: 5,
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/part/category/$"),
        isEmpty,
        reason: "Should NOT create category",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock",
      );
    });
  });

  // =========================================================================
  group("Linked parts", () {
    // Case 4: New, manufacturer only
    test("Case 4: New, manufacturer only", () async {
      await _submitPart(
        server,
        name: "IC Chip",
        description: "An integrated circuit",
        categoryId: 5,
        selectedManufacturerPk: 5,
        mpn: "LM7805",
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isNotEmpty,
        reason: "Should create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock",
      );

      // Verify manufacturer part body contents
      final mfrBody = server
          .requestsTo("POST", r"/api/company/part/manufacturer/$")
          .first
          .body!;
      expect(
        mfrBody["manufacturer"],
        equals(5),
        reason: "Manufacturer part should reference manufacturer pk",
      );
      expect(
        mfrBody["MPN"],
        equals("LM7805"),
        reason: "Manufacturer part should have MPN",
      );
      expect(
        mfrBody["part"],
        equals(1),
        reason: "Manufacturer part should reference created part pk",
      );
    });

    // Case 5: New, supplier only
    test("Case 5: New, supplier only", () async {
      await _submitPart(
        server,
        name: "LED",
        description: "Red LED 5mm",
        categoryId: 5,
        selectedSupplierPk: 6,
        sku: "MOU-LED-RED",
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isNotEmpty,
        reason: "Should create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock",
      );

      // Verify supplier part body contents
      final supBody = server
          .requestsTo("POST", r"/api/company/part/$")
          .first
          .body!;
      expect(
        supBody["supplier"],
        equals(6),
        reason: "Supplier part should reference supplier pk",
      );
      expect(
        supBody["SKU"],
        equals("MOU-LED-RED"),
        reason: "Supplier part should have SKU",
      );
      expect(
        supBody["part"],
        equals(1),
        reason: "Supplier part should reference created part pk",
      );
      expect(
        supBody.containsKey("manufacturer_part"),
        isFalse,
        reason:
            "Supplier part should NOT have manufacturer_part when no manufacturer",
      );
    });

    // Case 9: New, mfr+supplier linked (supplier_part has manufacturer_part FK)
    test("Case 9: New, mfr+supplier linked", () async {
      await _submitPart(
        server,
        name: "MOSFET",
        description: "N-channel MOSFET",
        categoryId: 5,
        selectedManufacturerPk: 5,
        mpn: "IRFZ44N",
        selectedSupplierPk: 6,
        sku: "ARR-IRFZ44N",
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );

      final mfrParts = server.requestsTo(
        "POST",
        r"/api/company/part/manufacturer/$",
      );
      expect(mfrParts, isNotEmpty, reason: "Should create manufacturer part");

      // Verify manufacturer part body contents
      final mfrBody = mfrParts.first.body!;
      expect(
        mfrBody["manufacturer"],
        equals(5),
        reason: "Manufacturer part should reference manufacturer pk",
      );
      expect(
        mfrBody["MPN"],
        equals("IRFZ44N"),
        reason: "Manufacturer part should have MPN",
      );
      expect(
        mfrBody["part"],
        equals(1),
        reason: "Manufacturer part should reference created part pk",
      );

      final supplierParts = server.requestsTo("POST", r"/api/company/part/$");
      expect(supplierParts, isNotEmpty, reason: "Should create supplier part");

      // Verify supplier part body contents
      final supBody = supplierParts.first.body!;
      expect(
        supBody["supplier"],
        equals(6),
        reason: "Supplier part should reference supplier pk",
      );
      expect(
        supBody["SKU"],
        equals("ARR-IRFZ44N"),
        reason: "Supplier part should have SKU",
      );
      expect(
        supBody["part"],
        equals(1),
        reason: "Supplier part should reference created part pk",
      );
      expect(
        supBody["manufacturer_part"],
        equals(100),
        reason:
            "Supplier part should reference manufacturer_part pk from mock response",
      );
    });
  });

  // =========================================================================
  group("Stock creation", () {
    // Case 6: New, stock only
    test("Case 6: New, stock only", () async {
      await _submitPart(
        server,
        name: "Screw",
        description: "M3x10 screw",
        categoryId: 5,
        createStock: true,
        itemCount: 25,
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isNotEmpty,
        reason: "Should create stock",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part",
      );

      // Verify stock body
      final stockReqs = server.requestsTo("POST", r"/api/stock/$");
      expect(stockReqs.first.body?["quantity"], equals(25));
      expect(stockReqs.first.body?["part"], equals(1));
    });

    // Case 10: Stock toggle on but count=0 → no stock POST
    test("Case 10: Stock toggle on, count=0", () async {
      await _submitPart(
        server,
        name: "Nut",
        description: "M3 hex nut",
        categoryId: 5,
        createStock: true,
        itemCount: 0,
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock when count=0",
      );
    });
  });

  // =========================================================================
  group("Category creation", () {
    // Case 7: New, new category only
    test("Case 7: New, new category only", () async {
      await _submitPart(
        server,
        name: "Connector",
        description: "USB-C connector",
        pendingCategoryCreation: "Connectors",
        parentCategoryId: 1,
      );

      expect(
        server.requestsTo("POST", r"/api/part/category/$"),
        isNotEmpty,
        reason: "Should create category",
      );
      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock",
      );

      // Verify category was created before part
      final allPosts = server.requests
          .where((r) => r.method == "POST" && r.path.startsWith("/api/"))
          .toList();
      final catIdx = allPosts.indexWhere(
        (r) => r.path.contains("/part/category/"),
      );
      final partIdx = allPosts.indexWhere((r) => r.path == "/api/part/");
      expect(
        catIdx,
        lessThan(partIdx),
        reason: "Category should be created before part",
      );

      // Verify the part body includes the new category id
      final partReqs = server.requestsTo("POST", r"/api/part/$");
      expect(
        partReqs.first.body?["category"],
        equals(10),
        reason: "Part should use the newly created category pk",
      );
    });

    // Case 14: Category creation fails → part creation still fires (without category)
    test("Case 14: Category creation fails", () async {
      server.respondTo(
        "POST",
        r"/api/part/category/$",
        statusCode: 400,
        body: {
          "name": ["Category already exists"],
        },
      );

      await _submitPart(
        server,
        name: "Diode",
        description: "1N4148 diode",
        pendingCategoryCreation: "Diodes",
        parentCategoryId: 1,
      );

      expect(
        server.requestsTo("POST", r"/api/part/category/$"),
        isNotEmpty,
        reason: "Should attempt category creation",
      );
      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Part should still be created even if category fails",
      );

      // Part body should NOT have a category (since creation failed and no fallback id)
      final partReqs = server.requestsTo("POST", r"/api/part/$");
      expect(
        partReqs.first.body?.containsKey("category"),
        isFalse,
        reason: "Part should not have category when category creation fails",
      );
    });
  });

  // =========================================================================
  group("Duplicate handling", () {
    // Case 8: Duplicate → update existing → PATCH only
    test("Case 8: Duplicate, update existing", () async {
      server.respondTo(
        "PATCH",
        "/api/part/42/",
        statusCode: 200,
        body: {
          "pk": 42,
          "name": "Existing Part",
          "description": "Updated",
          "active": true,
          "thumbnail": "",
          "image": "",
        },
      );

      final success = await _updateExistingPart(
        server,
        partPk: 42,
        description: "Updated description",
        keywords: "test,keywords",
      );

      expect(success, isTrue, reason: "Update should succeed");

      final patches = server.requestsTo("PATCH", "/api/part/42/");
      expect(patches, isNotEmpty, reason: "Should PATCH existing part");
      expect(patches.first.body?["description"], equals("Updated description"));
      expect(patches.first.body?["keywords"], equals("test,keywords"));

      // No POST part/ (not creating a new one)
      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isEmpty,
        reason: "Should NOT create a new part when updating existing",
      );
    });
  });

  // =========================================================================
  group("Edge cases", () {
    // Case 11: Manufacturer selected, no MPN → no manufacturer part creation
    test("Case 11: Mfr selected, no MPN", () async {
      await _submitPart(
        server,
        name: "Resistor",
        description: "10k resistor",
        categoryId: 5,
        selectedManufacturerPk: 5,
        mpn: "", // empty MPN
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part without MPN",
      );
    });

    // Case 12: Supplier selected, no SKU → no supplier part creation
    test("Case 12: Supplier selected, no SKU", () async {
      await _submitPart(
        server,
        name: "Capacitor",
        description: "10uF cap",
        categoryId: 5,
        selectedSupplierPk: 6,
        sku: "", // empty SKU
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should create part",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part without SKU",
      );
    });
  });

  // =========================================================================
  group("Error handling", () {
    // Case 13: Part creation fails → 400, no further calls
    test("Case 13: Part creation fails", () async {
      server.respondTo(
        "POST",
        r"/api/part/$",
        statusCode: 400,
        body: {
          "name": ["A part with this name already exists"],
        },
      );

      final result = await _submitPart(
        server,
        name: "Duplicate Name",
        description: "Should fail",
        categoryId: 5,
        selectedManufacturerPk: 5,
        mpn: "SHOULD-NOT-BE-CREATED",
        selectedSupplierPk: 6,
        sku: "SHOULD-NOT-BE-CREATED",
        createStock: true,
        itemCount: 10,
      );

      expect(
        result,
        isNull,
        reason: "submitPart should return null on failure",
      );

      expect(
        server.requestsTo("POST", r"/api/part/$"),
        isNotEmpty,
        reason: "Should attempt part creation",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/manufacturer/$"),
        isEmpty,
        reason: "Should NOT create manufacturer part after part creation fails",
      );
      expect(
        server.requestsTo("POST", r"/api/company/part/$"),
        isEmpty,
        reason: "Should NOT create supplier part after part creation fails",
      );
      expect(
        server.requestsTo("POST", r"/api/stock/$"),
        isEmpty,
        reason: "Should NOT create stock after part creation fails",
      );
      // Tag injection PATCH should not happen since part creation failed
      expect(
        server.requests.where(
          (r) => r.method == "PATCH" && r.path.startsWith("/api/part/"),
        ),
        isEmpty,
        reason: "Should NOT inject tags after part creation fails",
      );
    });
  });
}
