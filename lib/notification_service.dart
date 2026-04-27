import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Shared constants ─────────────────────────────────────────────────────────
const String kTakenActionId = 'TAKEN';
const String kLaterActionId = 'LATER';
const String kSkipActionId = 'SKIP';
const String kChannelId = 'medication_reminders';
const String kChannelName = 'Medication Reminders';
const String kChannelDesc = 'Reminds you when it is time to take your medication';

// ════════════════════════════════════════════════════════════════════════════
// BACKGROUND HANDLER — top-level, runs in a separate isolate
// ════════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) async {
  // Must be first line in every isolate that touches Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Re-initialise Firebase for this isolate
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  // Re-initialise timezone for this isolate
  tz.initializeTimeZones();
  final tzInfo = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

  // Re-initialise the plugin so we can schedule "Later" notifications
  // from this isolate.  We need the full channel + actions here.
  final plugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidSettings),
  );

  await _processAction(response, plugin);
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED ACTION PROCESSOR
// Called from both foreground and background contexts.
// ════════════════════════════════════════════════════════════════════════════
Future<void> _processAction(
  NotificationResponse response,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final String? payload = response.payload;
  final String? actionId = response.actionId;
  final int notifId = response.id ?? 0;

  // actionId == null means the user tapped the notification body to open
  // the app — nothing to log here.
  if (payload == null || actionId == null) return;

  // Payload: medicationId|patientId|scheduledTime|scheduledDateISO
  final parts = payload.split('|');
  if (parts.length < 4) return;

  final String medicationId = parts[0];
  final String patientId = parts[1];
  final String scheduledTime = parts[2];
  final DateTime scheduledDate = DateTime.tryParse(parts[3]) ?? DateTime.now();

  final firestore = FirebaseFirestore.instance;

  switch (actionId) {
    case kTakenActionId:
      // ✅ Patient confirmed — log as taken, update adherence
      await _logDose(
        firestore: firestore,
        medicationId: medicationId,
        patientId: patientId,
        scheduledTime: scheduledTime,
        scheduledDate: scheduledDate,
        wasTaken: true,
      );
      break;

    case kSkipActionId:
      // ❌ Patient skipping — log as not taken, update adherence
      await _logDose(
        firestore: firestore,
        medicationId: medicationId,
        patientId: patientId,
        scheduledTime: scheduledTime,
        scheduledDate: scheduledDate,
        wasTaken: false,
      );
      break;

    case kLaterActionId:
      // ⏰ Remind in 15 minutes — do NOT log yet
      await _scheduleLater(
        plugin: plugin,
        originalId: notifId,
        payload: payload,
        scheduledTime: scheduledTime,
      );
      break;
  }
}

// ── Log a dose to Medication_Schedule_Log ────────────────────────────────────
Future<void> _logDose({
  required FirebaseFirestore firestore,
  required String medicationId,
  required String patientId,
  required String scheduledTime,
  required DateTime scheduledDate,
  required bool wasTaken,
}) async {
  try {
    // Strip time component so the date matches what was stored at schedule time.
    // Use UTC midnight to be consistent with how Firestore stores Timestamps
    // created from DateTime(y, m, d) — which defaults to local midnight and
    // gets serialised to UTC.  We match on the ISO date string instead of a
    // Timestamp range to avoid timezone drift issues.
    final DateTime dateOnly = DateTime.utc(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    );
    final Timestamp dateTimestamp = Timestamp.fromDate(dateOnly);

    // Check for an existing log to avoid duplicates
    final existing = await firestore
        .collection('Medication_Schedule_Log')
        .where('medication_id', isEqualTo: medicationId)
        .where('scheduled_time', isEqualTo: scheduledTime)
        .where('scheduled_date', isEqualTo: dateTimestamp)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      // Update if the patient previously chose "Later" and now confirms
      await existing.docs.first.reference.update({
        'was_taken': wasTaken,
        'logged_at': Timestamp.now(),
      });
    } else {
      await firestore.collection('Medication_Schedule_Log').add({
        'medication_id': medicationId,
        'patient_id': patientId,
        'scheduled_time': scheduledTime,
        'scheduled_date': dateTimestamp,
        'was_taken': wasTaken,
        'logged_at': Timestamp.now(),
      });
    }

    // Recalculate adherence rate after every log change
    await _updateAdherenceRate(
      firestore: firestore,
      medicationId: medicationId,
    );
  } catch (e) {
    // Silently absorb — notification callbacks must never crash
    debugPrint('[NotificationService] _logDose error: $e');
  }
}

