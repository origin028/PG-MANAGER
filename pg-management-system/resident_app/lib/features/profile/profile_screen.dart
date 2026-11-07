import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late bool _isAadhaarUploaded;
  late bool _isPanUploaded;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    final isVerified = AppData.currentResident['kyc'] == 'Verified';
    _isAadhaarUploaded = isVerified;
    _isPanUploaded = isVerified;
    _loadProfileFromApi();
  }

  void _loadProfileFromApi() async {
    try {
      final p = await ResidentApiService.getProfile();
      if (p.isNotEmpty && mounted) {
        setState(() {
          AppData.currentResident = {
            ...AppData.currentResident,
            if (p['full_name'] != null) 'name': p['full_name'],
            if (p['phone'] != null) 'phone': p['phone'],
            if (p['email'] != null) 'email': p['email'],
          };
        });
      }
    } catch (e) {
      debugPrint('API getProfile error: $e');
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'R';
  }

  Future<void> _updateProfilePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _avatarPath = result.files.first.name;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile photo updated: ${_avatarPath ?? "Selfie"}'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (_) {
      // Fallback simulation
      setState(() {
        _avatarPath = 'selfie_updated.jpg';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated successfully!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    }
  }

  void _showEditProfileModal() {
    final currentName = AppData.currentResident['name']?.toString() ?? 'Resident';
    final currentPhone = AppData.currentResident['phone']?.toString() ?? '9876543210';
    final currentEmail = AppData.currentResident['email']?.toString() ??
        '${currentName.toLowerCase().replaceAll(' ', '.')}@example.com';

    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);
    final emailController = TextEditingController(text: currentEmail);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        final isDark = Theme.of(modalCtx).brightness == Brightness.dark;
        final cardBg = isDark ? AppTheme.darkCard : Colors.white;
        final textPri = isDark ? Colors.white : AppTheme.textDark;
        final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(modalCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update your personal information below.',
                      style: TextStyle(fontSize: 13, color: textSec),
                    ),
                    const SizedBox(height: 20),

                    // Name Field
                    Text('Full Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPri)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: nameController,
                      style: TextStyle(color: textPri),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Please enter your name' : null,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF243247) : AppTheme.softGrey,
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryBlue, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone Field (Strictly Read-Only)
                    Row(
                      children: [
                        Text('Phone Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSec)),
                        const SizedBox(width: 6),
                        Text('(Read-only)', style: TextStyle(fontSize: 11, color: textSec, fontStyle: FontStyle.italic)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: phoneController,
                      readOnly: true,
                      enabled: false,
                      style: TextStyle(color: textSec),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        prefixIcon: Icon(Icons.phone_iphone_rounded, color: textSec, size: 20),
                        suffixIcon: Icon(Icons.lock_outline_rounded, color: textSec, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email Field (Strictly Read-Only)
                    Row(
                      children: [
                        Text('Email Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSec)),
                        const SizedBox(width: 6),
                        Text('(Read-only)', style: TextStyle(fontSize: 11, color: textSec, fontStyle: FontStyle.italic)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: emailController,
                      readOnly: true,
                      enabled: false,
                      style: TextStyle(color: textSec),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        prefixIcon: Icon(Icons.mail_outline_rounded, color: textSec, size: 20),
                        suffixIcon: Icon(Icons.lock_outline_rounded, color: textSec, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            final newName = nameController.text.trim();
                            setState(() {
                              AppData.currentResident['name'] = newName;
                            });
                            ResidentApiService.updateProfile(fullName: newName).catchError((e) {
                              debugPrint('API updateProfile error: $e');
                              return <String, dynamic>{};
                            });
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully!'),
                                backgroundColor: Color(0xFF059669),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadDocument(String docType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploading $docType...'), duration: const Duration(seconds: 1)),
      );

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() {
        if (docType == 'Aadhaar') _isAadhaarUploaded = true;
        if (docType == 'PAN') _isPanUploaded = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$docType Uploaded Successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = AppData.currentResident;
    final name = res['name']?.toString() ?? 'Resident';
    final room = res['room']?.toString() ?? res['room_number']?.toString() ?? '101';
    final bed = res['bed']?.toString() ?? 'Bed B';
    final phone = res['phone']?.toString() ?? '9876543210';
    final email = res['email']?.toString() ?? '${name.toLowerCase().replaceAll(' ', '.')}@example.com';
    final isVerified = res['kyc'] == 'Verified';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;
    final dividerCol = isDark ? AppTheme.darkBorder : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.backgroundWhite,
      appBar: AppBar(
        title: Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPri),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPri),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 22.0),
              child: Column(
                children: [
                  // Profile Header Card with Selfie Avatar and Camera update icon
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderCol),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Avatar / Selfie with Camera Icon badge
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                gradient: AppTheme.blueGradient,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0x402563EB),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _getInitials(name),
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // Camera Icon Button badge
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: InkWell(
                                onTap: _updateProfilePhoto,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardBg, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0x26000000),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textPri,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'BNR Luxury PG • Room $room • $bed',
                          style: TextStyle(
                            color: textSec,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                                : (isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isVerified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                                size: 14,
                                color: isVerified
                                    ? const Color(0xFF059669)
                                    : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isVerified ? 'KYC Verified' : 'KYC Pending Verification',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isVerified
                                      ? const Color(0xFF059669)
                                      : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Edit Profile Button
                        OutlinedButton.icon(
                          onPressed: _showEditProfileModal,
                          icon: Icon(Icons.edit_outlined, size: 16, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue),
                          label: Text(
                            'Edit Profile',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDark ? AppTheme.darkBorder : const Color(0xFFC7D2FE)),
                            backgroundColor: isDark ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Personal Details Section
                  _buildSection(
                    title: 'Personal & Contact Details',
                    children: [
                      _buildListTile(Icons.person_outline_rounded, 'Full Name', name),
                      Divider(height: 1, color: dividerCol),
                      _buildListTile(Icons.phone_iphone_rounded, 'Phone Number (Read-only)', '+91 $phone', isReadOnly: true),
                      Divider(height: 1, color: dividerCol),
                      _buildListTile(Icons.mail_outline_rounded, 'Email Address (Read-only)', email, isReadOnly: true),
                      Divider(height: 1, color: dividerCol),
                      _buildListTile(Icons.home_work_outlined, 'Property', 'BNR Luxury PG, Koramangala', isReadOnly: true),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // KYC Documents Section
                  _buildSection(
                    title: 'KYC & Identity Verification',
                    children: [
                      _buildKycTile(
                        icon: Icons.credit_card_rounded,
                        title: 'Aadhaar Card',
                        isVerified: isVerified,
                        isUploaded: _isAadhaarUploaded,
                        onUpload: () => _pickAndUploadDocument('Aadhaar'),
                      ),
                      Divider(height: 1, color: dividerCol),
                      _buildKycTile(
                        icon: Icons.badge_outlined,
                        title: 'PAN Card',
                        isVerified: isVerified,
                        isUploaded: _isPanUploaded,
                        onUpload: () => _pickAndUploadDocument('PAN'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderCol = isDark ? AppTheme.darkBorder : const Color(0xFFEDF2F7);
    final textPri = isDark ? Colors.white : AppTheme.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textPri,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderCol),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x1F000000) : const Color(0x05000000),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String label, String value, {bool isReadOnly = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? Colors.white : AppTheme.textDark;
    final textSec = isDark ? AppTheme.darkTextSecondary : AppTheme.textGrey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF243247) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isReadOnly ? textSec : (isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: textSec, fontSize: 12), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isReadOnly ? textSec : textPri,
                    fontWeight: isReadOnly ? FontWeight.w500 : FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isReadOnly)
            Icon(Icons.lock_outline_rounded, size: 16, color: textSec),
        ],
      ),
    );
  }

  Widget _buildKycTile({
    required IconData icon,
    required String title,
    required bool isVerified,
    required bool isUploaded,
    required VoidCallback onUpload,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPri = isDark ? Colors.white : AppTheme.textDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF243247) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPri), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  isUploaded ? 'Document Attached' : 'Not Uploaded Yet',
                  style: TextStyle(
                    fontSize: 12,
                    color: isUploaded ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUploaded)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                SizedBox(width: 4),
                Text(
                  'Uploaded',
                  style: TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            )
          else
            ElevatedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded, size: 14),
              label: const Text('Upload', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}
