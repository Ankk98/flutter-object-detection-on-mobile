import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite/tflite.dart';
import 'package:image_save/image_save.dart';

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

class _MyHomePageState extends State<MyHomePage> {
  CameraController _cameraController;
  var statusText = '';
  var isCameraInitialized = false;
  CameraImage savedImage;
  var isProcessing = false;
  imglib.Image convertedImage;
  var showSnapshot = false;
  Uint8List snapShot;
  Map savedRectangle;
  var tfLiteBusy = false;
  var imageText = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    initializeCamera();
  }

  // Takes permissions, load model,
  // initialize camera with medium resoulution and starts streaming camera output
  void initializeCamera() async {
    await Permission.camera.request();
    await Permission.storage.request();

    await Tflite.loadModel(
        model: 'assets/tflite/detect.tflite',
        labels: 'assets/tflite/labelmap.txt',
        numThreads: 1);

    List<CameraDescription> cameras;
    cameras = await availableCameras();
    statusText = 'Waiting for the camera initialization';
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    _cameraController.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      isCameraInitialized = true;
      await _cameraController
          .startImageStream((CameraImage image) => processCameraImage(image));
      statusText = 'Camera initialized';
      setState(() {});
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  // To process live camera output & perform inferrence(object detection) every 0.5 seconds and sets state
  void processCameraImage(image) async {
    if (isProcessing) {
      return;
    }
    isProcessing = true;

    // perform object detection
    Future<Map<dynamic, dynamic>> detectObjectsFuture = detectObjects(image);
    List results = await Future.wait([
      detectObjectsFuture,
      Future.delayed(Duration(milliseconds: 500)),
    ]);
    setState(() {
      savedImage = image;
      savedRectangle = results[0];
    });

    isProcessing = false;
  }

  // takes snapshot and saves image to gallery when button is pressed
  void takeSnapshot() async {
    if (showSnapshot == true) {
      setState(() {
        showSnapshot = false;
      });
      return;
    }
    //draw on picture
    //convert
    imageText = statusText;
    convertedImage = _convertCameraImage(savedImage);
    convertedImage = imglib.copyResize(
      convertedImage,
      height: MediaQuery.of(context).size.height.toInt(),
    );
    snapShot = imglib.encodePng(convertedImage);

    //save to gallery
    bool success = await ImageSave.saveImage(snapShot, "png");
    if (success) {
      // imageText += 'saved';
    }
    //show saved image
    setState(() {
      showSnapshot = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Object detection app'),
      ),
      body: Container(
        child: Column(
          children: <Widget>[
            (showSnapshot == false) ? Text(statusText) : Text(imageText),
            isCameraInitialized
                ? (showSnapshot == false)
                    ? Expanded(
                        child: OverflowBox(
                          child: AspectRatio(
                            aspectRatio: _cameraController.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                CameraPreview(_cameraController),
                                CustomPaint(
                                  painter:
                                      InferredObjectPainter(savedRectangle),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Image.memory(snapShot)
                : Container(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: takeSnapshot,
        backgroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<Map> detectObjects(CameraImage image) async {
    if (tfLiteBusy) {
      return null;
    }
    tfLiteBusy = true;

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

    tfLiteBusy = false;

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
      statusText = 'Class: ' +
          resultLabel['detectedClass'].toString() +
          ' Score: ' +
          resultLabel['confidenceInClass'].toString();
    } else {
      statusText = 'No object found';
      resultLabel = {
        'rect': {'x': 0.0, 'y': 0.0, 'w': 0.0, 'h': 0.0}
      };
    }

    return resultLabel['rect'];
  }

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

class InferredObjectPainter extends CustomPainter {
  Map savedRectangle;
  InferredObjectPainter(this.savedRectangle);

  @override
  void paint(Canvas canvas, Size size) {
    if (savedRectangle != null) {
      final paint = Paint();
      paint.color = Colors.green;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3.0;
      double x, y, w, h;
      x = savedRectangle["x"] * size.width;
      y = savedRectangle["y"] * size.height;
      w = savedRectangle["w"] * size.width;
      h = savedRectangle["h"] * size.height;
      Rect myRect = Offset(x, y) & Size(w, h);
      canvas.drawRect(myRect, paint);
    }
  }

  @override
  bool shouldRepaint(InferredObjectPainter oldDelegate) =>
      oldDelegate.savedRectangle != savedRectangle;

  @override
  bool shouldRebuildSemantics(InferredObjectPainter oldDelegate) => false;
}
