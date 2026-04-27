import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_new_screen.dart';
import 'edit_appointment_screen.dart';
import 'medication_detail_screen.dart';
import 'second_eye_screen.dart';
import 'expired_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _fullName = '';
  String _dischargeDate = '';
  bool _isLoading = true;

  Map<String, dynamic>? _nextAppointment;
  List<Map<String, dynamic>> _medications = [];
  List<Map<String, dynamic>> _instructions = []; // ← new

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final String uid = _auth.currentUser!.uid;

      // 1. Fetch user info
      final userDoc = await _firestore.collection('Users').doc(uid).get();
      if (userDoc.exists) {
        _fullName = userDoc.data()?['full_name'] ?? 'Unknown';
      }

      // 2. Fetch patient doc
      final patientQuery = await _firestore
          .collection('Patients')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get();

      if (patientQuery.docs.isNotEmpty) {
        final patientData = patientQuery.docs.first.data();

        final Timestamp? discharge = patientData['discharge_date'];
        if (discharge != null) {
          final date = discharge.toDate();
          _dischargeDate = '${_monthName(date.month)} ${date.day}, ${date.year}';
        }

        // 3. Fetch active medications
        _firestore
            .collection('Medications')
            .where('patient_id', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) async {
          List<Map<String, dynamic>> meds = [];

          for (var doc in snapshot.docs) {
            final data = doc.data();
            if (data['is_active'] != true) continue;
            data['id'] = doc.id;
            
            //fetch drug name
            final drugId = data['drug_id'];
            if (drugId != null) {
              final drugDoc =
                await _firestore.collection('Drugs').doc(drugId).get();
              if (drugDoc.exists) {
                data['name'] = drugDoc.data()?['drug_name'] ?? 'Unknown';
              }
            }

            meds.add(data);
          }

          setState(() {
            _medications = meds;
          });
        });

        // Fetch next appointment
        final appointmentsSnapshot = await _firestore
            .collection('Appointments')
            .where('patient_id', isEqualTo: uid)
            .get();

        final now = Timestamp.now();
        final upcoming = appointmentsSnapshot.docs
            .where((doc) {
              final date = doc.data()['appointment_date'] as Timestamp?;
              return date != null && date.compareTo(now) >= 0;
            })
            .toList()
          ..sort((a, b) {
            final aDate = a.data()['appointment_date'] as Timestamp;
            final bDate = b.data()['appointment_date'] as Timestamp;
            return aDate.compareTo(bDate);
          });

        if (upcoming.isNotEmpty) {
          _nextAppointment = upcoming.first.data();
          _nextAppointment!['id'] = upcoming.first.id;
        } else {
          _nextAppointment = null;
        }

        // 5. Fetch active instructions ← new
        final instructionsSnapshot = await _firestore
            .collection('Instructions')
            .where('patient_id', isEqualTo: uid)
            .get();

        _instructions = instructionsSnapshot.docs
            .where((doc) => doc.data()['is_active'] == true)
            .map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            })
            .toList();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }

  String _daysRemaining(Timestamp appointmentDate) {
    final now = DateTime.now();
    final apptDate = appointmentDate.toDate();
    final diff = apptDate.difference(now).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return '1 day remaining';
    return '$diff days remaining';
  }

  String _formatAppointmentDate(Timestamp ts) {
    final date = ts.toDate();
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '📅 ${_monthName(date.month)} ${date.day}, ${date.year} • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[600],
        title: const Text('Recovery Dashboard',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Patient Info ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        const Text('👤', style: TextStyle(fontSize: 40)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fullName.isEmpty ? 'Loading...' : _fullName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _dischargeDate.isEmpty
                                  ? 'Discharge date not set'
                                  : 'Discharged: $_dischargeDate',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Appointment ───────────────────────────────────────
                  Container(
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
                                Icon(Icons.calendar_today,
                                    color: Colors.blue[600], size: 20),
                                const SizedBox(width: 8),
                                const Text('Next Appointment',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            if (_nextAppointment != null)
                              IconButton(
                                icon: Icon(Icons.edit,
                                    color: Colors.blue[600], size: 18),
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditAppointmentScreen(
                                        appointmentId: _nextAppointment!['id'],
                                        appointmentData: _nextAppointment!,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    setState(() => _isLoading = true);
                                    _loadDashboardData();
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _nextAppointment == null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No upcoming appointments',
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                      left: BorderSide(
                                          color: Colors.blue[600]!, width: 4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _nextAppointment!['appointment_type'] ??
                                          'Appointment',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatAppointmentDate(
                                          _nextAppointment!['appointment_date']),
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700]),
                                    ),
                                    Text(
                                      '📍 ${_nextAppointment!['location'] ?? 'Location not set'}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Icon(Icons.access_time,
                                            color: Colors.orange[700],
                                            size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          _daysRemaining(_nextAppointment![
                                              'appointment_date']),
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange[700]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Medications ───────────────────────────────────────
                  Container(
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
                                Icon(Icons.medication,
                                    color: Colors.blue[600], size: 20),
                                const SizedBox(width: 8),
                                const Text('Medications',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_medications.length} active',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _medications.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No medications added yet',
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ),
                              )
                            : Column(
                                children: _medications.asMap().entries.map((entry) {
                                  final med = entry.value;
                                  final adherence =
                                      (med['adherence_rate'] ?? 0) as int;
                                  final color = adherence >= 60
                                      ? Colors.green
                                      : Colors.orange;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                        top: entry.key == 0 ? 0 : 12),
                                    child: _buildMedication(
                                      '${med['name'] ?? ''} ${med['dosage'] ?? ''}',
                                      med['frequency'] ?? '',
                                      adherence,
                                      color,
                                      med,
                                    ),
                                  );
                                }).toList(),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Instructions/Restrictions ─────────────────────────
                  Container(
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
                                Icon(Icons.description,
                                    color: Colors.orange[600], size: 20),
                                const SizedBox(width: 8),
                                const Text('Restrictions',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_instructions.length} active',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _instructions.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No active restrictions',
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ),
                              )
                            : Column(
                                children: _instructions.asMap().entries.map((entry) {
                                  final instruction = entry.value;
                                  final isActivity =
                                      instruction['instruction_type'] == 'Activity';
                                  final color = isActivity
                                      ? Colors.green[600]!
                                      : Colors.orange[600]!;
                                  final bgColor = isActivity
                                      ? Colors.green[50]!
                                      : Colors.orange[50]!;

                                  return Padding(
                                    padding: EdgeInsets.only(
                                        top: entry.key == 0 ? 0 : 10),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border(
                                            left: BorderSide(
                                                color: color, width: 4)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            isActivity
                                                ? Icons.directions_run
                                                : Icons.restaurant,
                                            color: color,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      instruction['title'] ?? '',
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: color
                                                            .withOpacity(0.15),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                6),
                                                      ),
                                                      child: Text(
                                                        instruction[
                                                                'instruction_type'] ??
                                                            '',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: color,
                                                            fontWeight:
                                                                FontWeight.w600),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  instruction['description'] ?? '',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[700]),
                                                ),
                                                if (instruction['duration'] !=
                                                        null &&
                                                    instruction['duration']
                                                        .toString()
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '⏱ ${instruction['duration']}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey[600]),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMedication(String name, String frequency, int progress,
      Color color, Map<String, dynamic> medData) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MedicationDetailScreen(
              medicationId: medData['id'] ?? '',
              medicationName: medData['name'] ?? '',
              dosage: medData['dosage'] ?? '',
              frequency: frequency,
              adherenceRate: progress,
              schedule: List<String>.from(medData['schedule'] ?? []),
              instructions: medData['instructions'] ?? '',
              duration: medData['duration'] ?? '',
              startDate: medData['start_date'] != null
                  ? (medData['start_date'] as Timestamp).toDate()
                  : null,
            ),
          ),
        );
        if (result == true) {
          setState(() => _isLoading = true);
          _loadDashboardData();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(frequency,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Text('$progress%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey[200],
                color: color,
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
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
        setState(() => _selectedIndex = index);
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ExpiredScreen()),
          );
        }
        if (index == 3) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          );
        }
        if (index == 4) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SecondEyeScreen()),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 24,
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
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddNewScreen()),
        );
        if (result == true) {
          setState(() => _isLoading = true);
          _loadDashboardData();
        }
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
}