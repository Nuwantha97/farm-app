import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 24,
              ),
              decoration: const BoxDecoration(
                gradient: AppColors.headerGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Online Sync Section ──
                  _sectionTitle(context, 'Cloud Sync'),
                  const SizedBox(height: 12),
                  _syncCard(context),
                  const SizedBox(height: 28),

                  // ── Account Section ──
                  _sectionTitle(context, 'Account'),
                  const SizedBox(height: 12),
                  _logoutCard(context),
                  const SizedBox(height: 12),
                  _deleteAccountCard(context),
                  const SizedBox(height: 28),

                  // ── About Section ──
                  _sectionTitle(context, 'About'),
                  const SizedBox(height: 12),
                  _aboutCard(context),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  // ── Sync Card ─────────────────────────────────────────────

  Widget _syncCard(BuildContext context) {
    return Consumer2<SettingsProvider, AuthProvider>(
      builder: (context, settings, auth, _) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              // Toggle
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: settings.isSyncEnabled
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.textHint.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      settings.isSyncEnabled
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      color: settings.isSyncEnabled
                          ? AppColors.primary
                          : AppColors.textHint,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Online Sync',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          settings.isSyncEnabled
                              ? 'Data syncs with cloud'
                              : 'Data stored locally only',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: settings.isSyncEnabled,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? AppColors.primary
                            : null),
                    onChanged: settings.isSyncing
                        ? null
                        : (value) {
                            settings.toggleSync(value, auth);
                          },
                  ),
                ],
              ),

              if (settings.isSyncEnabled) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Last sync time
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      settings.lastSyncTime != null
                          ? 'Last synced: ${DateFormat('MMM d, y h:mm a').format(settings.lastSyncTime!)}'
                          : 'Never synced',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sync Now button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: settings.isSyncing
                        ? null
                        : () => settings.syncNow(auth),
                    icon: settings.isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                        settings.isSyncing ? 'Syncing...' : 'Sync Now'),
                  ),
                ),

                // Sync result
                if (settings.lastSyncResult != null &&
                    !settings.isSyncing) ...[
                  const SizedBox(height: 8),
                  Text(
                    '↑ ${settings.lastSyncResult!.pushed} pushed  '
                    '↓ ${settings.lastSyncResult!.pulled} pulled'
                    '${settings.lastSyncResult!.conflicts > 0 ? '  ⚡ ${settings.lastSyncResult!.conflicts} resolved' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                  ),
                ],

                // Error
                if (settings.syncError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 18, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            settings.syncError!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Logout Card ───────────────────────────────────────────

  Widget _logoutCard(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return _actionCard(
          context,
          icon: Icons.logout,
          iconColor: AppColors.info,
          title: 'Logout',
          subtitle: 'Sign out of your account',
          onTap: () => _showLogoutDialog(context, settings.isSyncEnabled),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, bool syncEnabled) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to sign out?\nYour data will remain stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<AuthProvider>()
                  .logout(syncEnabled: syncEnabled);
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.login,
                  (route) => false,
                );
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ── Delete Account Card ───────────────────────────────────

  Widget _deleteAccountCard(BuildContext context) {
    return _actionCard(
      context,
      icon: Icons.delete_forever,
      iconColor: AppColors.error,
      title: 'Delete Account',
      subtitle: 'Permanently remove your account & data',
      onTap: () => _showDeleteDialog(context),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 28),
            const SizedBox(width: 8),
            const Text('Delete Account'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is permanent and cannot be undone.\n'
              'All your data will be deleted.\n\n'
              'Enter your password and type DELETE to confirm:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
                prefixIcon: Icon(Icons.text_fields),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () async {
              if (confirmController.text.trim() != 'DELETE') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please type DELETE to confirm'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              final auth = context.read<AuthProvider>();
              final success =
                  await auth.deleteAccount(passwordController.text);

              if (context.mounted) {
                if (success) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.login,
                    (route) => false,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          auth.errorMessage ?? 'Failed to delete account'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }

  // ── About Card ────────────────────────────────────────────

  Widget _aboutCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FarmApp',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Version 1.0.0',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.storage, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Data stored locally with AES-256 encryption',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared action card widget ─────────────────────────────

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
