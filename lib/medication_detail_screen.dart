import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class MedicationDetailScreen extends StatefulWidget {
  final String medicationId;
  final String medicationName;
  final String dosage;
  final String frequency;
  final int adherenceRate;
  final List<String> schedule;
  final String instructions;
  final String duration;
  final DateTime? startDate;

  const MedicationDetailScreen({
    super.key,
    required this.medicationId,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.adherenceRate,
    required this.schedule,
    required this.instructions,
    this.duration = '',
    this.startDate,
  });

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TextEditingController _dosageController;
  late TextEditingController _frequencyController;
  late TextEditingController _instructionsController;
  late TextEditingController _durationController;
  List<TextEditingController> _scheduleControllers = [];
  DateTime? _selectedStartDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _dosageController = TextEditingController(text: widget.dosage);
    _frequencyController = TextEditingController(text: widget.frequency);
    _instructionsController = TextEditingController(text: widget.instructions);
    _durationController = TextEditingController(text: widget.duration);
    _selectedStartDate = widget.startDate;

    _scheduleControllers = widget.schedule
        .map((time) => TextEditingController(text: time))
        .toList();
    if (_scheduleControllers.isEmpty) {
      _scheduleControllers.add(TextEditingController());
    }
    _calculateAndUpdateAdherence();
  }

  @override
  void dispose() {
    _dosageController.dispose();
    _frequencyController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    for (var c in _scheduleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addScheduleSlot() {
    setState(() {
      _scheduleControllers.add(TextEditingController());
    });
  }

  void _removeScheduleSlot(int index) {
    setState(() {
      _scheduleControllers[index].dispose();
      _scheduleControllers.removeAt(index);
    });
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final schedule = _scheduleControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      await _firestore
          .collection('Medications')
          .doc(widget.medicationId)
          .update({
        'dosage': _dosageController.text.trim(),
        'frequency': _frequencyController.text.trim(),
        'instructions': _instructionsController.text.trim(),
        'duration': _durationController.text.trim(),
        'start_date': _selectedStartDate != null
            ? Timestamp.fromDate(_selectedStartDate!)
            : null,
        'schedule': schedule,
      });

      // Reschedule reminders with updated medication data.
      // scheduleAllReminders() cancels the old ones first automatically.
      final medData = {
        'id': widget.medicationId,
        'patient_id': (await _firestore
                .collection('Medications')
                .doc(widget.medicationId)
                .get())
            .data()?['patient_id'] ?? '',
        'name': widget.medicationName,
        'dosage': _dosageController.text.trim(),
        'schedule': schedule,
        'start_date': _selectedStartDate != null
            ? Timestamp.fromDate(_selectedStartDate!)
            : null,
        'duration': _durationController.text.trim(),
      };
      await NotificationService().scheduleAllReminders(medData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medication updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  Future<void> _deleteMedication() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medication'),
        content: const Text('Are you sure you want to delete this medication?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              // Cancel all scheduled reminders for this medication first
              await NotificationService()
                  .cancelMedicationReminders(widget.medicationId);

              await _firestore
                  .collection('Medications')
                  .doc(widget.medicationId)
                  .delete();

              if (mounted) {
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Medication deleted'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateAndUpdateAdherence() async{
    
    try {
      final medDoc =
        await _firestore.collection('Medications').doc(widget.medicationId).get();

      if (!medDoc.exists) return;

      final data = medDoc.data()!;
      final duration = data['duration'] ?? '';
      final schedule = List<String>.from(data['schedule'] ?? []);

      // 👉 Calculate total expected doses
      int totalDays = 0;
      final lower = duration.toLowerCase();

      final number =
        int.tryParse(lower.replaceAll(RegExp(r'[^0-9]'), ''));

      if (number != null) {
        if (lower.contains('day')) totalDays = number;
        if (lower.contains('week')) totalDays = number * 7;
        if (lower.contains('month')) totalDays = number * 30;
      }

      final dosesPerDay = schedule.length;
      final totalExpectedDoses = totalDays * dosesPerDay;

      // 👉 Get actual logs
      final logsSnapshot = await _firestore
        .collection('Medication_Schedule_Log')
        .where('medication_id', isEqualTo: widget.medicationId)
        .get();

      final taken = logsSnapshot.docs
        .where((d) => d['was_taken'] == true)
        .length;

      if (totalExpectedDoses == 0) return;

      final adherenceRate =
        ((taken / totalExpectedDoses) * 100).round();

      await _firestore
        .collection('Medications')
        .doc(widget.medicationId)
        .update({'adherence_rate': adherenceRate});

      debugPrint(
        '[Adherence FIXED] $taken / $totalExpectedDoses = $adherenceRate%');
    } catch (e) {
      debugPrint('Adherence error: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[600],
        title: Text(
          widget.medicationName,
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medication name display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.medication, color: Colors.blue[600], size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.medicationName,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Active Medication',
                        style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Dosage
            Text('Dosage',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_dosageController, 'e.g. 400mg'),

            const SizedBox(height: 20),

            // Frequency
            Text('Frequency',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_frequencyController, 'e.g. 3 times daily'),

            const SizedBox(height: 20),

            // Start Date
            Text('Start Date',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _selectStartDate(context),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedStartDate != null
                          ? _formatDate(_selectedStartDate!)
                          : 'Select start date',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedStartDate != null
                            ? Colors.black87
                            : Colors.grey[400],
                      ),
                    ),
                    Icon(Icons.calendar_today,
                        color: Colors.grey[600], size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Duration
            Text('Duration',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(
                _durationController, 'e.g. 7 days, 2 weeks, 1 month'),

            const SizedBox(height: 20),

            // Instructions
            Text('Instructions',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_instructionsController, 'e.g. Take with food'),

            const SizedBox(height: 20),

            // Schedule
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Schedule',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700])),
                TextButton.icon(
                  onPressed: _addScheduleSlot,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Time'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._scheduleControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                        child: _buildTextField(controller, 'e.g. 8:00 AM')),
                    if (_scheduleControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle,
                            color: Colors.red),
                        onPressed: () => _removeScheduleSlot(index),
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 16),

            // Delete Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _deleteMedication,
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Delete Medication',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[500],
                  side: BorderSide(color: Colors.red[500]!, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue[600]!, width: 2)),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}