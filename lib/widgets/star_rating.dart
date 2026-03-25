import 'package:flutter/material.dart';

class StarRating extends StatefulWidget {
  final int rating;
  final int maxRating;
  final ValueChanged<int>? onRatingChanged;
  final double size;
  final bool enabled;
  
  const StarRating({
    Key? key,
    required this.rating,
    this.maxRating = 5,
    this.onRatingChanged,
    this.size = 32.0,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  int _currentRating = 0;
  bool _isHovering = false;
  int _hoverRating = 0;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.rating;
  }

  @override
  void didUpdateWidget(StarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rating != oldWidget.rating) {
      setState(() {
        _currentRating = widget.rating;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() {
        _isHovering = false;
        _hoverRating = 0;
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.maxRating, (index) {
          final starNumber = index + 1;
          final isSelected = (_isHovering ? _hoverRating : _currentRating) >= starNumber;
          
          return GestureDetector(
            onTap: widget.enabled && widget.onRatingChanged != null
                ? () {
                    setState(() {
                      _currentRating = starNumber;
                    });
                    widget.onRatingChanged!(starNumber);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Icon(
                isSelected ? Icons.star : Icons.star_border,
                size: widget.size,
                color: isSelected ? Colors.amber : Colors.grey[400],
              ),
            ),
          );
        }),
      ),
    );
  }
}