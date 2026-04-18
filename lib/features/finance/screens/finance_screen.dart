import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/finance_provider.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId != null) {
      final financeProvider = context.read<FinanceProvider>();
      financeProvider.loadCommonExpenses(userId);
      financeProvider.fetchTotalExpenses(userId);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Common Expenses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOverviewTab(), _buildCommonExpensesTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.addExpense);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Consumer<FinanceProvider>(
      builder: (context, finance, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total expenses card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFEF5350)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.expense.withValues(alpha: 0.3),
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
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Total Expenses',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rs. ${finance.totalExpenses.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quick stats row
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      context,
                      'Common',
                      '${finance.commonExpenses.length}',
                      Icons.receipt_outlined,
                      AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statCard(
                      context,
                      'Crop-based',
                      '${finance.cropExpenses.length}',
                      Icons.eco_outlined,
                      AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                'Recent Expenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              if (finance.allExpenses.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: AppColors.textHint.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No expenses yet',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...finance.allExpenses
                    .take(10)
                    .map((expense) => _expenseListItem(context, expense)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommonExpensesTab() {
    return Consumer<FinanceProvider>(
      builder: (context, finance, _) {
        if (finance.commonExpenses.isEmpty) {
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
                  'No common expenses',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add farm-wide expenses here',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: finance.commonExpenses.length,
          itemBuilder: (context, index) {
            return _expenseListItem(context, finance.commonExpenses[index]);
          },
        );
      },
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _expenseListItem(BuildContext context, dynamic expense) {
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
            width: 44,
            height: 44,
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
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
    );
  }
}
