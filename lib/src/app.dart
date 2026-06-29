import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'config/dashboard_theme.dart'; // Use the new theme
import 'screens/station_dashboard_screen.dart';

class SensorMonitorApp extends StatelessWidget {
  const SensorMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crop Konnect',
      theme: buildAppTheme(),
      home: StationDashboardScreen(
        baseUrl: AppConfig.baseUrl,
      ),
    );
  }
}
