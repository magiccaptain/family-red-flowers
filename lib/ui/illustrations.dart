import 'dart:math' as math;

import 'package:flutter/material.dart';

const flowerRed = Color(0xFFD85A50);
const ink = Color(0xFF353B34);
const muted = Color(0xFF8B8E80);
const cream = Color(0xFFF8F7F2);
const line = Color(0xFFEAEAE1);
const leafGreen = Color(0xFF64866A);

class FlowerMark extends StatelessWidget {
  const FlowerMark({
    super.key,
    this.size = 36,
    this.color = flowerRed,
    this.face = false,
  });
  final double size;
  final Color color;
  final bool face;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: FlowerPainter(color: color, face: face),
    ),
  );
}

class FlowerPainter extends CustomPainter {
  const FlowerPainter({this.color = flowerRed, this.face = false});
  final Color color;
  final bool face;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - math.pi / 2;
      canvas.drawCircle(
        Offset(math.cos(angle) * r * .48, math.sin(angle) * r * .48),
        r * .43,
        paint,
      );
    }
    canvas.drawCircle(
      Offset.zero,
      r * .36,
      Paint()..color = const Color(0xFFFFDE8A),
    );
    if (face) {
      final eye = Paint()..color = const Color(0xFF754835);
      canvas.drawCircle(Offset(-r * .12, -r * .03), r * .026, eye);
      canvas.drawCircle(Offset(r * .12, -r * .03), r * .026, eye);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(0, r * .035),
          width: r * .19,
          height: r * .15,
        ),
        0,
        math.pi,
        false,
        eye
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .023
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlowerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.face != face;
}

const avatarNames = ['小熊', '小兔', '小猫', '小狐狸', '熊猫', '小鸡'];
const avatarColors = [
  Color(0xFFF4E1C8),
  Color(0xFFF6E2E5),
  Color(0xFFDEE8DC),
  Color(0xFFFFE3C9),
  Color(0xFFE2E6EF),
  Color(0xFFF9ECC2),
];

class AnimalAvatar extends StatelessWidget {
  const AnimalAvatar({super.key, required this.index, this.size = 44});
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _AnimalPainter(index)),
  );
}

class _AnimalPainter extends CustomPainter {
  _AnimalPainter(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawCircle(
      const Offset(50, 50),
      49,
      Paint()..color = avatarColors[index],
    );
    final fur = [
      const Color(0xFFB98859),
      const Color(0xFFFFFAF6),
      const Color(0xFF909F77),
      const Color(0xFFE49A60),
      const Color(0xFFFFFBF3),
      const Color(0xFFF4CF5D),
    ][index];
    final paint = Paint()..color = fur;
    if (index == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(30, 12, 15, 39),
          const Radius.circular(9),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(55, 12, 15, 39),
          const Radius.circular(9),
        ),
        paint,
      );
      final pink = Paint()..color = const Color(0xFFECC8C6);
      canvas.drawOval(const Rect.fromLTWH(35, 18, 5, 23), pink);
      canvas.drawOval(const Rect.fromLTWH(60, 18, 5, 23), pink);
    } else if (index == 2 || index == 3) {
      canvas.drawPath(
        Path()
          ..moveTo(23, 53)
          ..lineTo(24, 24)
          ..lineTo(44, 39)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(57, 38)
          ..lineTo(78, 24)
          ..lineTo(77, 53)
          ..close(),
        paint,
      );
    } else if (index != 5) {
      final ears = Paint()..color = index == 4 ? const Color(0xFF5E635B) : fur;
      canvas.drawCircle(const Offset(28, 36), 12, ears);
      canvas.drawCircle(const Offset(72, 36), 12, ears);
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(42, 37)
          ..quadraticBezierTo(30, 16, 49, 28)
          ..quadraticBezierTo(51, 13, 57, 30)
          ..lineTo(65, 35),
        paint,
      );
    }
    canvas.drawOval(const Rect.fromLTWH(22, 32, 56, 48), paint);
    if (index == 3 || index == 0) {
      canvas.drawOval(
        const Rect.fromLTWH(32, 53, 36, 24),
        Paint()..color = const Color(0xFFFCEEDB),
      );
    }
    if (index == 4) {
      final dark = Paint()..color = const Color(0xFF5E635B);
      canvas.drawOval(const Rect.fromLTWH(31, 44, 15, 17), dark);
      canvas.drawOval(const Rect.fromLTWH(54, 44, 15, 17), dark);
    }
    final eye = Paint()..color = const Color(0xFF4C443B);
    canvas.drawCircle(const Offset(39, 52), 2.6, eye);
    canvas.drawCircle(const Offset(61, 52), 2.6, eye);
    if (index == 5) {
      canvas.drawPath(
        Path()
          ..moveTo(44, 59)
          ..lineTo(56, 59)
          ..lineTo(50, 66)
          ..close(),
        Paint()..color = const Color(0xFFD88D40),
      );
    } else {
      canvas.drawOval(const Rect.fromLTWH(47, 58, 6, 4), eye);
      canvas.drawArc(
        const Rect.fromLTWH(44, 59, 12, 9),
        0,
        math.pi,
        false,
        Paint()
          ..color = const Color(0xFF6E5346)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
    final blush = Paint()
      ..color = const Color(0xFFE9A39A).withValues(alpha: .6);
    canvas.drawOval(const Rect.fromLTWH(28, 58, 9, 5), blush);
    canvas.drawOval(const Rect.fromLTWH(63, 58, 9, 5), blush);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnimalPainter oldDelegate) => oldDelegate.index != index;
}

class GardenIllustration extends StatelessWidget {
  const GardenIllustration({super.key});
  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _GardenPainter());
}