// ── Recalculate and write adherence rate to Medications doc ──────────────────
Future<void> _updateAdherenceRate({
  required FirebaseFirestore firestore,
  required String medicationId,
}) async {
  try {
    final medDoc =
        await firestore.collection('Medications').doc(medicationId).get();

    if (!medDoc.exists) return;

    final data = medDoc.data()!;
    final duration = data['duration'] ?? '';
    final schedule = List<String>.from(data['schedule'] ?? []);

    // Calculate total expected doses
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

    // Get actual logs
    final logsSnapshot = await firestore
        .collection('Medication_Schedule_Log')
        .where('medication_id', isEqualTo: medicationId)
        .get();

    final taken = logsSnapshot.docs
        .where((d) => d['was_taken'] == true)
        .length;

    if (totalExpectedDoses == 0) return;

    final adherenceRate =
        ((taken / totalExpectedDoses) * 100).round();

    await firestore
        .collection('Medications')
        .doc(medicationId)
        .update({'adherence_rate': adherenceRate});

    debugPrint(
        '[Adherence FIXED] $taken / $totalExpectedDoses = $adherenceRate%');
  } catch (e) {
    debugPrint('Adherence error: $e');
  }
}

// ── Schedule a "Remind me later" notification 15 minutes from now ─────────────
// IMPORTANT: this reuses _buildNotificationDetails() so the re-fired
// notification still has the Taken / Later / Skip action buttons.
Future<void> _scheduleLater({
  required FlutterLocalNotificationsPlugin plugin,
  required int originalId,
  required String payload,
  required String scheduledTime,
}) async {
  try {
    final tz.TZDateTime fifteenLater =
        tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15));

    // Use a different ID range so it never collides with scheduled reminders
    final int laterId = (originalId + 500000) % 0x7FFFFFFF;

    await plugin.zonedSchedule(
      id: laterId,
      title: '💊 Reminder: Take your medication',
      body: '$scheduledTime · Don\'t forget!',
      scheduledDate: fifteenLater,
      // ✅ FIX: include action buttons so the user can still tap Taken / Skip
      notificationDetails: _buildNotificationDetails(),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    debugPrint('[NotificationService] Later reminder scheduled for $fifteenLater');
  } catch (e) {
    debugPrint('[NotificationService] _scheduleLater error: $e');
  }
}

