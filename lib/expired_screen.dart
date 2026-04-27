import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_new_screen.dart';
import 'second_eye_screen.dart';

class ExpiredScreen extends StatefulWidget {
  const ExpiredScreen({super.key});

  @override
  State<ExpiredScreen> createState() => _ExpiredScreenState();
}

class _ExpiredScreenState extends State<ExpiredScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _expiredMeds = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  bool _isLoading = true;
  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadExpiredData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Parses duration string into an end date ───────────────────────
  DateTime? _calculateEndDate(DateTime startDate, String duration) {
    final lower = duration.toLowerCase().trim();
    final number = int.tryParse(lower.replaceAll(RegExp(r'[^0-9]'), ''));
    if (number == null) return null;

    if (lower.contains('day')) {
      return startDate.add(Duration(days: number));
    } else if (lower.contains('week')) {
      return startDate.add(Duration(days: number * 7));
    } else if (lower.contains('month')) {
      return DateTime(startDate.year, startDate.month + number, startDate.day);
    }
    return null;
  }

  Future<void> _loadExpiredData() async {
    final uid = _auth.currentUser!.uid;
    final now = Timestamp.now();
    final today = DateTime.now();

    // Fetch ALL medications for this patient
    final allMedsSnapshot = await _firestore
        .collection('Medications')
        .where('patient_id', isEqualTo: uid)
        .get();

    List<Map<String, dynamic>> meds = [];

    for (var doc in allMedsSnapshot.docs) {
      final data = doc.data();
      data['id'] = doc.id;

      final isActive = data['is_active'] ?? true;
      final startDate = data['start_date'] as Timestamp?;
      final duration = data['duration'] as String?;

      bool isExpired = !isActive; // already manually marked inactive

      // Check if start_date + duration has passed today
      if (!isExpired && startDate != null && duration != null && duration.isNotEmpty) {
        final endDate = _calculateEndDate(startDate.toDate(), duration);
        if (endDate != null && endDate.isBefore(today)) {
          isExpired = true;

          // Auto-update Firestore so it stays expired
          await _firestore.collection('Medications').doc(doc.id).update({
            'is_active': false,
          });
        }
      }

      if (isExpired) {
        // Look up drug name
        final drugId = data['drug_id'];
        if (drugId != null) {
          final drugDoc = await _firestore.collection('Drugs').doc(drugId).get();
          if (drugDoc.exists) {
            data['name'] = drugDoc.data()?['drug_name'] ?? 'Unknown';
          }
        }
        meds.add(data);
      }
    }

    // Fetch past appointments
    final apptSnapshot = await _firestore
        .collection('Appointments')
        .where('patient_id', isEqualTo: uid)
        .get();

    final past = apptSnapshot.docs
        .where((doc) {
          final date = doc.data()['appointment_date'] as Timestamp?;
          return date != null && date.compareTo(now) < 0;
        })
        .map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        })
        .toList()
      ..sort((a, b) {
        final aDate = a['appointment_date'] as Timestamp;
        final bDate = b['appointment_date'] as Timestamp;
        return bDate.compareTo(aDate);
      });

    setState(() {
      _expiredMeds = meds;
      _pastAppointments = past;
      _isLoading = false;
    });
  }

  String _monthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }

  String _formatDate(Timestamp ts) {
    final date = ts.toDate();
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${_monthName(date.month)} ${date.day}, ${date.year} • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[600],
        title: const Text('History', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.blue[200],
          tabs: const [
            Tab(text: 'Medications'),
            Tab(text: 'Appointments'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildExpiredMeds(),
                _buildPastAppointments(),
              ],
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.check_circle, 'Active', 0),
          _buildNavItem(Icons.cancel, 'Expired', 1),
          _buildAddButton(),
          _buildNavItem(Icons.person, 'Profile', 3),
          _buildNavItem(Icons.remove_red_eye, 'Second Eye', 4),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pop(context);
        } else if (index == 4) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SecondEyeScreen()),
          );
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24,
              color: isSelected ? Colors.blue[600] : Colors.grey[400]),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.blue[600] : Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddNewScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[600],
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildExpiredMeds() {
    if (_expiredMeds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medication, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No expired medications',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expiredMeds.length,
      itemBuilder: (context, index) {
        final med = _expiredMeds[index];
        final adherence = (med['adherence_rate'] ?? 0) as int;
        final color = adherence >= 60 ? Colors.green : Colors.orange;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.medication, color: Colors.grey[400], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${med['name'] ?? 'Unknown'} ${med['dosage'] ?? ''}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Completed',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(med['frequency'] ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              if (med['duration'] != null) ...[
                const SizedBox(height: 4),
                Text('Duration: ${med['duration']}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Final Adherence',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('$adherence%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: adherence / 100,
                  backgroundColor: Colors.grey[200],
                  color: color,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPastAppointments() {
    if (_pastAppointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No past appointments',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pastAppointments.length,
      itemBuilder: (context, index) {
        final appt = _pastAppointments[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.calendar_today, color: Colors.grey[400], size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt['appointment_type'] ?? 'Appointment',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('📅 ${_formatDate(appt['appointment_date'])}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    Text('📍 ${appt['location'] ?? 'Location not set'}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Done',
                    style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
}