class _GardenPainter extends CustomPainter {
  const _GardenPainter();

  void _leaf(
    Canvas canvas,
    Offset center,
    double angle,
    double scale,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-36, -35, -4, -55)
        ..quadraticBezierTo(23, -24, 0, 0)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawLine(
      const Offset(0, -3),
      const Offset(-3, -42),
      Paint()
        ..color = const Color(0xFFE9EBDD).withValues(alpha: .4)
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  void _flower(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
    double angle,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-size / 2, -size / 2);
    FlowerPainter(color: color, face: true).paint(canvas, Size.square(size));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.min(size.width / 380, size.height / 250);
    canvas.translate(
      (size.width - 380 * scale) / 2,
      (size.height - 250 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawOval(
      const Rect.fromLTWH(20, 14, 330, 224),
      Paint()..color = const Color(0xFFEEEEDC),
    );
    canvas.drawOval(
      const Rect.fromLTWH(48, 223, 275, 16),
      Paint()..color = const Color(0xFFD7DBC5).withValues(alpha: .65),
    );
    final stem = Paint()
      ..color = const Color(0xFF688567)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(102, 232)
        ..quadraticBezierTo(93, 150, 90, 115),
      stem,
    );
    canvas.drawPath(
      Path()
        ..moveTo(190, 232)
        ..quadraticBezierTo(177, 130, 188, 62),
      stem,
    );
    canvas.drawPath(
      Path()
        ..moveTo(260, 232)
        ..quadraticBezierTo(267, 170, 273, 132),
      stem,
    );
    _leaf(canvas, const Offset(99, 192), -.65, .8, const Color(0xFF7E9C75));
    _leaf(canvas, const Offset(102, 208), .8, .8, const Color(0xFF92AA82));
    _leaf(canvas, const Offset(184, 160), -.8, 1.0, const Color(0xFF7E9C75));
    _leaf(canvas, const Offset(184, 199), .85, 1.15, const Color(0xFF7E9C75));
    _leaf(canvas, const Offset(265, 196), -.7, .8, const Color(0xFF92AA82));
    _leaf(canvas, const Offset(265, 214), .75, .65, const Color(0xFF7E9C75));
    _flower(canvas, const Offset(88, 101), 82, const Color(0xFFE89688), -.25);
    _flower(canvas, const Offset(191, 68), 103, flowerRed, .12);
    _flower(canvas, const Offset(273, 133), 76, const Color(0xFFEAC371), .3);
    final dots = Paint()..color = const Color(0xFFC3C6A9);
    for (final point in [
      const Offset(37, 126),
      const Offset(137, 27),
      const Offset(301, 62),
      const Offset(337, 164),
      const Offset(143, 218),
    ]) {
      canvas.drawCircle(point, 2.5, dots);
    }
    canvas.save();
    canvas.translate(302, 40);
    canvas.rotate(.25);
    canvas.drawOval(
      const Rect.fromLTWH(-4, -13, 11, 15),
      Paint()..color = const Color(0xFFFCFBF2),
    );
    canvas.drawOval(
      const Rect.fromLTWH(3, -10, 11, 13),
      Paint()..color = const Color(0xFFFCFBF2),
    );
    canvas.drawOval(
      const Rect.fromLTWH(-9, -2, 24, 14),
      Paint()..color = const Color(0xFFECC96E),
    );
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, 9),
      Paint()
        ..color = const Color(0xFF8A7955)
        ..strokeWidth = 3,
    );
    canvas.drawCircle(const Offset(11, 3), 1.4, Paint()..color = ink);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GardenPainter oldDelegate) => false;
}

class Celebration extends StatefulWidget {
  const Celebration({
    super.key,
    required this.name,
    required this.amount,
    required this.onDone,
  });
  final String name;
  final int amount;
  final VoidCallback onDone;
  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2400),
        )
        ..forward()
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onDone();
        });
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600 || constraints.maxHeight < 400;
      return IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final opacity = t < .12
                ? t / .12
                : t > .82
                ? (1 - t) / .18
                : 1.0;
            return Opacity(
              opacity: opacity.clamp(0, 1),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: cream.withValues(alpha: .89)),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _ConfettiPainter(t)),
                  ),
                  Center(
                    child: Transform.scale(
                      scale:
                          .75 +
                          .25 *
                              Curves.elasticOut.transform((t / .3).clamp(0, 1)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: math.min(420.0, constraints.maxWidth - 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FlowerMark(
                                  size: compact ? 110 : 142,
                                  face: true,
                                ),
                                SizedBox(height: compact ? 18 : 28),
                                Text(
                                  '太棒啦，${widget.name}！',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: compact ? 23 : 28,
                                    fontWeight: FontWeight.w700,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '+${widget.amount} 朵小红花',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w600,
                                    color: flowerRed,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  '每一份努力，都在闪闪发光',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: muted, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    final center = Offset(size.width / 2, size.height / 2 - 50);
    const colors = [
      flowerRed,
      Color(0xFFEBC66A),
      Color(0xFF94AE8B),
      Color(0xFFECA79C),
    ];
    for (var i = 0; i < 64; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final distance =
          (90 + random.nextDouble() * 420) * Curves.easeOut.transform(t);
      final p =
          center +
          Offset(
            math.cos(angle) * distance,
            math.sin(angle) * distance + t * t * 210,
          );
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + t * 4);
      final color = colors[i % colors.length];
      if (i % 5 == 0) {
        FlowerPainter(color: color).paint(canvas, const Size.square(18));
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: 5 + random.nextDouble() * 3,
              height: 12,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = color,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