// ── Notification details with Taken / Later / Skip action buttons ─────────────
NotificationDetails _buildNotificationDetails() {
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      kChannelId,
      kChannelName,
      channelDescription: kChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // Keeps notification visible in the shade until the user acts
      autoCancel: false,
      ongoing: false,
      actions: [
        AndroidNotificationAction(
          kTakenActionId,
          '✅ Taken',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          kLaterActionId,
          '⏰ Later (15 min)',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          kSkipActionId,
          '❌ Skip',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// NotificationService — used by the rest of the app
// ════════════════════════════════════════════════════════════════════════════
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;

  // ── One-time initialisation on app start ──────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    // Create the notification channel on Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      kChannelId,
      kChannelName,
      description: kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      // Foreground handler — passes the shared plugin instance so _scheduleLater works
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        await _processAction(response, _plugin);
      },
      // Background handler — top-level function (Flutter requirement)
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    _initialized = true;
    debugPrint('[NotificationService] Initialised ✓');
  }

  // ── Request Android 13+ notification permission + exact alarm permission ───
  Future<void> requestPermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  // ── Parse "8:00am" → {hour: 8, minute: 0} ────────────────────────────────
  Map<String, int>? _parseTime(String timeStr) {
    try {
      final t = timeStr.trim().toLowerCase().replaceAll(' ', '');
      final isPm = t.endsWith('pm');
      final isAm = t.endsWith('am');
      final timePart = t.replaceAll('am', '').replaceAll('pm', '');
      final parts = timePart.split(':');
      if (parts.length != 2) return null;
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      if (isPm && hour != 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
      return {'hour': hour, 'minute': minute};
    } catch (_) {
      return null;
    }
  }

  // ── Parse "7 days" / "2 weeks" / "1 month" → number of days ──────────────
  int? _parseDurationDays(String duration) {
    final lower = duration.toLowerCase().trim();
    final number = int.tryParse(lower.replaceAll(RegExp(r'[^0-9]'), ''));
    if (number == null) return null;
    if (lower.contains('day')) return number;
    if (lower.contains('week')) return number * 7;
    if (lower.contains('month')) return number * 30;
    return null;
  }

  // ── Stable unique notification ID: medication + time slot + day ───────────
  int _buildNotificationId(String medicationId, int timeIndex, int dayOffset) {
    int hash = 0;
    for (int i = 0; i < medicationId.length; i++) {
      hash = (hash * 31 + medicationId.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return ((hash % 100000) * 1000 + timeIndex * 100 + dayOffset) % 0x7FFFFFFF;
  }

  // ── Schedule all daily reminders for one medication ───────────────────────
  Future<void> scheduleAllReminders(Map<String, dynamic> med) async {
    final String medicationId = med['id'] ?? '';
    final String patientId = med['patient_id'] ?? '';
    final String drugName = med['name'] ?? 'Medication';
    final String dosage = med['dosage'] ?? '';
    final List<dynamic> schedule = med['schedule'] ?? [];
    final Timestamp? startTimestamp = med['start_date'];
    final String duration = med['duration'] ?? '';

    if (medicationId.isEmpty || schedule.isEmpty || startTimestamp == null) {
      return;
    }

    final int? durationDays = _parseDurationDays(duration);
    if (durationDays == null) return;

    final DateTime startDate = startTimestamp.toDate();
    final DateTime today = DateTime.now();
    final DateTime endDate = startDate.add(Duration(days: durationDays));

    // Cancel existing reminders for this medication before re-scheduling
    await cancelMedicationReminders(medicationId);

    for (int dayOffset = 0; dayOffset <= durationDays; dayOffset++) {
      final DateTime scheduledDay = startDate.add(Duration(days: dayOffset));

      // Skip days that have already passed
      if (scheduledDay
          .isBefore(DateTime(today.year, today.month, today.day))) {
        continue;
      }
      if (scheduledDay.isAfter(endDate)) break;

      for (int timeIndex = 0; timeIndex < schedule.length; timeIndex++) {
        final String timeStr = schedule[timeIndex].toString();
        final Map<String, int>? parsedTime = _parseTime(timeStr);
        if (parsedTime == null) continue;

        final tz.TZDateTime scheduledDateTime = tz.TZDateTime(
          tz.local,
          scheduledDay.year,
          scheduledDay.month,
          scheduledDay.day,
          parsedTime['hour']!,
          parsedTime['minute']!,
        );

        // Skip times that have already passed today
        if (scheduledDateTime.isBefore(tz.TZDateTime.now(tz.local))) {
          continue;
        }

        final int notifId =
            _buildNotificationId(medicationId, timeIndex, dayOffset);

        // Payload carries everything needed for logging / re-scheduling.
        // scheduledDate is stored as UTC ISO string so parsing is unambiguous.
        final String payload =
            '$medicationId|$patientId|$timeStr|${DateTime.utc(scheduledDay.year, scheduledDay.month, scheduledDay.day).toIso8601String()}';

        await _plugin.zonedSchedule(
          id: notifId,
          title: '💊 Time to take $drugName',
          body: '$dosage · $timeStr',
          scheduledDate: scheduledDateTime,
          notificationDetails: _buildNotificationDetails(),
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }

    debugPrint(
        '[NotificationService] Reminders scheduled for $drugName ($medicationId)');
  }

  // ── Cancel all reminders for one medication ───────────────────────────────
  Future<void> cancelMedicationReminders(String medicationId) async {
    int hash = 0;
    for (int i = 0; i < medicationId.length; i++) {
      hash = (hash * 31 + medicationId.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final int base = (hash % 100000) * 1000;

    // Cancel main scheduled IDs (up to 4 time slots × 366 days)
    for (int t = 0; t < 4; t++) {
      for (int d = 0; d <= 365; d++) {
        await _plugin.cancel(id: (base + t * 100 + d) % 0x7FFFFFFF);
      }
    }
    // Cancel any "Later" reminder IDs (offset by 500 000)
    for (int t = 0; t < 4; t++) {
      for (int d = 0; d <= 365; d++) {
        await _plugin.cancel(
            id: ((base + t * 100 + d) % 0x7FFFFFFF + 500000) % 0x7FFFFFFF);
      }
    }
  }

  // ── Re-schedule all active medications on every app start ─────────────────
  Future<void> rescheduleOnStartup() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final medsSnapshot = await _firestore
          .collection('Medications')
          .where('patient_id', isEqualTo: uid)
          .where('is_active', isEqualTo: true)
          .get();

      for (final doc in medsSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        final drugId = data['drug_id'];
        if (drugId != null) {
          final drugDoc =
              await _firestore.collection('Drugs').doc(drugId).get();
          if (drugDoc.exists) {
            data['name'] = drugDoc.data()?['drug_name'] ?? 'Medication';
          }
        }

        await scheduleAllReminders(data);
      }

      debugPrint('[NotificationService] rescheduleOnStartup complete ✓');
    } catch (e) {
      debugPrint('[NotificationService] rescheduleOnStartup error: $e');
    }
  }
}