import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../models/crop_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/crop_provider.dart';

class AddCropScreen extends StatefulWidget {
  final Crop? crop; // null = add mode, non-null = edit mode

  const AddCropScreen({super.key, this.crop});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _soldAmountController = TextEditingController();
  final _consumedAmountController = TextEditingController();
  String _selectedStatus = 'growing';
  DateTime? _plantedDate;
  DateTime? _harvestedDate;
  bool _isLoading = false;

  bool get isEditMode => widget.crop != null;

  final List<String> _statusOptions = [
    'planning',
    'planted',
    'growing',
    'harvested',
    'sold',
    'consumed',
  ];

  @override
  void initState() {
    super.initState();
    if (isEditMode) {
      _nameController.text = widget.crop!.name;
      _selectedStatus = widget.crop!.status;
      _plantedDate = widget.crop!.plantedDate;
      _harvestedDate = widget.crop!.harvestedDate;
      if (widget.crop!.soldAmount != null) {
        _soldAmountController.text = widget.crop!.soldAmount!.toStringAsFixed(2);
      }
      if (widget.crop!.consumedEstimatedAmount != null) {
        _consumedAmountController.text =
            widget.crop!.consumedEstimatedAmount!.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _soldAmountController.dispose();
    _consumedAmountController.dispose();
    super.dispose();
  }

  bool get _showHarvestedDate =>
      _selectedStatus == 'harvested' ||
      _selectedStatus == 'sold' ||
      _selectedStatus == 'consumed';

  bool get _showSoldAmount => _selectedStatus == 'sold';

  bool get _showConsumedAmount => _selectedStatus == 'consumed';

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _plantedDate = picked);
    }
  }

  Future<void> _selectHarvestedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.secondary,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _harvestedDate = picked);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userId = context.read<AuthProvider>().user?.uid;
    if (userId == null) return;

    final cropProvider = context.read<CropProvider>();

    if (isEditMode) {
      // Update
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'status': _selectedStatus,
      };
      if (_plantedDate != null) {
        data['plantedDate'] = Timestamp.fromDate(_plantedDate!);
      }
      if (_showHarvestedDate && _harvestedDate != null) {
        data['harvestedDate'] = Timestamp.fromDate(_harvestedDate!);
      } else {
        data['harvestedDate'] = null;
      }
      if (_showSoldAmount) {
        data['soldAmount'] =
            double.tryParse(_soldAmountController.text.trim()) ?? 0.0;
        data['consumedEstimatedAmount'] = null;
      } else if (_showConsumedAmount) {
        data['consumedEstimatedAmount'] =
            double.tryParse(_consumedAmountController.text.trim()) ?? 0.0;
        data['soldAmount'] = null;
      } else {
        data['soldAmount'] = null;
        data['consumedEstimatedAmount'] = null;
      }

      final success = await cropProvider.updateCrop(
        userId,
        widget.crop!.id,
        data,
      );
      if (success && mounted) Navigator.pop(context);
    } else {
      // Add
      final crop = Crop(
        id: '',
        name: _nameController.text.trim(),
        status: _selectedStatus,
        plantedDate: _plantedDate,
        harvestedDate: _showHarvestedDate ? _harvestedDate : null,
        soldAmount: _showSoldAmount
            ? double.tryParse(_soldAmountController.text.trim())
            : null,
        consumedEstimatedAmount: _showConsumedAmount
            ? double.tryParse(_consumedAmountController.text.trim())
            : null,
      );
      final success = await cropProvider.addCrop(userId, crop);
      if (success && mounted) Navigator.pop(context);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(title: Text(isEditMode ? 'Edit Crop' : 'Add Crop')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextField(
                controller: _nameController,
                label: 'Crop Name',
                hint: 'e.g., Rice, Corn, Wheat',
                prefixIcon: Icons.eco_outlined,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter crop name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Status dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(
                    Icons.flag_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
                items: _statusOptions.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(status[0].toUpperCase() + status.substring(1)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedStatus = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Planted date picker
              GestureDetector(
                onTap: _selectDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Planted Date',
                      hintText: _plantedDate != null
                          ? dateFormat.format(_plantedDate!)
                          : 'Select date',
                      prefixIcon: const Icon(
                        Icons.calendar_today,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      suffixIcon: _plantedDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() => _plantedDate = null);
                              },
                            )
                          : null,
                    ),
                    controller: TextEditingController(
                      text: _plantedDate != null
                          ? dateFormat.format(_plantedDate!)
                          : '',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Harvested date picker — shown for harvested, sold, consumed
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showHarvestedDate
                    ? Column(
                        key: const ValueKey('harvestedDate'),
                        children: [
                          GestureDetector(
                            onTap: _selectHarvestedDate,
                            child: AbsorbPointer(
                              child: TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Harvested Date',
                                  hintText: _harvestedDate != null
                                      ? dateFormat.format(_harvestedDate!)
                                      : 'Select harvest date',
                                  prefixIcon: const Icon(
                                    Icons.agriculture,
                                    color: AppColors.secondaryDark,
                                    size: 22,
                                  ),
                                  suffixIcon: _harvestedDate != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear,
                                              size: 20),
                                          onPressed: () {
                                            setState(
                                                () => _harvestedDate = null);
                                          },
                                        )
                                      : null,
                                ),
                                controller: TextEditingController(
                                  text: _harvestedDate != null
                                      ? dateFormat.format(_harvestedDate!)
                                      : '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('noHarvestedDate')),
              ),

              // Sold amount field — shown only for 'sold' status
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showSoldAmount
                    ? Column(
                        key: const ValueKey('soldAmount'),
                        children: [
                          TextFormField(
                            controller: _soldAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Sold Amount (Rs.)',
                              hintText: 'Enter actual sale amount',
                              prefixIcon: Icon(
                                Icons.attach_money,
                                color: AppColors.income,
                                size: 22,
                              ),
                            ),
                            validator: (value) {
                              if (_showSoldAmount &&
                                  (value == null || value.isEmpty)) {
                                return 'Please enter the sold amount';
                              }
                              if (value != null &&
                                  value.isNotEmpty &&
                                  double.tryParse(value) == null) {
                                return 'Please enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('noSoldAmount')),
              ),

              // Consumed estimated amount field — shown only for 'consumed' status
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showConsumedAmount
                    ? Column(
                        key: const ValueKey('consumedAmount'),
                        children: [
                          TextFormField(
                            controller: _consumedAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Estimated Value (Rs.)',
                              hintText: 'Enter estimated consumption value',
                              prefixIcon: Icon(
                                Icons.restaurant,
                                color: AppColors.warning,
                                size: 22,
                              ),
                            ),
                            validator: (value) {
                              if (_showConsumedAmount &&
                                  (value == null || value.isEmpty)) {
                                return 'Please enter the estimated value';
                              }
                              if (value != null &&
                                  value.isNotEmpty &&
                                  double.tryParse(value) == null) {
                                return 'Please enter a valid number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('noConsumedAmount')),
              ),

              CustomButton(
                text: isEditMode ? 'Update Crop' : 'Add Crop',
                isLoading: _isLoading,
                icon: isEditMode ? Icons.save : Icons.add,
                onPressed: _handleSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
