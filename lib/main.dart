import 'package:flutter/material.dart';

import 'app.dart';
import 'screens/lock/lock_screen.dart';
import 'services/recurring_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await RecurringService().generateDueTransactions();
  } catch (error) {
    debugPrint('Erro ao gerar recorrências: $error');
  }

  runApp(LockGate(child: const FinanceApp()));
}
