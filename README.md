--------------------------------------------------------------------------------
CARETRACK+: POST-DISCHARGE PATIENT RECOVERY MANAGEMENT

README / DOCUMENTATION
--------------------------------------------------------------------------------

Author      : Bless Charles Oppong

Institution : Ashesi University

Major       : Management Information Systems

Year        : 2026
 
 
--------------------------------------------------------------------------------
1. GITHUB REPOSITORY
--------------------------------------------------------------------------------
 
The full source code for CareTrack+ is hosted on GitHub at the following link:
 
    https://github.com/BlessCharles/Capstone_Project_CareTrack-.git
 
To clone the repository, open a terminal and run:
 
    git clone https://github.com/BlessCharles/Capstone_Project_CareTrack-.git
 
 
--------------------------------------------------------------------------------
2. PROJECT OVERVIEW
--------------------------------------------------------------------------------
 
CareTrack+ is a mobile application built with Flutter and Firebase that supports
patients and caregivers during the post-discharge recovery period. The system
allows patients to track medications, log discharge instructions, schedule
follow-up appointments, manage dietary and activity restrictions, and designate
a trusted family member (Second_Eye) to monitor their recovery remotely.
 
The application runs on Android devices and was developed and tested on a
Google Pixel 7A running Android 14.
 
 
--------------------------------------------------------------------------------
3. PREREQUISITES
--------------------------------------------------------------------------------
 
Before running the application from source, ensure the following are installed
on your machine:
 
    - Flutter SDK (version 3.x or later)
        https://docs.flutter.dev/get-started/install
 
    - Dart SDK (included with Flutter)
 
    - Android Studio (for the Android emulator and SDK tools)
        https://developer.android.com/studio
 
    - Visual Studio Code (recommended code editor)
        https://code.visualstudio.com/
 
    - A physical Android device OR an Android emulator (API level 30 or higher
      recommended)
 
To verify your Flutter installation is set up correctly, run:
 
    flutter doctor
 
All items should show a green checkmark before proceeding.
 
 
--------------------------------------------------------------------------------
4. FIREBASE CONFIGURATION (IMPORTANT)
--------------------------------------------------------------------------------

CareTrack+ uses Firebase for authentication, database, and push notifications.
The Firebase configuration file (google-services.json) is already included in
the repository at:

    android/app/google-services.json

No additional Firebase setup is required. Once you clone the repository and
run flutter pub get, the app will automatically connect to the existing
Firebase backend. All services (Phone Authentication, Cloud Firestore, and
Firebase Cloud Messaging) are already configured and live.
 
 
--------------------------------------------------------------------------------
5. HOW TO RUN THE APPLICATION
--------------------------------------------------------------------------------
 
OPTION A: Run on a Physical Android Device (Recommended)
 
    1. Clone the repository (see Section 1)
    2. Open the project folder in Visual Studio Code or Android Studio
    3. Connect your Android phone to your computer via USB, or connect wirelessly over the same Wi-Fi network using Android Studio's wireless debugging feature
    4. Open a terminal in the project root directory and run:
 
           flutter pub get
 
       This installs all required dependencies.
 
    6. Then run the application with:
 
           flutter run
 
       Or, in Android Studio, select your connected device from the device dropdown and click the Run button.
 
    7. The app will compile and appear on your device automatically.
 
 
OPTION B: Run on an Android Emulator
 
    1. Open Android Studio and launch the AVD Manager
       (Tools > Device Manager)
    2. Create or start an existing Android Virtual Device (AVD)
       (API level 30 or higher recommended)
    3. Once the emulator is running, follow steps 1-6 from Option A above.
       Flutter will automatically detect the emulator as a target device.
 
NOTE: Phone number OTP authentication requires either a real SIM-connected
device or Firebase test phone numbers configured in the Firebase console.
For testing purposes, the following test credentials were used during
development and can be configured in your Firebase project:
 
    Test phone number : +233 553 573 155
    Test OTP code     : 123456
 
These must be added manually under Authentication > Sign-in method >
Phone > Phone numbers for testing in your Firebase console.
 
 
--------------------------------------------------------------------------------
6. PROJECT STRUCTURE
--------------------------------------------------------------------------------
 
The source code is organized as follows:
 
    caretrack_plus/
    ├── lib/
    │   ├── main.dart                    Entry point and welcome screen
    │   ├── enter_phone_screen.dart      Phone number input and OTP request
    │   ├── verify_otp_screen.dart       OTP verification and user registration
    │   ├── dashboard_screen.dart        Main patient dashboard
    │   ├── add_medication_screen.dart   Add medication form
    │   ├── add_appointment_screen.dart  Add appointment form
    │   ├── add_instruction_screen.dart  Add discharge instruction form
    |   ├── add_new_screen.dart          Access point to access the add medication, appointment, and instruction buttons 
    │   ├── medication_detail_screen.dart Medication detail and adherence view
    |   ├── edit_appointment_screen.dart  Edit the appointment information 
    │   ├── expired_screen.dart          Expired medications and appointments
    │   ├── profile_screen.dart          User profile
    |   ├── notification_service.dart    Handles the notifications/alerts the patients receives to remind them about their medications
    │   └── second_eye_screen.dart       Caregiver (Second_Eye) management
    │
    ├── android/
    │   └── app/
    │       └── google-services.json     
    │
    ├── pubspec.yaml                     Flutter dependencies
    └── README.txt                       This file
 
 
--------------------------------------------------------------------------------
7. KEY DEPENDENCIES
--------------------------------------------------------------------------------
 
The following Flutter packages are used in this project (defined in
pubspec.yaml):
 
    - firebase_core               Firebase initialization
    - firebase_auth               Phone number authentication
    - cloud_firestore             NoSQL cloud database
    - firebase_messaging          Push notifications to caregivers
    - flutter_local_notifications On-device medication reminders
    - intl                        Date and time formatting
 
All dependencies are installed automatically when you run:
 
    flutter pub get
 
 
--------------------------------------------------------------------------------
8. USER MANUAL
--------------------------------------------------------------------------------
 
A full user manual is included in the appendix of the pdf document in the zip file
 
It covers account registration, adding medications, scheduling appointments, logging discharge instructions, and using the Second_Eye feature. Please refer
to it for step-by-step guidance on using the application.
 
 
--------------------------------------------------------------------------------
9. ADDITIONAL NOTES
--------------------------------------------------------------------------------
 
    - The application was developed and tested on Android only. iOS support is planned for a future version.
 
    - The application supports basic offline functionality. Medication reminders stored locally will still trigger without an internet
      connection, but data sync and caregiver alerts require connectivity.
 
    - Firebase Cloud Functions were used to detect missed medication doses and trigger caregiver alerts. These functions are deployed separately
      to Firebase and are not included in the local source code.
 
    - For any questions regarding the source code or setup, please contact:
          bless.oppong@ashesi.edu.gh

