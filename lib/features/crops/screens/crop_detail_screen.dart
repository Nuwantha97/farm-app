import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/crop_model.dart';
import '../../../models/expense_model.dart';
import '../../../routes/app_routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../../finance/providers/finance_provider.dart';
import '../providers/crop_provider.dart';

class CropDetailScreen extends StatefulWidget {
  final Crop crop;

  const CropDetailScreen({super.key, required this.crop});

  @override
  State<CropDetailScreen> createState() => _CropDetailScreenState();
}

class _CropDetailScreenState extends State<CropDetailScreen> {
  @override
  void initState() {
    super.initState();
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId != null) {
      context.read<FinanceProvider>().loadCropExpenses(
            userId,
            widget.crop.id,
            cropName: widget.crop.name,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final crop = widget.crop;
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(crop.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.addCrop,
                arguments: crop,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, crop),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.headerGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.eco, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              crop.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                crop.status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _infoChip(Icons.category_outlined, 'Type', crop.type),
                      const SizedBox(width: 16),
                      _infoChip(Icons.square_foot, 'Area', '${crop.area} ac'),
                      const SizedBox(width: 16),
                      _infoChip(
                        Icons.calendar_today,
                        'Planted',
                        crop.plantedDate != null
                            ? dateFormat.format(crop.plantedDate!)
                            : 'N/A',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Notes
            if (crop.notes.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      crop.notes,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Expenses Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Crop Expenses',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.addExpense,
                      arguments: {'cropId': crop.id, 'cropName': crop.name},
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Consumer<FinanceProvider>(
              builder: (context, financeProvider, _) {
                if (financeProvider.cropExpenses.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: AppColors.textHint.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No expenses recorded',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: financeProvider.cropExpenses
                      .map((expense) => _buildExpenseItem(context, expense))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(BuildContext context, Expense expense) {
    final dateFormat = DateFormat('MMM dd');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_outlined,
              color: AppColors.expense,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                      ),
                ),
                Text(
                  '${expense.category} • ${dateFormat.format(expense.date)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          Text(
            'Rs. ${expense.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.expense,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Crop crop) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Crop'),
        content: Text('Are you sure you want to delete "${crop.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final parentNavigator = Navigator.of(context);
              final userId = context.read<AuthProvider>().user?.uid;
              if (userId != null) {
                await context.read<CropProvider>().deleteCrop(userId, crop.id);
              }
              if (mounted) {
                navigator.pop();
                parentNavigator.pop();
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
