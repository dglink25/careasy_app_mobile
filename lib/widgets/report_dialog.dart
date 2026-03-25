// lib/widgets/report_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/report_reason.dart';

class ReportDialog extends StatefulWidget {
  final String serviceName;
  final Function(String, String?) onSubmit;
  final bool isLoading;

  const ReportDialog({
    Key? key,
    required this.serviceName,
    required this.onSubmit,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  ReportReason? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();
  bool _showDetailsField = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(Icons.flag, color: Colors.red[400], size: 28),
          const SizedBox(width: 8),
          const Text(
            'Signaler ce service',
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
              'Pourquoi signalez-vous "${widget.serviceName}" ?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...ReportReason.reasons.map((reason) => RadioListTile<ReportReason>(
              title: Text(reason.label),
              value: reason,
              groupValue: _selectedReason,
              activeColor: Colors.red,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: widget.isLoading
                  ? null
                  : (value) {
                      setState(() {
                        _selectedReason = value;
                        _showDetailsField = value?.requiresDetails ?? false;
                        if (!_showDetailsField) {
                          _detailsController.clear();
                        }
                      });
                      HapticFeedback.lightImpact();
                    },
            )).toList(),
            if (_showDetailsField) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _detailsController,
                maxLines: 3,
                maxLength: 300,
                enabled: !widget.isLoading,
                decoration: InputDecoration(
                  hintText: 'Veuillez préciser votre signalement...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
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
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  counterText: '',
                ),
              ),
            ],
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
          onPressed: (_selectedReason == null || widget.isLoading)
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  
                  String reportMessage = _selectedReason!.label;
                  if (_showDetailsField && _detailsController.text.trim().isNotEmpty) {
                    reportMessage += ': ${_detailsController.text.trim()}';
                  }
                  
                  widget.onSubmit(
                    _selectedReason!.id,
                    _showDetailsField ? _detailsController.text.trim() : null,
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
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
                  'Signaler',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}