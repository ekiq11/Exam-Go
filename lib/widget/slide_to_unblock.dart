import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SlideToUnblock extends StatefulWidget {
  final VoidCallback onAction;
  final String text;
  final Color backgroundColor;
  final Color sliderColor;

  const SlideToUnblock({
    super.key,
    required this.onAction,
    this.text = 'Geser untuk Buka',
    this.backgroundColor = const Color(0xFFE8F5E9),
    this.sliderColor = const Color(0xFF2E7D32),
  });

  @override
  State<SlideToUnblock> createState() => _SlideToUnblockState();
}

class _SlideToUnblockState extends State<SlideToUnblock> with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _isCompleted = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        setState(() {
          if (!_isCompleted) {
            _dragPosition = _animationController.value * _dragPosition;
          }
        });
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, double maxWidth) {
    if (_isCompleted) return;
    setState(() {
      _dragPosition += details.delta.dx;
      // Batas minimum
      if (_dragPosition < 0) _dragPosition = 0;
      // Batas maksimum (slider width is approx 60)
      if (_dragPosition > maxWidth - 60) {
        _dragPosition = maxWidth - 60;
      }
    });
  }

  void _onPanEnd(DragEndDetails details, double maxWidth) {
    if (_isCompleted) return;
    // Jika digeser lebih dari 70%
    if (_dragPosition > (maxWidth - 60) * 0.7) {
      setState(() {
        _dragPosition = maxWidth - 60;
        _isCompleted = true;
      });
      widget.onAction();
    } else {
      // Kembalikan ke posisi semula
      _animationController.forward(from: 1.0).then((_) {
        _animationController.value = 0;
        setState(() => _dragPosition = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return Container(
          height: 60,
          width: maxWidth,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: widget.sliderColor.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Shimmer Text Background
              Center(
                child: Text(
                  _isCompleted ? 'Berhasil Membuka Akses!' : widget.text,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _isCompleted ? widget.sliderColor : widget.sliderColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
              // Draggable Thumb
              if (!_isCompleted)
                Positioned(
                  left: _dragPosition,
                  top: 5,
                  bottom: 5,
                  child: GestureDetector(
                    onPanUpdate: (details) => _onPanUpdate(details, maxWidth),
                    onPanEnd: (details) => _onPanEnd(details, maxWidth),
                    child: Container(
                      width: 50,
                      decoration: BoxDecoration(
                        color: widget.sliderColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.sliderColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(2, 0),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
