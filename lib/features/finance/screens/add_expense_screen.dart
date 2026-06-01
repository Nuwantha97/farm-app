import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../models/expense_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../crops/providers/crop_provider.dart';
import '../providers/finance_provider.dart';

class AddExpenseScreen extends StatefulWidget {
  final Map<String, String>?
  cropInfo; // {cropId, cropName} for pre-selected crop

  const AddExpenseScreen({super.key, this.cropInfo});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isCommonExpense = true;
  String? _selectedCropId;
  String? _selectedCropName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.cropInfo != null) {
      _isCommonExpense = false;
      _selectedCropId = widget.cropInfo!['cropId'];
      _selectedCropName = widget.cropInfo!['cropName'];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userId = context.read<AuthProvider>().currentUserId;
    if (userId == null) return;

    final financeProvider = context.read<FinanceProvider>();

    final expense = Expense(
      id: '',
      title: _titleController.text.trim(),
      amount: double.tryParse(_amountController.text) ?? 0.0,
      date: _selectedDate,
      cropId: _isCommonExpense ? null : _selectedCropId,
      cropName: _isCommonExpense ? null : _selectedCropName,
    );

    bool success;
    if (_isCommonExpense) {
      success = await financeProvider.addCommonExpense(userId, expense);
    } else {
      if (_selectedCropId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please select a crop')));
        setState(() => _isLoading = false);
        return;
      }
      success = await financeProvider.addCropExpense(
        userId,
        _selectedCropId!,
        expense,
      );
    }

    if (success && mounted) Navigator.pop(context);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final crops = context.watch<CropProvider>().crops;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expense type toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isCommonExpense = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isCommonExpense
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Common',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isCommonExpense
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isCommonExpense = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isCommonExpense
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Crop-based',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: !_isCommonExpense
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Crop selector (only when crop-based)
              if (!_isCommonExpense) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedCropId,
                  decoration: const InputDecoration(
                    labelText: 'Select Crop',
                    prefixIcon: Icon(
                      Icons.eco_outlined,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                  items: crops.map((crop) {
                    return DropdownMenuItem(
                      value: crop.id,
                      child: Text(crop.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    final crop = crops.firstWhere((c) => c.id == value);
                    setState(() {
                      _selectedCropId = value;
                      _selectedCropName = crop.name;
                    });
                  },
                  validator: (value) {
                    if (!_isCommonExpense && value == null) {
                      return 'Please select a crop';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              CustomTextField(
                controller: _titleController,
                label: 'Expense Title',
                hint: 'e.g., Bought fertilizer',
                prefixIcon: Icons.title,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter expense title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              CustomTextField(
                controller: _amountController,
                label: 'Amount (Rs.)',
                hint: 'e.g., 5000',
                prefixIcon: Icons.attach_money,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Date picker
              GestureDetector(
                onTap: _selectDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Date',
                      prefixIcon: const Icon(
                        Icons.calendar_today,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                    controller: TextEditingController(
                      text: dateFormat.format(_selectedDate),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              CustomButton(
                text: 'Save Expense',
                isLoading: _isLoading,
                icon: Icons.save,
                onPressed: _handleSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
