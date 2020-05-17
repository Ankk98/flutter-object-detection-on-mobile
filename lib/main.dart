import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;

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
  var cameraInitialized = false;
  CameraImage savedImage;
  var isProcessing = false;
  imglib.Image convertedImage;
  var showSnapshot = false;
  Uint8List snapShot;

  //copied
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    initializeCamera();
  }

  void procesCameraImage(image) async {
    if (isProcessing) {
      return;
    }
    isProcessing = true;

    // perform object detection

    setState(() {
      savedImage = image;
    });

    isProcessing = false;
  }

  void initializeCamera() async {
    List<CameraDescription> cameras;
    cameras = await availableCameras();
    statusText = 'Waiting for the camera initialization';
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    _cameraController.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      cameraInitialized = true;
      await _cameraController
          .startImageStream((CameraImage image) => procesCameraImage(image));
      statusText = 'Camera initialized';
      setState(() {});
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void startProcessing() {
    //convert
    convertedImage = _convertCameraImage(savedImage);
    // convertedImage = imglib.copyRotate(convertedImage, 90);
    convertedImage = imglib.copyResize(
      convertedImage,
      height: MediaQuery.of(context).size.height.toInt(),
    );
    snapShot = imglib.encodePng(convertedImage);
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
            Text(statusText),
            cameraInitialized
                ? showSnapshot == false
                    ? Expanded(
                        child: OverflowBox(
                          child: AspectRatio(
                            aspectRatio: _cameraController.value.aspectRatio,
                            child: CameraPreview(_cameraController),
                          ),
                        ),
                      )
                    : Image.memory(snapShot)
                : Container(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: startProcessing,
        backgroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// Future<void> main() async {

//   // to fix asyn error
//   WidgetsFlutterBinding.ensureInitialized();

//   cameras = await availableCameras();
//   runApp(MyApp());
// }

// if (!_cameraController.value.isInitialized) {
//       return Container();
//     }
//     return ;
