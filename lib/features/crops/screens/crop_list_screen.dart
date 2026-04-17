import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/crop_model.dart';
import '../../../routes/app_routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/crop_provider.dart';

class CropListScreen extends StatefulWidget {
  const CropListScreen({super.key});

  @override
  State<CropListScreen> createState() => _CropListScreenState();
}

class _CropListScreenState extends State<CropListScreen> {
  @override
  void initState() {
    super.initState();
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId != null) {
      context.read<CropProvider>().loadCrops(userId);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'harvested':
        return AppColors.secondary;
      case 'planning':
        return AppColors.info;
      default:
        return AppColors.textHint;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.grass;
      case 'harvested':
        return Icons.agriculture;
      case 'planning':
        return Icons.schedule;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Crops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Add filter functionality
            },
          ),
        ],
      ),
      body: Consumer<CropProvider>(
        builder: (context, cropProvider, _) {
          if (cropProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            );
          }

          if (cropProvider.crops.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.eco_outlined,
                    size: 80,
                    color: AppColors.textHint.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No crops yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add your first crop',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: cropProvider.crops.length,
            itemBuilder: (context, index) {
              final crop = cropProvider.crops[index];
              return _buildCropCard(context, crop);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.addCrop);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Crop'),
      ),
    );
  }

  Widget _buildCropCard(BuildContext context, Crop crop) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pushNamed(
              context,
              AppRoutes.cropDetail,
              arguments: crop,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _statusColor(crop.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _statusIcon(crop.status),
                    color: _statusColor(crop.status),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        crop.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor(crop.status)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              crop.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(crop.status),
                              ),
                            ),
                          ),
                          if (crop.type.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              crop.type,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Area badge
                if (crop.area > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${crop.area} ac',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
