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


  /// Affiche les étoiles + le nombre d'avis
  Widget _buildStarRating(Map<String, dynamic> service) {
    final totalReviews = (service['total_reviews'] ?? 0) as int;
    final averageRating = service['average_rating'];

    if (totalReviews == 0) return const SizedBox.shrink();

    final double avg = averageRating != null
        ? double.tryParse(averageRating.toString()) ?? 0.0
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Étoiles
        ...List.generate(5, (i) {
          if (i < avg.floor()) {
            return const Icon(Icons.star, size: 13, color: Colors.amber);
          } else if (i < avg && (avg - avg.floor()) >= 0.5) {
            return const Icon(Icons.star_half, size: 13, color: Colors.amber);
          } else {
            return Icon(Icons.star_border, size: 13, color: Colors.grey[400]);
          }
        }),
        const SizedBox(width: 4),
        Text(
          '$avg ($totalReviews)',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }


}