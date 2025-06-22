import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CustomSaveDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final IconData icon;

  const CustomSaveDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'SAVE',
    this.cancelText = 'DISCARD',
    this.icon = Icons.directions_bike_sharp,
  });

  @override
  Widget build(BuildContext context) {
    // Get screen size
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Dialog(
      backgroundColor: const Color.fromARGB(255, 236, 233, 233),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isSmallScreen ? 40 : 50, color: Colors.blueAccent),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              message,
              style: const TextStyle(color: Colors.black),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 16 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Colors.red),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 16 : 24,
                      vertical: isSmallScreen ? 8 : 12,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    cancelText,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 16 : 24,
                      vertical: isSmallScreen ? 8 : 12,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    confirmText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      fontSize: isSmallScreen ? 14 : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UserInfoDialog extends StatefulWidget {
  @override
  _UserInfoDialogState createState() => _UserInfoDialogState();
}

class _UserInfoDialogState extends State<UserInfoDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final fullName = _nameController.text.trim();
      final contactNumber = _contactController.text.trim();

      const String scriptURL =
          "https://script.google.com/macros/s/...../exec  //LOOKS LIKE THIS";
      try {
        final response = await http.post(
          Uri.parse(scriptURL),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            'action': 'saveUserInfo',
            'fullName': fullName,
            'contactNumber': contactNumber,
          }),
        );

        if (response.statusCode == 200) {
          print("Data saved to Google Sheets: ${response.body}");
        } else {
          print("Failed to save: ${response.body}");
        }
      } catch (e) {
        print("Error: $e");
      }

      Navigator.of(
        context,
      ).pop({'fullName': fullName, 'contactNumber': contactNumber});
    }
  }

  InputDecoration _buildInputDecoration(
    String label,
    IconData icon,
    BuildContext context,
  ) {
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: Colors.blueAccent,
        size: isSmallScreen ? 20 : 24,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blueAccent, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(
        vertical: isSmallScreen ? 12 : 16,
        horizontal: isSmallScreen ? 12 : 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isSmallScreen ? 16 : 24,
          horizontal: isSmallScreen ? 16 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person,
              size: isSmallScreen ? 40 : 48,
              color: Colors.blueAccent,
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'Enter Your Info',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: _buildInputDecoration(
                      'Full Name',
                      Icons.person_outline,
                      context,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Full Name is required'
                        : null,
                    style: TextStyle(fontSize: isSmallScreen ? 14 : null),
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  TextFormField(
                    controller: _contactController,
                    decoration: _buildInputDecoration(
                      'Contact Number',
                      Icons.phone,
                      context,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Contact number is required'
                        : null,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(fontSize: isSmallScreen ? 14 : null),
                  ),
                ],
              ),
            ),
            SizedBox(height: isSmallScreen ? 16 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: Icon(
                    Icons.arrow_forward,
                    color: Colors.black,
                    size: isSmallScreen ? 16 : 18,
                  ),
                  label: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 16 : 20,
                      vertical: isSmallScreen ? 8 : 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
