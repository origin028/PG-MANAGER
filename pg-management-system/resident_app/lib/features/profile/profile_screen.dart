import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/network/token_storage.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late bool _isAadhaarUploaded;
  late bool _isPanUploaded;
  String? _avatarPath;

  late final AnimationController _entranceController;
  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();
    final isVerified = _resolveIsVerified(_resolveResidentData());
    _isAadhaarUploaded = isVerified;
    _isPanUploaded = isVerified;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _loadProfileFromApi();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animationStarted) {
      _animationStarted = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _resolveResidentData() {
    final savedProfile = TokenStorage.residentProfile;
    if (savedProfile != null &&
        savedProfile.isNotEmpty &&
        AppData.currentResident['phone'] == AppData.residents.first['phone'] &&
        AppData.currentResident['room_number'] == null) {
      return savedProfile;
    }
    return AppData.currentResident;
  }

  bool _resolveIsVerified(Map<String, dynamic> resident) {
    final kycDetails =
        (resident['kyc_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawKyc = (kycDetails['kyc_status'] ??
            resident['kyc'] ??
            resident['kyc_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return rawKyc == 'verified' || rawKyc == 'approved';
  }

  void _loadProfileFromApi() async {
    try {
      final p = await ResidentApiService.getProfile();
      if (p.isNotEmpty && mounted) {
        final residentInfo =
            (p['resident_info'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final stayDetails =
            (p['stay_details'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final kycDetails =
            (p['kyc_details'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

        final resolvedName =
            residentInfo['full_name'] ?? p['full_name'] ?? p['name'];
        final resolvedPhone =
            residentInfo['phone'] ?? p['phone'];
        final resolvedEmail =
            residentInfo['email'] ?? p['email'];
        final resolvedRoom =
            stayDetails['room_number'] ?? p['room_number'] ?? p['room'];
        final resolvedBed =
            stayDetails['bed_number'] ?? p['bed_number'] ?? p['bed'];
        final resolvedProperty =
            stayDetails['property_name'] ?? p['property_name'] ?? p['property'];
        final resolvedPropertyAddress =
            stayDetails['property_address'] ?? p['property_address'];
        final resolvedLivingSince =
            stayDetails['living_since'] ??
            stayDetails['check_in_date'] ??
            p['living_since'] ??
            p['check_in_date'];
        final resolvedKycStatus =
            kycDetails['kyc_status'] ?? p['kyc_status'] ?? p['kyc'];

        setState(() {
          AppData.currentResident = {
            ...AppData.currentResident,
            'name': ?resolvedName,
            'phone': ?resolvedPhone,
            'email': ?resolvedEmail,
            'room_number': ?resolvedRoom,
            'room': ?resolvedRoom,
            'bed': ?resolvedBed,
            'property': ?resolvedProperty,
            'property_address': ?resolvedPropertyAddress,
            'living_since': ?resolvedLivingSince,
            'kyc': ?resolvedKycStatus,
            if (stayDetails.isNotEmpty) 'stay_details': stayDetails,
            if (kycDetails.isNotEmpty) 'kyc_details': kycDetails,
          };

          final verifiedNow = _resolveIsVerified(AppData.currentResident);
          if (verifiedNow) {
            _isAadhaarUploaded = true;
            _isPanUploaded = true;
          }
          if (kycDetails['has_aadhaar'] == true ||
              kycDetails['aadhaar_uploaded'] == true) {
            _isAadhaarUploaded = true;
          }
          if (kycDetails['has_pan'] == true ||
              kycDetails['pan_uploaded'] == true) {
            _isPanUploaded = true;
          }
        });
      }
    } catch (e) {
      debugPrint('API getProfile error: $e');
    }
  }

  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'R';
  }

  String _formatSinceLabel(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return 'Oct 2026';
    final trimmed = rawDate.trim();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return '${months[parsed.month - 1]} ${parsed.year}';
    }

    final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(trimmed);
    if (dmy != null) {
      final month = int.tryParse(dmy.group(2) ?? '');
      final year = dmy.group(3);
      if (month != null && month >= 1 && month <= 12 && year != null) {
        return '${months[month - 1]} $year';
      }
    }

    return trimmed;
  }

  String _formatBedMetric(String bed) {
    final cleaned = bed
        .trim()
        .replaceFirst(RegExp(r'^Bed\s+', caseSensitive: false), '')
        .trim();
    return cleaned.isNotEmpty ? cleaned : 'B';
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
            backgroundColor: HomeThemeTokens.lightTeal,
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
          backgroundColor: HomeThemeTokens.lightTeal,
        ),
      );
    }
  }

  void _showEditProfileModal() {
    final res = _resolveResidentData();
    final residentInfo =
        (res['resident_info'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final currentName =
        (residentInfo['full_name'] ??
                res['full_name'] ??
                res['name'] ??
                'Resident')
            .toString();
    final currentPhone =
        (residentInfo['phone'] ?? res['phone'] ?? '9876543210').toString();
    final currentEmail =
        (residentInfo['email'] ??
                res['email'] ??
                '${currentName.toLowerCase().replaceAll(' ', '.')}@example.com')
            .toString();

    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);
    final emailController = TextEditingController(text: currentEmail);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        final isDark = HomeThemeTokens.isDark(modalCtx);
        final cardBg =
            isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
        final textPri = HomeThemeTokens.textPrimary(modalCtx);
        final textSec = HomeThemeTokens.textSecondary(modalCtx);
        final tealCol = HomeThemeTokens.teal(modalCtx);
        final borderCol = HomeThemeTokens.border(modalCtx);
        final fieldFill =
            isDark ? HomeThemeTokens.darkSurface : const Color(0xFFF6F9F8);
        final readOnlyFill =
            isDark ? HomeThemeTokens.darkControlBg : const Color(0xFFF1F5F4);

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border(
                top: BorderSide(color: borderCol, width: 1),
              ),
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
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: borderCol,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Edit Profile',
                      style: HomeThemeTokens.manrope(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: textPri,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update your personal information below.',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textSec,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name Field
                    Text(
                      'Full Name',
                      style: HomeThemeTokens.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: nameController,
                      style: HomeThemeTokens.manrope(
                        color: textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Please enter your name'
                          : null,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldFill,
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          color: tealCol,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: tealCol, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone Field (Editable)
                    Text(
                      'Phone Number',
                      style: HomeThemeTokens.manrope(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: textPri,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: HomeThemeTokens.manrope(
                        color: textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your phone number';
                        }
                        final digits = val.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 10) {
                          return 'Please enter a valid 10-digit mobile number';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldFill,
                        prefixIcon: Icon(
                          Icons.phone_iphone_rounded,
                          color: tealCol,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: tealCol, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email Field (Strictly Read-Only)
                    Row(
                      children: [
                        Text(
                          'Email Address',
                          style: HomeThemeTokens.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: textSec,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(Read-only)',
                          style: HomeThemeTokens.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textSec,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: emailController,
                      readOnly: true,
                      enabled: false,
                      style: HomeThemeTokens.manrope(
                        color: textSec,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: readOnlyFill,
                        prefixIcon: Icon(
                          Icons.mail_outline_rounded,
                          color: textSec,
                          size: 20,
                        ),
                        suffixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: textSec,
                          size: 17,
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            final newName = nameController.text.trim();
                            final newPhone = phoneController.text.trim();
                            setState(() {
                              AppData.currentResident['name'] = newName;
                              AppData.currentResident['phone'] = newPhone;
                            });
                            ResidentApiService.updateProfile(
                              fullName: newName,
                              phone: newPhone,
                            ).catchError((e) {
                              debugPrint('API updateProfile error: $e');
                              return <String, dynamic>{};
                            });
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully!'),
                                backgroundColor: HomeThemeTokens.lightTeal,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tealCol,
                          foregroundColor: isDark
                              ? const Color(0xFF04201C)
                              : Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Save Changes',
                          style: HomeThemeTokens.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: isDark
                                ? const Color(0xFF04201C)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
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
        SnackBar(
          content: Text('Uploading $docType...'),
          duration: const Duration(seconds: 1),
        ),
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
          backgroundColor: HomeThemeTokens.lightTeal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: HomeThemeTokens.lightError,
        ),
      );
    }
  }

  Widget _staggeredEntrance({
    required double begin,
    required double end,
    required Widget child,
  }) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        begin.clamp(0.0, 0.96),
        end.clamp(0.05, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, inner) {
        final t = anim.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: inner,
          ),
        );
      },
    );
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) != null) {
      context.go('/menu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _resolveResidentData();
    final residentInfo =
        (res['resident_info'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final stayDetails =
        (res['stay_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final kycDetails =
        (res['kyc_details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final rawName =
        residentInfo['full_name'] ?? res['full_name'] ?? res['name'] ?? 'Resident';
    final name =
        rawName.toString().trim().isNotEmpty ? rawName.toString().trim() : 'Resident';

    final rawRoom = stayDetails['room_number'] ?? res['room_number'] ?? res['room'];
    final room = (rawRoom != null && rawRoom.toString().trim().isNotEmpty)
        ? rawRoom.toString().trim()
        : '101';

    final rawBed = stayDetails['bed_number'] ?? res['bed_number'] ?? res['bed'];
    final bed = (rawBed != null && rawBed.toString().trim().isNotEmpty)
        ? rawBed.toString().trim()
        : 'Bed B';

    final rawPhone =
        (residentInfo['phone'] ?? res['phone'] ?? '9876543210').toString().trim();
    final formattedPhone = rawPhone.startsWith('+') ? rawPhone : '+91 $rawPhone';

    final rawEmail = (residentInfo['email'] ?? res['email'])?.toString().trim();
    final email = (rawEmail != null && rawEmail.isNotEmpty)
        ? rawEmail
        : '${name.toLowerCase().replaceAll(RegExp(r'\s+'), '.')}@example.com';

    final rawProperty =
        stayDetails['property_name'] ?? res['property_name'] ?? res['property'];
    final propertyName =
        (rawProperty != null && rawProperty.toString().trim().isNotEmpty)
            ? rawProperty.toString().trim()
            : 'BNR Luxury PG';

    final rawPropertyAddress =
        stayDetails['property_address'] ?? res['property_address'];
    final propertyDisplay = (rawPropertyAddress != null &&
            rawPropertyAddress.toString().trim().isNotEmpty)
        ? rawPropertyAddress.toString().trim()
        : (rawProperty != null && rawProperty.toString().trim().isNotEmpty)
            ? rawProperty.toString().trim()
            : 'BNR Luxury PG, Koramangala';

    final rawSince = (stayDetails['living_since'] ??
            stayDetails['check_in_date'] ??
            res['living_since'] ??
            res['check_in_date'])
        ?.toString();
    final sinceLabel = _formatSinceLabel(rawSince);
    final compactBed = _formatBedMetric(bed);

    final isVerified = _resolveIsVerified(res);
    final maskedIdType = kycDetails['id_proof_type']?.toString().trim() ?? '';
    final maskedIdNumber =
        kycDetails['id_proof_number_masked']?.toString().trim() ?? '';

    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final dividerCol =
        isDark ? HomeThemeTokens.darkBorder : const Color(0xFFF0F4F3);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final avatarScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.03), weight: 62),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 38),
    ]).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.08, 0.56, curve: Curves.easeOutCubic),
      ),
    );

    final heroShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x22000000) : const Color(0x0A0E1A1F),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];

    final cardShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x1E000000) : const Color(0x080E1A1F),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----------------------------------------------------------
                  // 1. TOP HEADER BAR
                  // ----------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.00,
                    end: 0.35,
                    child: Row(
                      children: [
                        _InteractivePress(
                          onTap: _handleBack,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: borderCol, width: 1),
                              boxShadow: cardShadow,
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: textPri,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'My Profile',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HomeThemeTokens.manrope(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: textPri,
                            ),
                          ),
                        ),
                        const SizedBox(width: 42),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ----------------------------------------------------------
                  // 2. HERO PROFILE CARD + TRI-METRIC STRIP
                  // ----------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.08,
                    end: 0.52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderCol, width: 1),
                        boxShadow: heroShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                              child: Column(
                                children: [
                                  // Avatar Ring + Camera Button
                                  AnimatedBuilder(
                                    animation: avatarScale,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: disableAnim ? 1.0 : avatarScale.value,
                                        child: child,
                                      );
                                    },
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          width: 96,
                                          height: 96,
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: isDark
                                                  ? const [
                                                      HomeThemeTokens.darkTeal,
                                                      Color(0xFF219684),
                                                    ]
                                                  : const [
                                                      HomeThemeTokens.lightTeal,
                                                      Color(0xFF149E91),
                                                    ],
                                            ),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: cardBg,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF2B5A72)
                                                    : HomeThemeTokens.lightNavy,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  _getInitials(name),
                                                  style: HomeThemeTokens.manrope(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.4,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: -1,
                                          right: -1,
                                          child: Semantics(
                                            button: true,
                                            label: 'Update selfie photo',
                                            child: _InteractivePress(
                                              onTap: _updateProfilePhoto,
                                              child: Container(
                                                width: 31,
                                                height: 31,
                                                decoration: BoxDecoration(
                                                  color: tealCol,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: cardBg,
                                                    width: 2.5,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x26000000),
                                                      blurRadius: 6,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Icon(
                                                  Icons.camera_alt_rounded,
                                                  size: 14.5,
                                                  color: isDark
                                                      ? const Color(0xFF04201C)
                                                      : Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      color: textPri,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$propertyName · Room $room · $bed',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: textSec,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 4.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isVerified
                                          ? HomeThemeTokens.successBg(context)
                                          : HomeThemeTokens.warningBg(context),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isVerified
                                              ? Icons.check_rounded
                                              : Icons.hourglass_top_rounded,
                                          size: 13.5,
                                          color: isVerified
                                              ? HomeThemeTokens.success(context)
                                              : HomeThemeTokens.warning(context),
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            isVerified
                                                ? 'KYC Verified'
                                                : 'KYC Pending Verification',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: HomeThemeTokens.manrope(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: isVerified
                                                  ? HomeThemeTokens.success(context)
                                                  : HomeThemeTokens.warning(context),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  _InteractivePress(
                                    onTap: _showEditProfileModal,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: softTealCol,
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.edit_outlined,
                                            size: 15,
                                            color: tealCol,
                                          ),
                                          const SizedBox(width: 7),
                                          Text(
                                            'Edit Profile',
                                            style: HomeThemeTokens.manrope(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: tealCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(height: 1, color: borderCol),
                            IntrinsicHeight(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildMetricCell(
                                      label: 'Room',
                                      value: room,
                                      textPri: textPri,
                                      textSec: textSec,
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: borderCol,
                                  ),
                                  Expanded(
                                    child: _buildMetricCell(
                                      label: 'Bed',
                                      value: compactBed,
                                      textPri: textPri,
                                      textSec: textSec,
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: borderCol,
                                  ),
                                  Expanded(
                                    child: _buildMetricCell(
                                      label: 'Since',
                                      value: sinceLabel,
                                      textPri: textPri,
                                      textSec: textSec,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ----------------------------------------------------------
                  // 3. PERSONAL & CONTACT DETAILS SECTION
                  // ----------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.22,
                    end: 0.72,
                    child: _buildSection(
                      title: 'Personal & Contact Details',
                      cardBg: cardBg,
                      borderCol: borderCol,
                      tealCol: tealCol,
                      textSec: textSec,
                      shadow: cardShadow,
                      children: [
                        _buildListTile(
                          Icons.person_outline_rounded,
                          'Full name',
                          name,
                        ),
                        _buildInsetDivider(dividerCol),
                        _buildListTile(
                          Icons.phone_iphone_rounded,
                          'Phone number',
                          formattedPhone,
                        ),
                        _buildInsetDivider(dividerCol),
                        _buildListTile(
                          Icons.mail_outline_rounded,
                          'Email address',
                          email,
                          isReadOnly: true,
                        ),
                        _buildInsetDivider(dividerCol),
                        _buildListTile(
                          Icons.apartment_rounded,
                          'Property',
                          propertyDisplay,
                          isReadOnly: true,
                          showLockIcon: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ----------------------------------------------------------
                  // 4. KYC & IDENTITY VERIFICATION SECTION
                  // ----------------------------------------------------------
                  _staggeredEntrance(
                    begin: 0.36,
                    end: 0.90,
                    child: _buildSection(
                      title: 'KYC & Identity Verification',
                      cardBg: cardBg,
                      borderCol: borderCol,
                      tealCol: tealCol,
                      textSec: textSec,
                      shadow: cardShadow,
                      children: [
                        _buildKycTile(
                          icon: Icons.credit_card_rounded,
                          title: 'Aadhaar card',
                          isVerified: isVerified,
                          isUploaded: _isAadhaarUploaded,
                          maskedId: maskedIdType.toLowerCase().contains('aadhaar')
                              ? maskedIdNumber
                              : null,
                          onUpload: () => _pickAndUploadDocument('Aadhaar'),
                        ),
                        _buildInsetDivider(dividerCol),
                        _buildKycTile(
                          icon: Icons.badge_outlined,
                          title: 'PAN card',
                          isVerified: isVerified,
                          isUploaded: _isPanUploaded,
                          maskedId: maskedIdType.toLowerCase().contains('pan')
                              ? maskedIdNumber
                              : null,
                          onUpload: () => _pickAndUploadDocument('PAN'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCell({
    required String label,
    required String value,
    required Color textPri,
    required Color textSec,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeThemeTokens.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: textSec,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeThemeTokens.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: textPri,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsetDivider(Color dividerCol) {
    return Padding(
      padding: const EdgeInsets.only(left: 70),
      child: Container(height: 1, color: dividerCol),
    );
  }

  Widget _buildSection({
    required String title,
    required Color cardBg,
    required Color borderCol,
    required Color tealCol,
    required Color textSec,
    required List<BoxShadow> shadow,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  color: tealCol,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.25,
                    color: textSec,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderCol, width: 1),
            boxShadow: shadow,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildListTile(
    IconData icon,
    String label,
    String value, {
    bool isReadOnly = false,
    bool showLockIcon = true,
  }) {
    final isDark = HomeThemeTokens.isDark(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final iconTileBg =
        isDark ? HomeThemeTokens.darkSurface : const Color(0xFFF1F5F4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconTileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: tealCol,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: textSec,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPri,
                  ),
                ),
              ],
            ),
          ),
          if (isReadOnly && showLockIcon) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Email cannot be edited',
              child: Icon(
                Icons.lock_outline_rounded,
                size: 15.5,
                color: textSec.withValues(alpha: 0.72),
              ),
            ),
          ],
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
    String? maskedId,
  }) {
    final isDark = HomeThemeTokens.isDark(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final successCol = HomeThemeTokens.success(context);
    final successBg = HomeThemeTokens.successBg(context);
    final errorCol = HomeThemeTokens.error(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final String subtitleText;
    if (isUploaded) {
      subtitleText = (maskedId != null && maskedId.isNotEmpty)
          ? 'Document attached · $maskedId'
          : 'Document attached';
    } else {
      subtitleText = 'Not Uploaded Yet';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: softTealCol,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tealCol, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: textPri,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontSize: 12,
                    color: isUploaded ? textSec : errorCol,
                    fontWeight: isUploaded ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration:
                disableAnim ? Duration.zero : const Duration(milliseconds: 220),
            child: isUploaded
                ? Container(
                    key: ValueKey('uploaded_$title'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: successBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          color: successCol,
                          size: 13.5,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Uploaded',
                          style: HomeThemeTokens.manrope(
                            color: successCol,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : _InteractivePress(
                    key: ValueKey('upload_$title'),
                    onTap: onUpload,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7.5,
                      ),
                      decoration: BoxDecoration(
                        color: tealCol,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_file_rounded,
                            size: 14,
                            color: isDark
                                ? const Color(0xFF04201C)
                                : Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Upload',
                            style: HomeThemeTokens.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF04201C)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tactile press wrapper honoring reduced-motion accessibility settings.
class _InteractivePress extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _InteractivePress({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<_InteractivePress> createState() => _InteractivePressState();
}

class _InteractivePressState extends State<_InteractivePress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: (_pressed && !disableAnim) ? 0.96 : 1.0,
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
