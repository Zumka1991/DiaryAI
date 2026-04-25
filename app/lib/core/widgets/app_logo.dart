import 'package:flutter/material.dart';

import '../theme.dart';

/// Уникальный логотип DiaryAI: открытая книга с искрой над ней.
/// Рисуется кастомным painter'ом, без растровых ассетов.
class AppLogo extends StatelessWidget {
  final double size;
  final bool withGlow;

  const AppLogo({super.key, this.size = 96, this.withGlow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: withGlow
            ? [
                BoxShadow(
                  color: AppColors.lavender.withValues(alpha: 0.45),
                  blurRadius: size * 0.32,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _DiaryLogoPainter(),
      ),
    );
  }
}

class _DiaryLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ========= Открытая книга (два «крыла» страниц) =========
    final pagePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final pageStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = w * 0.012
      ..style = PaintingStyle.stroke;

    // Левая страница
    final leftPage = Path()
      ..moveTo(cx, cy + h * 0.10)            // нижняя точка корешка
      ..quadraticBezierTo(cx - w * 0.20, cy + h * 0.05, cx - w * 0.32, cy - h * 0.02)
      ..lineTo(cx - w * 0.32, cy - h * 0.18)
      ..quadraticBezierTo(cx - w * 0.20, cy - h * 0.16, cx, cy - h * 0.06)
      ..close();

    // Правая страница (зеркальная)
    final rightPage = Path()
      ..moveTo(cx, cy + h * 0.10)
      ..quadraticBezierTo(cx + w * 0.20, cy + h * 0.05, cx + w * 0.32, cy - h * 0.02)
      ..lineTo(cx + w * 0.32, cy - h * 0.18)
      ..quadraticBezierTo(cx + w * 0.20, cy - h * 0.16, cx, cy - h * 0.06)
      ..close();

    canvas.drawPath(leftPage, pagePaint);
    canvas.drawPath(rightPage, pagePaint);
    canvas.drawPath(leftPage, pageStroke);
    canvas.drawPath(rightPage, pageStroke);

    // Корешок — лёгкая вертикальная линия по центру
    canvas.drawLine(
      Offset(cx, cy - h * 0.06),
      Offset(cx, cy + h * 0.10),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = w * 0.014,
    );

    // ========= Искра (символ ИИ-анализа) над книгой =========
    final sparkleCx = cx + w * 0.05;
    final sparkleCy = cy - h * 0.30;
    _drawSparkle(canvas, Offset(sparkleCx, sparkleCy), w * 0.08, Colors.white);
    // маленькая вторая искра
    _drawSparkle(canvas, Offset(sparkleCx - w * 0.14, sparkleCy + h * 0.05), w * 0.04,
        Colors.white.withValues(alpha: 0.85));
  }

  void _drawSparkle(Canvas canvas, Offset c, double radius, Color color) {
    final p = Path();
    // 4-конечная искра (как в Material auto_awesome)
    p.moveTo(c.dx, c.dy - radius);
    p.quadraticBezierTo(c.dx + radius * 0.18, c.dy - radius * 0.18, c.dx + radius, c.dy);
    p.quadraticBezierTo(c.dx + radius * 0.18, c.dy + radius * 0.18, c.dx, c.dy + radius);
    p.quadraticBezierTo(c.dx - radius * 0.18, c.dy + radius * 0.18, c.dx - radius, c.dy);
    p.quadraticBezierTo(c.dx - radius * 0.18, c.dy - radius * 0.18, c.dx, c.dy - radius);
    p.close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
