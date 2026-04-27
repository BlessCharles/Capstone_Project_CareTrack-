import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  List<TextEditingController> _scheduleControllers = [TextEditingController()];
  String _selectedFrequency = 'Select frequency';
  DateTime? _selectedStartDate;
  bool _isSaving = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    for (var c in _scheduleControllers) c.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedStartDate = picked);
  }

  void _addScheduleSlot() {
    setState(() => _scheduleControllers.add(TextEditingController()));
  }

  void _removeScheduleSlot(int index) {
    setState(() {
      _scheduleControllers[index].dispose();
      _scheduleControllers.removeAt(index);
    });
  }

  String _formatDate(DateTime date) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  Future<String> _getOrCreateDrugId(String drugName) async {
    final existing = await _firestore
        .collection('Drugs')
        .where('drug_name', isEqualTo: drugName)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final newDrug = await _firestore.collection('Drugs').add({
      'drug_name': drugName,
    });
    return newDrug.id;
  }

  Future<void> _saveMedication() async {
    if (_nameController.text.isEmpty ||
        _dosageController.text.isEmpty ||
        _selectedFrequency == 'Select frequency' ||
        _selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = _auth.currentUser!.uid;

      // Step 1: Get or create drug in Drugs collection
      final drugId = await _getOrCreateDrugId(_nameController.text.trim());

      // Step 2: Build schedule list
      final schedule = _scheduleControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // Step 3: Save medication to Firestore
      final docRef = await _firestore.collection('Medications').add({
        'patient_id': uid,
        'drug_id': drugId,
        'dosage': _dosageController.text.trim(),
        'frequency': _selectedFrequency,
        'instructions': _instructionsController.text.trim(),
        'duration': _durationController.text.trim(),
        'schedule': schedule,
        'start_date': Timestamp.fromDate(_selectedStartDate!),
        'is_active': true,
        'adherence_rate': 0,
        'created_at': Timestamp.now(),
      });

      // Step 4: Schedule local notifications for this medication
      // Build the same map the notification service expects
      final medData = {
        'id': docRef.id,
        'patient_id': uid,
        'name': _nameController.text.trim(),
        'dosage': _dosageController.text.trim(),
        'schedule': schedule,
        'start_date': Timestamp.fromDate(_selectedStartDate!),
        'duration': _durationController.text.trim(),
      };
      await NotificationService().scheduleAllReminders(medData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medication added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving medication: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[600],
        title: const Text('Add Medication', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Medication Name
            Text('Medication Name',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_nameController, 'e.g., Ibuprofen'),

            const SizedBox(height: 20),

            // Dosage
            Text('Dosage',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_dosageController, 'e.g., 400mg'),

            const SizedBox(height: 20),

            // Frequency
            Text('Frequency',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButton<String>(
                value: _selectedFrequency,
                isExpanded: true,
                underline: const SizedBox(),
                items: [
                  'Select frequency',
                  'Once daily',
                  'Twice daily',
                  '3 times daily',
                  '4 times daily',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() => _selectedFrequency = newValue!);
                },
              ),
            ),

            const SizedBox(height: 20),

            // Start Date
            Text('Start Date',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
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
                      _selectedStartDate == null
                          ? 'Select start date'
                          : _formatDate(_selectedStartDate!),
                      style: TextStyle(
                          fontSize: 16,
                          color: _selectedStartDate == null
                              ? Colors.grey[400] : Colors.black87),
                    ),
                    Icon(Icons.calendar_today, color: Colors.grey[600], size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Duration
            Text('Duration',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_durationController, 'e.g., 7 days, 2 weeks, 1 month'),

            const SizedBox(height: 20),

            // Instructions
            Text('Instructions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _buildTextField(_instructionsController, 'e.g., Take before food'),

            const SizedBox(height: 20),

            // Schedule
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Schedule',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
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
                        child: _buildTextField(controller, 'e.g., 8:00am')),
                    if (_scheduleControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
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
                onPressed: _isSaving ? null : _saveMedication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Medication',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
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