import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
    if (now - _lastRun < 250) return;
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
        if (r.width < 40 || r.height < 18) continue;
        final msg = kMessages[block.text.hashCode.abs() % kMessages.length];
        hits.add(_Hit(r, msg));
      }

      if (!mounted) return;
      if (hits.isEmpty) {
        _emptyFrames++;
        if (_emptyFrames < 3) return;
      } else {
        _emptyFrames = 0;
      }
      setState(() {
        _hits = hits;
        _uprightSize = upright;
      });
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _recognizer.close();
    super.di
