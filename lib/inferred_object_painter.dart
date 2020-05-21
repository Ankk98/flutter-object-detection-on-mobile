import 'package:flutter/material.dart';

/// Class to paint the inferred rectangle on the top of image displayed.
class InferredObjectPainter extends CustomPainter {
  Map _savedRectangle;
  InferredObjectPainter(this._savedRectangle);

  @override
  void paint(Canvas canvas, Size size) {
    if (_savedRectangle != null) {
      final paint = Paint();
      paint.color = Colors.green;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3.0;
      double x, y, w, h;
      x = _savedRectangle["x"] * size.width;
      y = _savedRectangle["y"] * size.height;
      w = _savedRectangle["w"] * size.width;
      h = _savedRectangle["h"] * size.height;
      Rect myRect = Offset(x, y) & Size(w, h);
      canvas.drawRect(myRect, paint);
    }
  }

  @override
  bool shouldRepaint(InferredObjectPainter oldDelegate) =>
      oldDelegate._savedRectangle != _savedRectangle;

  @override
  bool shouldRebuildSemantics(InferredObjectPainter oldDelegate) => false;
}
