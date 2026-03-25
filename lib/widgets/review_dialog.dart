import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'star_rating.dart';

class ReviewDialog extends StatefulWidget {
  final String serviceName;
  final Function(int, String?) onSubmit;
  final bool isLoading;

  const ReviewDialog({
    Key? key,
    required this.serviceName,
    required this.onSubmit,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  int _selectedRating = 0;
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(Icons.star_rate, color: Colors.amber, size: 28),
          const SizedBox(width: 8),
          const Text(
            'Noter le service',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comment avez-vous apprécié "${widget.serviceName}" ?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Center(
              child: StarRating(
                rating: _selectedRating,
                maxRating: 5,
                size: 40,
                onRatingChanged: (rating) {
                  setState(() {
                    _selectedRating = rating;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Votre avis (optionnel)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Partagez votre expérience...',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.isLoading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _selectedRating == 0 || widget.isLoading
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  widget.onSubmit(
                    _selectedRating,
                    _commentController.text.trim().isEmpty
                        ? null
                        : _commentController.text.trim(),
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Envoyer',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}