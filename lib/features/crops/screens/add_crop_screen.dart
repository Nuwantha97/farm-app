import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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
  final _areaController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedStatus = 'active';
  DateTime? _plantedDate;
  bool _isLoading = false;

  bool get isEditMode => widget.crop != null;

  final List<String> _statusOptions = ['planning', 'active', 'harvested'];

  @override
  void initState() {
    super.initState();
    if (isEditMode) {
      _nameController.text = widget.crop!.name;
      _typeController.text = widget.crop!.type;
      _areaController.text =
          widget.crop!.area > 0 ? widget.crop!.area.toString() : '';
      _notesController.text = widget.crop!.notes;
      _selectedStatus = widget.crop!.status;
      _plantedDate = widget.crop!.plantedDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _areaController.dispose();
    _notesController.dispose();
    super.dispose();
  }

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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userId = context.read<AuthProvider>().user?.uid;
    if (userId == null) return;

    final cropProvider = context.read<CropProvider>();

    if (isEditMode) {
      // Update
      final data = {
        'name': _nameController.text.trim(),
        'type': _typeController.text.trim(),
        'status': _selectedStatus,
        'area': double.tryParse(_areaController.text) ?? 0.0,
        'notes': _notesController.text.trim(),
      };
      if (_plantedDate != null) {
        data['plantedDate'] = _plantedDate!;
      }
      final success =
          await cropProvider.updateCrop(userId, widget.crop!.id, data);
      if (success && mounted) Navigator.pop(context);
    } else {
      // Add
      final crop = Crop(
        id: '',
        name: _nameController.text.trim(),
        type: _typeController.text.trim(),
        status: _selectedStatus,
        plantedDate: _plantedDate,
        area: double.tryParse(_areaController.text) ?? 0.0,
        notes: _notesController.text.trim(),
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
      appBar: AppBar(
        title: Text(isEditMode ? 'Edit Crop' : 'Add Crop'),
      ),
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

              CustomTextField(
                controller: _typeController,
                label: 'Crop Type',
                hint: 'e.g., Grain, Vegetable, Fruit',
                prefixIcon: Icons.category_outlined,
              ),
              const SizedBox(height: 16),

              // Status dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.flag_outlined,
                      color: AppColors.textSecondary, size: 22),
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

              CustomTextField(
                controller: _areaController,
                label: 'Area (acres)',
                hint: 'e.g., 2.5',
                prefixIcon: Icons.square_foot,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),

              // Date picker
              GestureDetector(
                onTap: _selectDate,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Planted Date',
                      hintText: _plantedDate != null
                          ? dateFormat.format(_plantedDate!)
                          : 'Select date',
                      prefixIcon: const Icon(Icons.calendar_today,
                          color: AppColors.textSecondary, size: 22),
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

              CustomTextField(
                controller: _notesController,
                label: 'Notes',
                hint: 'Any additional notes...',
                prefixIcon: Icons.notes,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

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
