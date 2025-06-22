import 'package:flutter/material.dart';
import 'package:tracker/dialogbox.dart';
import 'package:tracker/navigation_menu.dart';

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showUserInfoDialog();
    });
  }

  Future<void> _showUserInfoDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UserInfoDialog(),
    );

    if (result != null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => NavigationMenu(
              fullName: result['fullName']!,
              contactNumber: result['contactNumber']!,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User information is required to proceed.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
