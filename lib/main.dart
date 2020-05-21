import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite/tflite.dart';
import 'package:image_save/image_save.dart';

import 'inferred_object_painter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  CameraController _cameraController;

  /// Text to be displayed when showing camera preview.
  var _statusText = '';
  var _isCameraInitialized = false;
  CameraImage _savedImage;
  var _isProcessing = false;
  imglib.Image _convertedImage;
  var _showSnapshot = false;
  Uint8List _snapShot;

  /// Dimentions of rectangle to be dsiplayed.
  Map _savedRectangle;
  var _isTfLiteBusy = false;

  /// Displayed with captured image.
  var _imageText = '';

  /// Change this enum to change preset resolution.
  var _resolution = ResolutionPreset.medium;

  var _buttonColor = Colors.white;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _cameraController.dispose();
      _isCameraInitialized = false;
    }
    if (state == AppLifecycleState.resumed) {
      _resumeCamera();
    }
    print(state);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Takes permissions, load model, initializes the camera with medium resoulution and starts streaming camera output.
  void _initializeCamera() async {
    await Permission.camera.request();
    await Permission.storage.request();

    await Tflite.loadModel(
        model: 'assets/tflite/detect.tflite',
        labels: 'assets/tflite/labelmap.txt',
        numThreads: 1);

    List<CameraDescription> cameras;
    cameras = await availableCameras();
    _statusText = 'Waiting for the camera initialization';
    _cameraController = CameraController(cameras[0], _resolution);
    _cameraController.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      _isCameraInitialized = true;
      await _cameraController
          .startImageStream((CameraImage image) => _processCameraImage(image));
      _statusText = 'Camera initialized';
      setState(() {});
    });
  }

  /// To reinitialize camera and object inference after the app gets resumed.
  void _resumeCamera() async {
    List<CameraDescription> cameras;
    cameras = await availableCameras();
    _statusText = 'Waiting for the camera initialization';
    _cameraController = CameraController(cameras[0], _resolution);
    _cameraController.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      _isCameraInitialized = true;
      await _cameraController
          .startImageStream((CameraImage image) => _processCameraImage(image));
      _statusText = 'Camera initialized';
      setState(() {});
    });
  }

  /// To process live camera output & perform inferrence(object detection) every 0.5 seconds and sets state.
  void _processCameraImage(image) async {
    // To prevent parallel predictions that might require extra resources.
    if (_isProcessing) {
      return;
    }
    _isProcessing = true;

    // perform object detection
    Future<Map<dynamic, dynamic>> detectObjectsFuture = _detectObjects(image);
    List results = await Future.wait([
      detectObjectsFuture,
      Future.delayed(Duration(milliseconds: 500)),
    ]);

    setState(() {
      _savedImage = image;
      _savedRectangle = results[0];
    });

    _isProcessing = false;
  }

  /// Takes snapshot and saves image to gallery when the button is pressed.
  void _takeSnapshot() async {
    if (_showSnapshot == true) {
      setState(() {
        _showSnapshot = false;
      });
      return;
    }
    //convert
    _imageText = _statusText;
    _convertedImage = _convertCameraImage(_savedImage);
    _convertedImage = imglib.copyResize(
      _convertedImage,
      height: MediaQuery.of(context).size.height.toInt(),
    );
    _snapShot = imglib.encodePng(_convertedImage);

    //save to gallery
    await ImageSave.saveImage(_snapShot, "png");

    //show saved image
    setState(() {
      _showSnapshot = true;
    });
  }

  /// Portrait mode view
  Widget _buildPortraitContent(double height, AppBar appBar) {
    return Container(
      height: height,
      child: _isCameraInitialized
          ? (_showSnapshot == false)
              ? AspectRatio(
                  aspectRatio: _cameraController.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CameraPreview(_cameraController),
                      CustomPaint(
                        painter: InferredObjectPainter(_savedRectangle),
                      ),
                      (_showSnapshot == false)
                          ? Text(
                              _statusText,
                              style: TextStyle(
                                backgroundColor: _buttonColor,
                              ),
                            )
                          : Text(_imageText),
                    ],
                  ),
                )
              : Image.memory(_snapShot)
          : Container(),
    );
  }

  /// Landscape mode view
  Widget _buildLandscapeContent(double height, AppBar appBar) {
    return Container(
      height: height,
      child: Text(
        'Under development',
      ),
    );
  }

  /// App bar
  Widget _buildAppBar() {
    return AppBar(
      title: Text('Object detection app'),
      actions: <Widget>[
        (_showSnapshot == true)
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  setState(
                    () {
                      _showSnapshot = false;
                    },
                  );
                },
              )
            : Container(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    AppBar appBar = _buildAppBar();
    final height = (mediaQuery.size.height -
        appBar.preferredSize.height -
        mediaQuery.padding.top);

    return Scaffold(
      appBar: appBar,
      body: (isLandscape == false)
          ? _buildPortraitContent(height, appBar)
          : _buildLandscapeContent(height, appBar),
      floatingActionButton: _showSnapshot
          ? Container()
          : FloatingActionButton(
              onPressed: _takeSnapshot,
              backgroundColor: Colors.white,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// To detect object with highest prediction score in the CamreaImages object provided.
  Future<Map> _detectObjects(CameraImage image) async {
    if (_isTfLiteBusy) {
      return null;
    }
    _isTfLiteBusy = true;

    List resultList = await Tflite.detectObjectOnFrame(
      bytesList: image.planes.map((plane) {
        return plane.bytes;
      }).toList(),
      model: "SSDMobileNet",
      imageHeight: image.height,
      imageWidth: image.width,
      imageMean: 127.5,
      imageStd: 127.5,
      threshold: 0.2,
    );

    _isTfLiteBusy = false;

    Map resultLabel;
    double resultScore = 0.0;
    for (int i = 0; i < resultList.length; i++) {
      Map currLabel = resultList[i];
      double currScore = currLabel['confidenceInClass'];
      if (currScore > 0.6) {
        if (currScore > resultScore) {
          resultLabel = currLabel;
        }
      }
    }

    if (resultLabel != null) {
      _statusText = 'Class: ' +
          resultLabel['detectedClass'].toString() +
          ' Score: ' +
          resultLabel['confidenceInClass'].toString();
    } else {
      _statusText = 'No object found';
      resultLabel = {
        'rect': {'x': 0.0, 'y': 0.0, 'w': 0.0, 'h': 0.0}
      };
    }

    return resultLabel['rect'];
  }

  /// To convert CameraImage object to Image object. (Copied)
  static imglib.Image _convertCameraImage(CameraImage image) {
    int width = image.width;
    int height = image.height;
    // imglib -> Image package from https://pub.dartlang.org/packages/image
    var img = imglib.Image(width, height); // Create Image buffer
    const int hexFF = 0xFF000000;
    final int uvyButtonStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel;
    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvyButtonStride * (y / 2).floor();
        final int index = y * width + x;
        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        // Calculate pixel color
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        // color: 0x FF  FF  FF  FF
        //           A   B   G   R
        img.data[index] = hexFF | (b << 16) | (g << 8) | r;
      }
    }
    // Rotate 90 degrees to upright
    var img1 = imglib.copyRotate(img, 90);
    return img1;
  }
}
