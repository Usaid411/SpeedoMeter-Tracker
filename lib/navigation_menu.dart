import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:tracker/screens/historyscreen.dart';
import 'package:tracker/screens/mapscreen.dart';
import 'package:tracker/screens/speedometer.dart';

class NavigationMenu extends StatelessWidget {
  final String fullName;
  final String contactNumber;

  const NavigationMenu({
    super.key,
    required this.fullName,
    required this.contactNumber,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      NavigationController(fullName: fullName, contactNumber: contactNumber),
    );

    // Get screen size
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      bottomNavigationBar: Obx(
        () => NavigationBar(
          // Make height responsive
          height: screenHeight * 0.08, // 8% of screen height
          elevation: 0,
          selectedIndex: controller.selectedIndex.value,
          onDestinationSelected: (index) =>
              controller.selectedIndex.value = index,
          destinations: [
            NavigationDestination(
              icon: Icon(
                Iconsax.map_15,
                size: screenWidth * 0.06, // Responsive icon size
              ),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Iconsax.activity, size: screenWidth * 0.06),
              label: 'SpeedMeter',
            ),
            NavigationDestination(
              icon: Icon(Iconsax.activity5, size: screenWidth * 0.06),
              label: 'History',
            ),
          ],
          // Make label behavior responsive
          labelBehavior: screenWidth < 600
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
      body: Obx(
        () => Padding(
          // Add responsive padding if needed
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.02,
            vertical: screenHeight * 0.01,
          ),
          child: controller.screens[controller.selectedIndex.value],
        ),
      ),
    );
  }
}

class NavigationController extends GetxController {
  final Rx<int> selectedIndex = 0.obs;
  final List<Widget> screens;

  NavigationController({
    required String fullName,
    required String contactNumber,
  }) : screens = [
         MapScreen(fullName: fullName, contactNumber: contactNumber),
         SpeedometerScreen(fullName: fullName, contactNumber: contactNumber),
         const HistoryScreen(),
       ];
}
