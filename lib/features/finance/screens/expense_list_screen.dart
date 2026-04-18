import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/finance_provider.dart';

class ExpenseListScreen extends StatelessWidget {
  final String? cropId;
  final String? cropName;

  const ExpenseListScreen({super.key, this.cropId, this.cropName});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(cropName != null ? '$cropName Expenses' : 'All Expenses'),
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, finance, _) {
          final expenses = cropId != null
              ? finance.cropExpenses
              : finance.commonExpenses;

          if (expenses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: AppColors.textHint.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No expenses found',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final expense = expenses[index];
              return Dismissible(
                key: Key(expense.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  final userId = context.read<AuthProvider>().user?.uid;
                  if (userId != null) {
                    if (expense.cropId != null) {
                      context.read<FinanceProvider>().deleteCropExpense(
                        userId,
                        expense.cropId!,
                        expense.id,
                      );
                    } else {
                      context.read<FinanceProvider>().deleteCommonExpense(
                        userId,
                        expense.id,
                      );
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.expense.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateFormat.format(expense.date),
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Rs. ${expense.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.expense,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
