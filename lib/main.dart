import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/main_navigation.dart';
import 'core/services/hive_service.dart';
import 'routes/app_routes.dart';

import 'features/auth/providers/auth_provider.dart';
import 'features/crops/providers/crop_provider.dart';
import 'features/finance/providers/finance_provider.dart';
import 'features/home/providers/dashboard_provider.dart';
import 'features/history/providers/history_provider.dart';
import 'features/settings/providers/settings_provider.dart';

import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/crops/screens/add_crop_screen.dart';
import 'features/crops/screens/crop_detail_screen.dart';
import 'features/finance/screens/add_expense_screen.dart';
import 'features/finance/screens/expense_list_screen.dart';
import 'features/finance/screens/finance_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';

import 'models/crop_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive (primary local database)
  await HiveService.init();

  // Initialize Firebase (needed for registration + sync)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const FarmApp());
}

class FarmApp extends StatelessWidget {
  const FarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CropProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          return MaterialApp(
            title: 'FarmApp',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            initialRoute: authProvider.isAuthenticated
                ? AppRoutes.home
                : AppRoutes.login,
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case AppRoutes.login:
                  return MaterialPageRoute(builder: (_) => const LoginScreen());
                case AppRoutes.register:
                  return MaterialPageRoute(
                    builder: (_) => const RegisterScreen(),
                  );
                case AppRoutes.home:
                  return MaterialPageRoute(
                    builder: (_) => const MainNavigation(),
                  );
                case AppRoutes.addCrop:
                  final crop = settings.arguments as Crop?;
                  return MaterialPageRoute(
                    builder: (_) => AddCropScreen(crop: crop),
                  );
                case AppRoutes.cropDetail:
                  final crop = settings.arguments as Crop;
                  return MaterialPageRoute(
                    builder: (_) => CropDetailScreen(crop: crop),
                  );
                case AppRoutes.finance:
                  return MaterialPageRoute(
                    builder: (_) => const FinanceScreen(),
                  );
                case AppRoutes.addExpense:
                  final cropInfo = settings.arguments as Map<String, String>?;
                  return MaterialPageRoute(
                    builder: (_) => AddExpenseScreen(cropInfo: cropInfo),
                  );
                case AppRoutes.expenseList:
                  final args = settings.arguments as Map<String, String>?;
                  return MaterialPageRoute(
                    builder: (_) => ExpenseListScreen(
                      cropId: args?['cropId'],
                      cropName: args?['cropName'],
                    ),
                  );
                case AppRoutes.settings:
                  return MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  );
                case AppRoutes.history:
                  return MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  );
                default:
                  return MaterialPageRoute(builder: (_) => const LoginScreen());
              }
            },
          );
        },
      ),
    );
  }
}
