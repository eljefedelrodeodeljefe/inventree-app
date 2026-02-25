import "dart:async";
import "dart:io";
import "dart:math";

import "package:camera/camera.dart";
import "package:device_info_plus/device_info_plus.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:path_provider/path_provider.dart";

import "package:inventree/ai/ai_factory.dart";
import "package:inventree/ai/ai_service.dart";
import "package:inventree/helpers/step_sizes.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/helpers.dart";
import "package:inventree/l10.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/widget/snacks.dart";

class AIStockScreen extends StatefulWidget {
  const AIStockScreen({Key? key, required this.stockItem}) : super(key: key);

  final InvenTreeStockItem stockItem;

  @override
  _AIStockScreenState createState() => _AIStockScreenState();
}

class _AIStockScreenState extends State<AIStockScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isTakingPicture = false;
  FlashMode _flashMode = FlashMode.off;

  // Emulator dev mode
  bool _isEmulator = false;
  final List<String> _fixtureAssets = const [
    "test/fixtures/ai_stock/stock_01.jpg",
    "test/fixtures/ai_stock/stock_02.jpg",
  ];
  int _currentFixtureIndex = 0;
  Timer? _fixtureTimer;
  final Random _random = Random();

  // Analysis state
  bool _analyzing = false;
  bool _adjusting = false;
  AIStockCountResult? _result;
  File? _capturedImage;
  String? _errorMessage;
  String? _errorDetail;
  int _adjustedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectEmulatorAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fixtureTimer?.cancel();
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

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        showSnackIcon(L10().aiNoCameras, success: false);
        return;
      }

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
      sentryReportError("AIStockScreen._initializeCamera", e, stackTrace);
      showSnackIcon(L10().aiCameraInitFailed, success: false);
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture || _analyzing) return;

    setState(() {
      _isTakingPicture = true;
    });

    try {
      File imageFile;

      if (_isEmulator) {
        final assetPath = _fixtureAssets[_currentFixtureIndex];
        final bytes = await rootBundle.load(assetPath);
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File("${tempDir.path}/stock_count_$timestamp.jpg");
        await tempFile.writeAsBytes(bytes.buffer.asUint8List());
        imageFile = tempFile;
      } else {
        if (_cameraController == null ||
            !_cameraController!.value.isInitialized) {
          return;
        }
        final xFile = await _cameraController!.takePicture();
        imageFile = File(xFile.path);
      }

      setState(() {
        _isTakingPicture = false;
        _capturedImage = imageFile;
        _result = null;
        _errorMessage = null;
        _errorDetail = null;
        _analyzing = true;
      });

      await _analyzeImage(imageFile);
    } catch (e, stackTrace) {
      sentryReportError("AIStockScreen._takePicture", e, stackTrace);
      showSnackIcon(L10().aiTakePictureFailed, success: false);
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _analyzeImage(File imageFile) async {
    try {
      final service = await AIServiceFactory.create();
      if (service == null) {
        setState(() {
          _analyzing = false;
          _errorMessage = L10().aiServiceNotConfigured;
        });
        return;
      }

      final result = await service.analyzeStockCount(
        imageFile,
        partName: widget.stockItem.partName,
      );

      if (mounted) {
        setState(() {
          _analyzing = false;
          _result = result;
          _adjustedCount = result.count;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _errorMessage = L10().aiImageAnalysisFailed;
          _errorDetail = e.toString();
        });
      }
    }
  }

  Future<void> _performAdjustment(String action) async {
    if (_result == null || _adjusting) return;

    setState(() {
      _adjusting = true;
    });

    try {
      bool success = false;
      final count = _adjustedCount.toDouble();

      switch (action) {
        case "count":
          success = await widget.stockItem.countStock(
            count,
            notes: "AI stock count",
          );
        case "add":
          success = await widget.stockItem.addStock(
            count,
            notes: "AI stock count",
          );
        case "remove":
          success = await widget.stockItem.removeStock(
            count,
            notes: "AI stock count",
          );
      }

      if (success) {
        showSnackIcon(L10().aiStockUpdated, success: true);
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        showSnackIcon(L10().aiStockUpdateFailed, success: false);
      }
    } catch (e) {
      showSnackIcon(L10().aiStockUpdateFailed, success: false);
    } finally {
      if (mounted) {
        setState(() {
          _adjusting = false;
        });
      }
    }
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

  Widget _buildMiddleArea() {
    if (_analyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              L10().aiStockCounting,
              style: TextStyle(color: COLOR_GRAY_LIGHT, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(TablerIcons.alert_circle, size: 48, color: COLOR_DANGER),
            SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: COLOR_DANGER,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (_capturedImage != null) {
                  setState(() {
                    _errorMessage = null;
                    _errorDetail = null;
                    _analyzing = true;
                  });
                  _analyzeImage(_capturedImage!);
                }
              },
              icon: Icon(TablerIcons.refresh),
              label: Text(L10().aiRetry),
            ),
            if (_errorDetail != null) ...[
              SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  L10().details,
                  style: TextStyle(fontSize: 13, color: COLOR_GRAY_LIGHT),
                ),
                tilePadding: EdgeInsets.zero,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _errorDetail!,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: "monospace",
                        color: COLOR_GRAY_LIGHT,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    if (_result != null && _capturedImage != null) {
      return _buildResultCard();
    }

    // Default: before capture
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(TablerIcons.camera, size: 48, color: COLOR_GRAY_LIGHT),
          SizedBox(height: 12),
          Text(
            L10().aiStockTakePhoto,
            style: TextStyle(color: COLOR_GRAY_LIGHT, fontSize: 16),
          ),
        ],
      ),
    );
  }

  List<int> _stepSizes() => computeStepSizes(_adjustedCount);

  Widget _buildAdjustPanel() {
    final steps = _stepSizes();
    return Column(
      children: [
        SizedBox(height: 12),
        Row(
          children: [
            Text(
              L10().aiStockAdjustCount,
              style: TextStyle(fontSize: 13, color: COLOR_GRAY_LIGHT),
            ),
            Spacer(),
            if (_adjustedCount != _result!.count)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _adjustedCount = _result!.count;
                  });
                },
                child: Text(
                  L10().aiStockReset,
                  style: TextStyle(fontSize: 13, color: COLOR_ACTION),
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            for (final step in steps.reversed)
              Expanded(child: _stepButton(-step)),
            SizedBox(width: 12),
            for (int i = 0; i < steps.length; i++)
              Expanded(child: _stepButton(steps[i])),
          ],
        ),
      ],
    );
  }

  Widget _stepButton(int delta) {
    final label = delta > 0 ? "+$delta" : "$delta";
    final isNegative = delta < 0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              _adjustedCount = max(0, _adjustedCount + delta);
            });
          },
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: isNegative ? Colors.red : Colors.green,
            side: BorderSide(
              color: (isNegative ? Colors.red : Colors.green).withValues(
                alpha: 0.4,
              ),
            ),
          ),
          child: Text(label, style: TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    final currentQty = widget.stockItem.quantity;

    String confidenceLabel;
    Color confidenceColor;
    if (result.confidence >= 0.8) {
      confidenceLabel = L10().aiConfidenceHigh;
      confidenceColor = COLOR_SUCCESS;
    } else if (result.confidence >= 0.5) {
      confidenceLabel = L10().aiConfidenceMedium;
      confidenceColor = COLOR_WARNING;
    } else {
      confidenceLabel = L10().aiConfidenceLow;
      confidenceColor = COLOR_DANGER;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail + count
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _capturedImage!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              "${result.count}",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              L10().aiStockItemsCounted,
                              style: TextStyle(
                                fontSize: 16,
                                color: COLOR_GRAY_LIGHT,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: confidenceColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            L10().aiConfidenceLabel(confidenceLabel),
                            style: TextStyle(
                              color: confidenceColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Description
              if (result.description != null &&
                  result.description!.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  result.description!,
                  style: TextStyle(color: COLOR_GRAY_LIGHT),
                ),
              ],
              Divider(height: 24),
              // Current stock
              Text(
                L10().aiCurrentStock(simpleNumberString(currentQty)),
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              // Action buttons
              if (_adjusting)
                Center(child: CircularProgressIndicator())
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _performAdjustment("count"),
                        icon: Icon(TablerIcons.circle_check, size: 18),
                        label: Text(
                          "=$_adjustedCount",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _performAdjustment("remove"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(TablerIcons.minus, size: 18),
                        label: Text(
                          "$_adjustedCount",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _performAdjustment("add"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(TablerIcons.plus, size: 18),
                    label: Text(
                      "${L10().add} $_adjustedCount",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _buildAdjustPanel(),
              ],
            ],
          ),
        ),
      ),
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
                  color: (_isTakingPicture || _analyzing)
                      ? Colors.grey
                      : COLOR_ACTION,
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
        title: Text(L10().aiStockCount),
        backgroundColor: COLOR_APP_BAR,
        actions: [
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
            SizedBox(
              height: cameraHeight,
              width: double.infinity,
              child: _buildCameraPreview(),
            ),
            Expanded(child: _buildMiddleArea()),
            _buildShutterButton(),
          ],
        ),
      ),
    );
  }
}
