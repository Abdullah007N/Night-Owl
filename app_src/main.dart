import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// ======= النصوص الجاهزة (غيّر فيها زي ما تحب) =======
const List<String> kMessages = [
  'OBEY',
  'CONSUME',
  'STAY ASLEEP',
  'NO INDEPENDENT THOUGHT',
  'CONFORM',
  'BUY',
  'SUBMIT',
  'WATCH TV',
  'MARRY AND REPRODUCE',
  'DO NOT QUESTION AUTHORITY',
  'NO THOUGHT',
  'SPEND MORE',
];

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _cameras = await availableCameras();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ObeyScreen(),
  ));
}

class ObeyScreen extends StatefulWidget {
  const ObeyScreen({super.key});

  @override
  State<ObeyScreen> createState() => _ObeyScreenState();
}

class _ObeyScreenState extends State<ObeyScreen> {
  CameraController? _controller;
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool _glassesOn = true;
  bool _busy = false;
  int _lastRun = 0;
  int _emptyFrames = 0;

  List<_Hit> _hits = [];
  Size _uprightSize = const Size(720, 1280);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final back = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() => _controller = controller);
    await controller.startImageStream(_onFrame);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!_glassesOn || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRun < 250) return; // 4 مرات في الثانية تقريباً
    _lastRun = now;
    _busy = true;

    try {
      final controller = _controller!;
      final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation);
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (rotation == null || format == null) return;

      final input = InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final result = await _recognizer.processImage(input);

      final swap = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final upright = swap
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      final hits = <_Hit>[];
      for (final block in result.blocks) {
        final r = block.boundingBox;
        if (r.width < 40 || r.height < 18) continue; // تجاهل الصغير جداً
        final msg = kMessages[block.text.hashCode.abs() % kMessages.length];
        hits.add(_Hit(r, msg));
      }

      if (!mounted) return;
      if (hits.isEmpty) {
        _emptyFrames++;
        if (_emptyFrames < 3) return; // يمنع الوميض
      } else {
        _emptyFrames = 0;
      }
      setState(() {
        _hits = hits;
        _uprightSize = upright;
      });
    } catch (_) {
      // تجاهل أخطاء الفريم الواحد
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  // فلتر أبيض وأسود بكونتراست عالي
  static ColorFilter _bwFilter() {
    const c = 1.7;
    const t = (-0.5 * c + 0.5) * 255;
    return const ColorFilter.matrix(<double>[
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, t, //
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, t,
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, t,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    Widget preview = CameraPreview(controller);
    if (_glassesOn) {
      preview = ColorFiltered(colorFilter: _bwFilter(), child: preview);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _uprightSize.width,
              height: _uprightSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  if (_glassesOn)
                    CustomPaint(painter: _OverlayPainter(_hits)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () => setState(() {
                  _glassesOn = !_glassesOn;
                  if (!_glassesOn) _hits = [];
                }),
                icon: Icon(_glassesOn ? Icons.visibility : Icons.visibility_off),
                label: Text(_glassesOn ? 'TAKE OFF GLASSES' : 'PUT ON GLASSES'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hit {
  final Rect rect;
  final String message;
  _Hit(this.rect, this.message);
}

class _OverlayPainter extends CustomPainter {
  final List<_Hit> hits;
  _OverlayPainter(this.hits);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final h in hits) {
      final r = h.rect.inflate(6);
      canvas.drawRect(r, bg);
      canvas.drawRect(r, border);

      final tp = TextPainter(
        text: TextSpan(
          text: h.message,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: r.height * 0.7,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // لو النص أعرض من المربع صغّره
      final scale = tp.width > r.width * 0.92 ? (r.width * 0.92) / tp.width : 1.0;
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.scale(scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.hits != hits;
}
