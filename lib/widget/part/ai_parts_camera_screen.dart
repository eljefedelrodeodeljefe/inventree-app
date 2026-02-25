import "dart:async";
import "dart:io";
import "dart:math";

import "package:camera/camera.dart";
import "package:device_info_plus/device_info_plus.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:path_provider/path_provider.dart";

import "package:inventree/ai/ai_part_queue_service.dart";
import "package:inventree/api.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/widget/part/ai_part_edit_widget.dart";
import "package:inventree/widget/part/ai_part_queue_item_tile.dart";
import "package:inventree/widget/snacks.dart";
import "package:inventree/l10.dart";

class AIPartsCameraScreen extends StatefulWidget {
  const AIPartsCameraScreen({
    Key? key,
    this.categoryId,
    this.categoryName,
    this.subCategories,
  }) : super(key: key);

  final int? categoryId;
  final String? categoryName;
  final Map<String, int>? subCategories;

  @override
  _AIPartsCameraScreenState createState() => _AIPartsCameraScreenState();
}

class _AIPartsCameraScreenState extends State<AIPartsCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isTakingPicture = false;
  FlashMode _flashMode = FlashMode.off;

  // Emulator dev mode
  bool _isEmulator = false;
  final List<String> _fixtureAssets = const [
    "test/fixtures/ai_parts/part_01.jpg",
    "test/fixtures/ai_parts/part_02.jpg",
    "test/fixtures/ai_parts/part_03.jpg",
    "test/fixtures/ai_parts/part_04.jpg",
  ];
  int _currentFixtureIndex = 0;
  Timer? _fixtureTimer;
  final Random _random = Random();

  final AIPartQueueService _queueService = AIPartQueueService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueService.initialize(
      categoryNames: widget.subCategories?.keys.toList(),
    );
    _queueService.addListener(_onQueueChanged);
    _detectEmulatorAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fixtureTimer?.cancel();
    _queueService.removeListener(_onQueueChanged);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _detectEmulatorAndInit() async {
    bool emulator = false;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        emulator = !android.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        emulator = !ios.isPhysicalDevice;
      }
    } catch (_) {}

    if (emulator) {
      _isEmulator = true;
      _startFixtureCycling();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } else {
      _initializeCamera();
    }
  }

  void _startFixtureCycling() {
    _fixtureTimer = Timer.periodic(Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _currentFixtureIndex = _random.nextInt(_fixtureAssets.length);
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isEmulator) return;

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _onQueueChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        showSnackIcon(L10().aiNoCameras, success: false);
        return;
      }

      // Prefer back camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      sentryReportError("AIPartsCameraScreen._initializeCamera", e, stackTrace);
      showSnackIcon(L10().aiCameraInitFailed, success: false);
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture) return;

    setState(() {
      _isTakingPicture = true;
    });

    try {
      if (_isEmulator) {
        await _enqueueFixtureImage();
      } else {
        if (_cameraController == null ||
            !_cameraController!.value.isInitialized) {
          return;
        }
        final xFile = await _cameraController!.takePicture();
        _queueService.enqueue(File(xFile.path));
      }
    } catch (e, stackTrace) {
      sentryReportError("AIPartsCameraScreen._takePicture", e, stackTrace);
      showSnackIcon(L10().aiTakePictureFailed, success: false);
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _enqueueFixtureImage() async {
    final assetPath = _fixtureAssets[_currentFixtureIndex];
    final bytes = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File("${tempDir.path}/fixture_$timestamp.jpg");
    await tempFile.writeAsBytes(bytes.buffer.asUint8List());
    _queueService.enqueue(tempFile);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    final newMode = _flashMode == FlashMode.off
        ? FlashMode.torch
        : FlashMode.off;

    try {
      await _cameraController!.setFlashMode(newMode);
      setState(() {
        _flashMode = newMode;
      });
    } catch (e) {
      // Some devices don't support flash
    }
  }

  Future<void> _onItemTap(AIPartQueueItem item) async {
    if (item.status == AIPartQueueStatus.success && item.result != null) {
      // Resolve AI-suggested category to an ID from sub-categories
      int? resolvedCategoryId = widget.categoryId;
      String? resolvedCategoryName;
      final suggestion = item.result!.categoryName;
      if (suggestion != null && suggestion.isNotEmpty) {
        if (widget.subCategories != null) {
          // Try exact match first, then contains match
          final exactMatch = widget.subCategories!.entries
              .where((e) => e.key.toLowerCase() == suggestion.toLowerCase())
              .firstOrNull;
          if (exactMatch != null) {
            resolvedCategoryId = exactMatch.value;
            resolvedCategoryName = exactMatch.key;
          } else {
            final fuzzyMatch = widget.subCategories!.entries
                .where(
                  (e) =>
                      e.key.toLowerCase().contains(suggestion.toLowerCase()) ||
                      suggestion.toLowerCase().contains(e.key.toLowerCase()),
                )
                .firstOrNull;
            if (fuzzyMatch != null) {
              resolvedCategoryId = fuzzyMatch.value;
              resolvedCategoryName = fuzzyMatch.key;
            }
          }
        }

        // No match found — create the sub-category
        if (resolvedCategoryName == null) {
          final created = await _createCategory(suggestion, widget.categoryId);
          if (created != null) {
            resolvedCategoryId = created;
            resolvedCategoryName = suggestion;
          }
        }
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AIPartEditWidget(
            imageFile: item.imageFile,
            result: item.result!,
            categoryId: resolvedCategoryId,
            categoryName: resolvedCategoryName,
            parentCategoryId: widget.categoryId,
            parentCategoryName: widget.categoryName,
            subCategories: widget.subCategories,
            onSubmitted: () {
              _queueService.removeItem(item.id);
            },
          ),
        ),
      );
    } else if (item.status == AIPartQueueStatus.error) {
      _queueService.retryItem(item.id);
    }
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
      sentryReportError("AIPartsCameraScreen._createCategory", e, stackTrace);
    }
    return null;
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_isEmulator) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(_fixtureAssets[_currentFixtureIndex], fit: BoxFit.cover),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "EMULATOR",
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 0,
            height: _cameraController!.value.previewSize?.width ?? 0,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueList() {
    final items = _queueService.items;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(TablerIcons.camera, size: 48, color: COLOR_GRAY_LIGHT),
            SizedBox(height: 12),
            Text(
              L10().aiPartsTakePhoto,
              style: TextStyle(color: COLOR_GRAY_LIGHT, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _2) => Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return AIPartQueueItemTile(
          item: item,
          onTap: () => _onItemTap(item),
          onDismissed: () => _queueService.removeItem(item.id),
        );
      },
    );
  }

  Widget _buildShutterButton() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: GestureDetector(
          onTap: _takePicture,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: COLOR_ACTION, width: 4),
            ),
            child: Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isTakingPicture ? Colors.grey : COLOR_ACTION,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final cameraHeight = screenHeight * 0.35;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10().aiParts),
        backgroundColor: COLOR_APP_BAR,
        actions: [
          if (_queueService.items.isNotEmpty)
            IconButton(
              icon: Icon(TablerIcons.trash_x),
              tooltip: L10().aiClearAll,
              onPressed: () => _queueService.clearAll(),
            ),
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.off
                  ? TablerIcons.bolt_off
                  : TablerIcons.bolt,
            ),
            tooltip: L10().aiToggleFlash,
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Camera preview
            SizedBox(
              height: cameraHeight,
              width: double.infinity,
              child: _buildCameraPreview(),
            ),
            // Queue list
            Expanded(child: _buildQueueList()),
            // Shutter button
            _buildShutterButton(),
          ],
        ),
      ),
    );
  }
}
