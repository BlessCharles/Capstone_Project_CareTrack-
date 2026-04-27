import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final String fullName;
  
  const VerifyOtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.fullName,
  });

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = false;

  // Verify the OTP code
  Future<void> _verifyCode() async {
    String code = _controllers.map((c) => c.text).join();
    
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit code'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Create credential
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: code,
      );

      // Sign in with credential
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      // Check if user exists in Firestore
      String uid = userCredential.user!.uid;
      String phoneNumber = '+233${widget.phoneNumber}';
      
      DocumentSnapshot userDoc = await _firestore.collection('Users').doc(uid).get();
      
      if (!userDoc.exists) {
        // New user - create user document
        await _firestore.collection('Users').doc(uid).set({
          'phone_number': phoneNumber,
          'full_name': widget.fullName,
          'created_at': FieldValue.serverTimestamp(),
        });
        
        // Create patient document
        await _firestore.collection('Patients').add({
          'user_id': uid,
          'discharge_date': Timestamp.now(), // Placeholder - can be updated
        });
      }
      
      // Navigate to dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.blue[600],
        title: const Text('Verify Phone', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 32),
            
            const Text(
              'Enter verification code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Code sent to +233 ${widget.phoneNumber}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            
            const SizedBox(height: 4),
            
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Change number',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
            
            const SizedBox(height: 40),
            
            Text(
              'Enter 6-digit code',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700]),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 48,
                  height: 56,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.blue[600]!, width: 2),
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      }
                      setState(() {});
                    },
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 32),
            
            Text("Didn't receive the code?", style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {},
              child: const Text('Resend Code (0:45)', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            
            const SizedBox(height: 24),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.yellow[50],
                border: Border.all(color: Colors.yellow[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 13, color: Colors.yellow[900], height: 1.4),
                        children: const [
                          TextSpan(text: 'Tip: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: 'The verification code may take up to 2 minutes to arrive. Check your SMS inbox.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_isComplete() && !_isLoading) ? _verifyCode : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isComplete() ? Colors.blue[600] : Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Verify & Continue',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  bool _isComplete() {
    return _controllers.every((c) => c.text.isNotEmpty);
  }
}