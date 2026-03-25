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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 20,
                    bottom: 12,
                    left: 20,
                    right: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag, color: Colors.red[400], size: 28),
                          const SizedBox(width: 8),
                          const Text(
                            'Signaler ce service',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Pourquoi signalez-vous "${widget.serviceName}" ?',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ...ReportReason.reasons.map((reason) => _buildReasonOption(reason)).toList(),
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.isLoading
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                          },
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonOption(ReportReason reason) {
    return InkWell(
      onTap: widget.isLoading
          ? null
          : () {
              setState(() {
                _selectedReason = reason;
                _showDetailsField = reason.requiresDetails ?? false;
                if (!_showDetailsField) {
                  _detailsController.clear();
                }
              });
              HapticFeedback.lightImpact();
            },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedReason == reason
                      ? Colors.red
                      : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: _selectedReason == reason
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                reason.label,
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedReason == reason
                      ? Colors.red[900]
                      : Colors.grey[800],
                  fontWeight: _selectedReason == reason
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}