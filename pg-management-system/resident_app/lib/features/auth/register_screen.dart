import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion_wrappers.dart';
import 'otp_screen.dart';

class _RegisterPalette {
  final bool isDark;
  final Color bg;
  final Color card;
  final Color ink;
  final Color mute;
  final Color line;
  final Color field;
  final Color teal;
  final Color softTeal;
  final Color error;
  final Color softError;
  final Color success;
  final Color softSuccess;
  final Color warning;
  final Color softWarning;
  final List<Color> progressColors;

  const _RegisterPalette({
    required this.isDark,
    required this.bg,
    required this.card,
    required this.ink,
    required this.mute,
    required this.line,
    required this.field,
    required this.teal,
    required this.softTeal,
    required this.error,
    required this.softError,
    required this.success,
    required this.softSuccess,
    required this.warning,
    required this.softWarning,
    required this.progressColors,
  });

  factory _RegisterPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _RegisterPalette(
        isDark: true,
        bg: Color(0xFF0B1417),
        card: Color(0xFF121E24),
        ink: Color(0xFFE8F0EF),
        mute: Color(0xFF93A5A8),
        line: Color(0xFF1F2F35),
        field: Color(0xFF172830),
        teal: Color(0xFF14998B),
        softTeal: Color(0xFF12312F),
        error: Color(0xFFFF9A8F),
        softError: Color(0xFF3A1714),
        success: Color(0xFF5BD3A0),
        softSuccess: Color(0xFF0F2F24),
        warning: Color(0xFFF5B54A),
        softWarning: Color(0xFF3A2A0C),
        progressColors: [Color(0xFF3CC3AF), Color(0xFF14998B)],
      );
    }
    return const _RegisterPalette(
      isDark: false,
      bg: Color(0xFFF2F5F4),
      card: Color(0xFFFFFFFF),
      ink: Color(0xFF0E1A1F),
      mute: Color(0xFF56626B),
      line: Color(0xFFE6ECEA),
      field: Color(0xFFF2F6F5),
      teal: Color(0xFF0B6B63),
      softTeal: Color(0xFFE2F0EE),
      error: Color(0xFFB42318),
      softError: Color(0xFFFDECEA),
      success: Color(0xFF0F6B4A),
      softSuccess: Color(0xFFDDF3E8),
      warning: Color(0xFF92400E),
      softWarning: Color(0xFFFEF3C7),
      progressColors: [Color(0xFF14998B), Color(0xFF0B6B63)],
    );
  }
}

class RegisterScreen extends StatefulWidget {
  final VoidCallback? onSwitchToLogin;
  const RegisterScreen({super.key, this.onSwitchToLogin});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _occupationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _addressController = TextEditingController();
  final _pincodeController = TextEditingController();

  late final AnimationController _shakeController;
  DateTime? _selectedDob;

  // Property Selection
  List<Map<String, dynamic>> _properties = [];
  String? _selectedPropertyId;
  String? _selectedPropertyName;
  bool _isLoadingProperties = false;

  // Dropdowns & Verification Methods
  String _selectedGender = 'Male';
  String _selectedDocType = 'Aadhaar & PAN';

  // KYC PlatformFiles (Real Uploads)
  PlatformFile? _aadhaarFrontFile;
  PlatformFile? _aadhaarBackFile;
  PlatformFile? _panCardFile;
  PlatformFile? _passportFile;
  PlatformFile? _selfieFile;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    for (final ctrl in [
      _nameController,
      _dobController,
      _occupationController,
      _phoneController,
      _emailController,
      _emergencyController,
      _addressController,
      _pincodeController,
    ]) {
      ctrl.addListener(_onFormChanged);
    }
    _loadProperties();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shakeController.dispose();
    for (final ctrl in [
      _nameController,
      _dobController,
      _occupationController,
      _phoneController,
      _emailController,
      _emergencyController,
      _addressController,
      _pincodeController,
    ]) {
      ctrl.removeListener(_onFormChanged);
      ctrl.dispose();
    }
    super.dispose();
  }

  double _computeProgress() {
    final isPassport = _selectedDocType == 'Passport';
    int completed = 0;

    if (_selectedPropertyId != null && _selectedPropertyId!.isNotEmpty) {
      completed++;
    }
    if (_nameController.text.trim().length > 1) completed++;
    if (_dobController.text.trim().isNotEmpty) completed++;
    if (_selectedGender.isNotEmpty) completed++;
    if (_occupationController.text.trim().length > 1) completed++;

    final phoneDigits =
        _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length >= 10) completed++;

    final emailText = _emailController.text.trim();
    if (emailText.contains('@') && emailText.contains('.')) completed++;

    final emergencyDigits =
        _emergencyController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (emergencyDigits.length >= 10) completed++;

    if (_addressController.text.trim().isNotEmpty) completed++;

    final pinDigits =
        _pincodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (pinDigits.length == 6) completed++;

    if (isPassport) {
      if (_passportFile != null) completed++;
    } else {
      if (_aadhaarFrontFile != null) completed++;
      if (_aadhaarBackFile != null) completed++;
      if (_panCardFile != null) completed++;
    }
    if (_selfieFile != null) completed++;

    final total = isPassport ? 12 : 14;
    return (completed / total).clamp(0.0, 1.0);
  }

  void _handleBackNavigation() {
    if (widget.onSwitchToLogin != null) {
      widget.onSwitchToLogin!();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  Future<void> _loadProperties() async {
    setState(() => _isLoadingProperties = true);
    try {
      final props = await ResidentAuthService.getAvailableProperties();
      if (mounted && props.isNotEmpty) {
        setState(() {
          _properties = props;
          _selectedPropertyId = props.first['id']?.toString();
          _selectedPropertyName = props.first['name']?.toString();
          _isLoadingProperties = false;
        });
        return;
      }
    } catch (_) {
      // Fallback handles default properties
    }
    if (mounted) {
      setState(() => _isLoadingProperties = false);
    }
  }

  void _fillDemoData() {
    // 64-byte valid sample JPEG header
    final sampleJpegBytes = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0xFF, 0xD9
    ]);

    setState(() {
      _nameController.text = 'Aarav Sharma';
      _selectedDob = DateTime(1998, 6, 18);
      _dobController.text = '18/06/1998';
      _selectedGender = 'Male';
      _occupationController.text = 'Software Engineer';
      _phoneController.text = '9876500001';
      _emailController.text = 'aarav.sharma@originpg.com';
      _emergencyController.text = '9876599999';
      _addressController.text =
          'Flat 304, Green Glen Residency, Bellandur, Bengaluru, Karnataka';
      _pincodeController.text = '560103';

      if (_properties.isNotEmpty && _selectedPropertyId == null) {
        _selectedPropertyId = _properties.first['id']?.toString();
        _selectedPropertyName = _properties.first['name']?.toString();
      }

      if (_selectedDocType == 'Passport') {
        _passportFile = PlatformFile(
          name: 'passport_scan.jpg',
          size: sampleJpegBytes.length,
          bytes: sampleJpegBytes,
        );
        _aadhaarFrontFile = null;
        _aadhaarBackFile = null;
        _panCardFile = null;
      } else {
        _aadhaarFrontFile = PlatformFile(
          name: 'aadhaar_front.jpg',
          size: sampleJpegBytes.length,
          bytes: sampleJpegBytes,
        );
        _aadhaarBackFile = PlatformFile(
          name: 'aadhaar_back.jpg',
          size: sampleJpegBytes.length,
          bytes: sampleJpegBytes,
        );
        _panCardFile = PlatformFile(
          name: 'pan_card.jpg',
          size: sampleJpegBytes.length,
          bytes: sampleJpegBytes,
        );
        _passportFile = null;
      }

      _selfieFile = PlatformFile(
        name: 'resident_selfie.jpg',
        size: sampleJpegBytes.length,
        bytes: sampleJpegBytes,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Demo registration details and sample documents auto-filled!',
        ),
        backgroundColor: _RegisterPalette.of(context).teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final palette = _RegisterPalette.of(context);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(1999, 1, 1),
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: palette.isDark
                ? ColorScheme.dark(
                    primary: palette.teal,
                    onPrimary: Colors.white,
                    surface: palette.card,
                    onSurface: palette.ink,
                  )
                : ColorScheme.light(
                    primary: palette.teal,
                    onPrimary: Colors.white,
                    surface: palette.card,
                    onSurface: palette.ink,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Future<void> _pickFile({
    required String fileType,
    required Function(PlatformFile) onSelected,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null || file.bytes!.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected file is empty or could not be loaded.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (file.size > 5 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('File exceeds 5MB size limit. Please choose a smaller file.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          onSelected(file);
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileType selected: ${file.name}'),
            backgroundColor: _RegisterPalette.of(context).success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDobForBackend() {
    if (_selectedDob != null) {
      return "${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}";
    }
    final raw = _dobController.text.trim();
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return "${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}";
      }
    } else if (raw.contains('-')) {
      return raw;
    }
    return '2000-01-01';
  }

  Map<String, String> _parseAddressFields() {
    final raw = _addressController.text.trim();
    final parts = raw
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    String houseFlatNo = 'Flat 101';
    String street = 'Main Road';
    String landmark = '';
    String city = 'Bengaluru';
    String state = 'Karnataka';

    if (parts.length >= 5) {
      houseFlatNo = parts[0];
      street = parts[1];
      landmark = parts[2];
      city = parts[3];
      state = parts[4];
    } else if (parts.length == 4) {
      houseFlatNo = parts[0];
      street = parts[1];
      city = parts[2];
      state = parts[3];
    } else if (parts.length == 3) {
      houseFlatNo = parts[0];
      street = parts[1];
      city = parts[2];
    } else if (parts.length == 2) {
      houseFlatNo = parts[0];
      street = parts[1];
    } else if (parts.length == 1) {
      houseFlatNo = parts[0];
      street = parts[0];
    }

    return {
      'house_flat_no': houseFlatNo,
      'street': street,
      'landmark': landmark,
      'city': city,
      'state': state,
    };
  }

  void _triggerValidationShake() {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disableAnim) {
      _shakeController.forward(from: 0);
    }
  }

  Future<void> _handleSubmitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      _triggerValidationShake();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all required personal, contact and address fields.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a target PG property.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isPassport = _selectedDocType == 'Passport';

    if (!isPassport) {
      if (_aadhaarFrontFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload Aadhaar Card Front side.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_aadhaarBackFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload Aadhaar Card Back side.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_panCardFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload PAN Card document.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      if (_passportFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload your Passport document scan.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_selfieFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload your selfie photograph.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await _sendRegistrationOtpRequest();

      if (!mounted) return;

      final emailMasked =
          res['email_masked']?.toString() ?? _emailController.text.trim();
      final cooldownSeconds = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification code sent to $emailMasked! Check your inbox.',
          ),
          backgroundColor: _RegisterPalette.of(context).success,
          duration: const Duration(seconds: 4),
        ),
      );

      _showOtpDialog(
        phone: _phoneController.text.trim(),
        emailMasked: emailMasked,
        cooldownSeconds: cooldownSeconds,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration OTP request failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<Map<String, dynamic>> _sendRegistrationOtpRequest() {
    final isPassport = _selectedDocType == 'Passport';
    final files = <http.MultipartFile>[];
    if (!isPassport) {
      files.add(http.MultipartFile.fromBytes(
        'aadhaar_front_file',
        _aadhaarFrontFile!.bytes!,
        filename: _aadhaarFrontFile!.name,
      ));
      files.add(http.MultipartFile.fromBytes(
        'aadhaar_back_file',
        _aadhaarBackFile!.bytes!,
        filename: _aadhaarBackFile!.name,
      ));
      files.add(http.MultipartFile.fromBytes(
        'pan_card_file',
        _panCardFile!.bytes!,
        filename: _panCardFile!.name,
      ));
    } else {
      files.add(http.MultipartFile.fromBytes(
        'passport_file',
        _passportFile!.bytes!,
        filename: _passportFile!.name,
      ));
    }

    files.add(http.MultipartFile.fromBytes(
      'resident_selfie_file',
      _selfieFile!.bytes!,
      filename: _selfieFile!.name,
    ));

    final addr = _parseAddressFields();
    final dobFormatted = _formatDobForBackend();
    final verificationMethod = isPassport ? 'PASSPORT' : 'AADHAAR_PAN';

    return ResidentAuthService.requestRegistrationOtp(
      fullName: _nameController.text.trim(),
      dateOfBirth: dobFormatted,
      gender: _selectedGender,
      occupation: _occupationController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      emergencyContact: _emergencyController.text.trim(),
      houseFlatNo: addr['house_flat_no']!,
      street: addr['street']!,
      landmark: addr['landmark']!,
      city: addr['city']!,
      state: addr['state']!,
      pincode: _pincodeController.text.trim(),
      propertyId: _selectedPropertyId!,
      verificationMethod: verificationMethod,
      files: files,
    );
  }

  void _showOtpDialog({
    required String phone,
    required String emailMasked,
    int cooldownSeconds = 60,
  }) {
    Navigator.of(context).push(
      buildOtpPageRoute<void>(
        OtpVerificationScreen(
          destinationMasked: emailMasked,
          destinationChannel: 'registered email',
          initialCooldownSeconds: cooldownSeconds,
          onVerifyOtp: (otp) => ResidentAuthService.verifyRegistrationOtp(
            phone: phone,
            otp: otp,
          ),
          onResendOtp: _sendRegistrationOtpRequest,
          onVerified: (otpContext, result) {
            Navigator.of(otpContext).pop();
            if (!mounted) return;
            _showRegistrationSuccessDialog(
              residentName: result['full_name']?.toString() ??
                  _nameController.text.trim(),
              propertyName: result['property_name']?.toString() ??
                  _selectedPropertyName ??
                  'PG Property',
            );
          },
        ),
      ),
    );
  }

  void _showRegistrationSuccessDialog({
    required String residentName,
    required String propertyName,
  }) {
    final palette = _RegisterPalette.of(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.line),
        ),
        backgroundColor: palette.card,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: palette.softSuccess,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Lottie.asset(
                    'assets/animations/payment_success.json',
                    width: 60,
                    height: 60,
                    repeat: false,
                    animate: !disableAnim,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.check_circle_rounded,
                      color: palette.success,
                      size: 46,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Application submitted',
              textAlign: TextAlign.center,
              style: HomeThemeTokens.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.softWarning,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: palette.warning,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Pending approval',
                      style: HomeThemeTokens.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: palette.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Thanks $residentName, your registration for $propertyName is under KYC review. You will be notified once approved.',
              textAlign: TextAlign.center,
              style: HomeThemeTokens.manrope(
                fontSize: 13,
                color: palette.mute,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _handleBackNavigation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'Go to login',
                style: HomeThemeTokens.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _RegisterPalette.of(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool isPassportSelected = _selectedDocType == 'Passport';
    final double progress = _computeProgress();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A. Top App Bar
                _buildTopBar(palette),

                // B. Animated Progress Indicator
                _buildProgressBar(palette, progress, disableAnim),

                // Scrollable Body
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          final t = _shakeController.value;
                          final dx = t == 0
                              ? 0.0
                              : math.sin(t * math.pi * 4) * (1 - t) * 6.0;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // C. Self-onboarding Navy Banner
                            MotionEntrance(
                              slideOffset: const Offset(0, 0.02),
                              child: _buildSelfOnboardingBanner(palette),
                            ),

                            // D. Select PG Property
                            MotionEntrance(
                              delay: const Duration(milliseconds: 45),
                              slideOffset: const Offset(0, 0.025),
                              child: _buildSectionCard(
                                palette: palette,
                                title: 'Select PG property',
                                icon: Icons.apartment_rounded,
                                children: [
                                  _buildFieldLabel(
                                    palette,
                                    'Target PG property',
                                  ),
                                  _isLoadingProperties
                                      ? Padding(
                                          padding: const EdgeInsets.all(14.0),
                                          child: Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: palette.teal,
                                              ),
                                            ),
                                          ),
                                        )
                                      : _FocusGlowField(
                                          palette: palette,
                                          child: DropdownButtonFormField<String>(
                                            key: ValueKey(
                                              'prop_$_selectedPropertyId',
                                            ),
                                            initialValue: _selectedPropertyId,
                                            isExpanded: true,
                                            icon: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: palette.mute,
                                              size: 20,
                                            ),
                                            dropdownColor: palette.card,
                                            style: HomeThemeTokens.manrope(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: palette.ink,
                                            ),
                                            decoration: _buildInputDecoration(
                                              palette: palette,
                                              prefixIcon: Icons.home_outlined,
                                            ),
                                            items: _properties.map((p) {
                                              final id =
                                                  p['id']?.toString() ?? '';
                                              final name =
                                                  p['name']?.toString() ??
                                                      'PG Property';
                                              final city =
                                                  p['city']?.toString() ?? '';
                                              return DropdownMenuItem<String>(
                                                value: id,
                                                child: Text(
                                                  city.isNotEmpty
                                                      ? '$name ($city)'
                                                      : name,
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: palette.ink,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() {
                                                  _selectedPropertyId = val;
                                                  final matched =
                                                      _properties.firstWhere(
                                                    (p) =>
                                                        p['id']?.toString() ==
                                                        val,
                                                    orElse: () => {},
                                                  );
                                                  _selectedPropertyName =
                                                      matched['name']
                                                              ?.toString() ??
                                                          '';
                                                });
                                              }
                                            },
                                            validator: (val) =>
                                                (val == null || val.isEmpty)
                                                    ? 'Please select a PG property'
                                                    : null,
                                          ),
                                        ),
                                ],
                              ),
                            ),

                            // E. Personal Information
                            MotionEntrance(
                              delay: const Duration(milliseconds: 90),
                              slideOffset: const Offset(0, 0.025),
                              child: _buildSectionCard(
                                palette: palette,
                                title: '1. Personal information',
                                icon: Icons.person_outline_rounded,
                                children: [
                                  _buildInputField(
                                    palette: palette,
                                    controller: _nameController,
                                    label: 'Full name',
                                    hintText: 'e.g. Aarav Sharma',
                                    prefixIcon: Icons.badge_outlined,
                                    validator: (val) =>
                                        (val == null || val.trim().isEmpty)
                                            ? 'Enter your full name'
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: InkWell(
                                          onTap: _selectDateOfBirth,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: IgnorePointer(
                                            child: _buildInputField(
                                              palette: palette,
                                              controller: _dobController,
                                              label: 'Date of birth',
                                              hintText: 'DD/MM/YYYY',
                                              prefixIcon:
                                                  Icons.calendar_today_rounded,
                                              validator: (val) => (val == null ||
                                                      val.trim().isEmpty)
                                                  ? 'Select DOB'
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildFieldLabel(palette, 'Gender'),
                                            _FocusGlowField(
                                              palette: palette,
                                              child: DropdownButtonFormField<
                                                  String>(
                                                key: ValueKey(
                                                  'gender_$_selectedGender',
                                                ),
                                                initialValue: _selectedGender,
                                                isExpanded: true,
                                                icon: Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                  color: palette.mute,
                                                  size: 20,
                                                ),
                                                dropdownColor: palette.card,
                                                style: HomeThemeTokens.manrope(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: palette.ink,
                                                ),
                                                decoration:
                                                    _buildInputDecoration(
                                                  palette: palette,
                                                  horizontalPadding: 12,
                                                ),
                                                items: ['Male', 'Female', 'Other']
                                                    .map((g) {
                                                  return DropdownMenuItem(
                                                    value: g,
                                                    child: Text(
                                                      g,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: HomeThemeTokens
                                                          .manrope(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: palette.ink,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (val) => setState(
                                                  () => _selectedGender = val!,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInputField(
                                    palette: palette,
                                    controller: _occupationController,
                                    label: 'Occupation / designation',
                                    hintText: 'e.g. Software engineer',
                                    prefixIcon: Icons.work_outline_rounded,
                                    validator: (val) =>
                                        (val == null || val.trim().isEmpty)
                                            ? 'Enter occupation'
                                            : null,
                                  ),
                                ],
                              ),
                            ),

                            // F. Contact Information
                            MotionEntrance(
                              delay: const Duration(milliseconds: 135),
                              slideOffset: const Offset(0, 0.025),
                              child: _buildSectionCard(
                                palette: palette,
                                title: '2. Contact information',
                                icon: Icons.phone_outlined,
                                children: [
                                  _buildInputField(
                                    palette: palette,
                                    controller: _phoneController,
                                    label: 'Primary phone number',
                                    hintText: '10-digit mobile number',
                                    prefixIcon: Icons.smartphone_rounded,
                                    showCountryCodePrefix: true,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (val) {
                                      final digits = (val ?? '').replaceAll(
                                        RegExp(r'[^0-9]'),
                                        '',
                                      );
                                      if (digits.length < 10) {
                                        return 'Enter 10-digit mobile number';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInputField(
                                    palette: palette,
                                    controller: _emailController,
                                    label: 'Email address',
                                    hintText: 'name@example.com',
                                    prefixIcon: Icons.mail_outline_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (val) {
                                      if (val == null ||
                                          !val.contains('@') ||
                                          !val.contains('.')) {
                                        return 'Enter valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInputField(
                                    palette: palette,
                                    controller: _emergencyController,
                                    label: 'Emergency contact',
                                    hintText: '10-digit emergency number',
                                    prefixIcon:
                                        Icons.contact_emergency_outlined,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (val) {
                                      final digits = (val ?? '').replaceAll(
                                        RegExp(r'[^0-9]'),
                                        '',
                                      );
                                      if (digits.length < 10) {
                                        return 'Enter 10-digit contact';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // G. Permanent Address
                            MotionEntrance(
                              delay: const Duration(milliseconds: 180),
                              slideOffset: const Offset(0, 0.025),
                              child: _buildSectionCard(
                                palette: palette,
                                title: '3. Permanent address',
                                icon: Icons.location_on_outlined,
                                children: [
                                  _buildInputField(
                                    palette: palette,
                                    controller: _addressController,
                                    label: 'Address details',
                                    hintText:
                                        'House/Flat no, street, landmark, city, state',
                                    prefixIcon: Icons.home_outlined,
                                    maxLines: 3,
                                    validator: (val) =>
                                        (val == null || val.trim().isEmpty)
                                            ? 'Enter permanent address'
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInputField(
                                    palette: palette,
                                    controller: _pincodeController,
                                    label: 'Pincode',
                                    hintText: '6-digit pincode',
                                    prefixIcon: Icons.pin_drop_outlined,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (val) {
                                      final digits = (val ?? '').replaceAll(
                                        RegExp(r'[^0-9]'),
                                        '',
                                      );
                                      if (digits.length != 6) {
                                        return 'Enter valid 6-digit pincode';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // H. Identity & Verification (KYC)
                            MotionEntrance(
                              delay: const Duration(milliseconds: 225),
                              slideOffset: const Offset(0, 0.025),
                              child: _buildSectionCard(
                                palette: palette,
                                title: '4. Identity & verification (KYC)',
                                icon: Icons.verified_user_outlined,
                                children: [
                                  _buildFieldLabel(
                                    palette,
                                    'Verification method',
                                  ),
                                  _buildVerificationSegmentedControl(
                                    palette: palette,
                                    isPassportSelected: isPassportSelected,
                                    disableAnim: disableAnim,
                                  ),
                                  const SizedBox(height: 16),
                                  AnimatedSize(
                                    duration: disableAnim
                                        ? Duration.zero
                                        : const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: AnimatedSwitcher(
                                      duration: disableAnim
                                          ? Duration.zero
                                          : const Duration(milliseconds: 220),
                                      child: Column(
                                        key: ValueKey(isPassportSelected),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (isPassportSelected) ...[
                                            _buildUploadBox(
                                              palette: palette,
                                              disableAnim: disableAnim,
                                              title: 'Passport document',
                                              subtitle:
                                                  'Photo bio & address page (PDF, PNG or JPG)',
                                              icon: Icons.flight_takeoff_rounded,
                                              isUploaded: _passportFile != null,
                                              fileName: _passportFile != null
                                                  ? '${_passportFile!.name} (${(_passportFile!.size / 1024).toStringAsFixed(1)} KB)'
                                                  : '',
                                              onTap: () => _pickFile(
                                                fileType: 'Passport',
                                                onSelected: (f) =>
                                                    _passportFile = f,
                                              ),
                                              onRemove: () => setState(
                                                () => _passportFile = null,
                                              ),
                                            ),
                                          ] else ...[
                                            _buildUploadBox(
                                              palette: palette,
                                              disableAnim: disableAnim,
                                              title: 'Aadhaar card (front)',
                                              subtitle:
                                                  'Front side showing photo and Aadhaar number',
                                              icon: Icons.badge_outlined,
                                              isUploaded:
                                                  _aadhaarFrontFile != null,
                                              fileName: _aadhaarFrontFile !=
                                                      null
                                                  ? '${_aadhaarFrontFile!.name} (${(_aadhaarFrontFile!.size / 1024).toStringAsFixed(1)} KB)'
                                                  : '',
                                              onTap: () => _pickFile(
                                                fileType: 'Aadhaar Front',
                                                onSelected: (f) =>
                                                    _aadhaarFrontFile = f,
                                              ),
                                              onRemove: () => setState(
                                                () => _aadhaarFrontFile = null,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            _buildUploadBox(
                                              palette: palette,
                                              disableAnim: disableAnim,
                                              title: 'Aadhaar card (back)',
                                              subtitle:
                                                  'Back side showing address details',
                                              icon: Icons.badge_outlined,
                                              isUploaded:
                                                  _aadhaarBackFile != null,
                                              fileName: _aadhaarBackFile != null
                                                  ? '${_aadhaarBackFile!.name} (${(_aadhaarBackFile!.size / 1024).toStringAsFixed(1)} KB)'
                                                  : '',
                                              onTap: () => _pickFile(
                                                fileType: 'Aadhaar Back',
                                                onSelected: (f) =>
                                                    _aadhaarBackFile = f,
                                              ),
                                              onRemove: () => setState(
                                                () => _aadhaarBackFile = null,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            _buildUploadBox(
                                              palette: palette,
                                              disableAnim: disableAnim,
                                              title: 'PAN card',
                                              subtitle:
                                                  'Front view showing PAN number and photo',
                                              icon: Icons.credit_card_outlined,
                                              isUploaded: _panCardFile != null,
                                              fileName: _panCardFile != null
                                                  ? '${_panCardFile!.name} (${(_panCardFile!.size / 1024).toStringAsFixed(1)} KB)'
                                                  : '',
                                              onTap: () => _pickFile(
                                                fileType: 'PAN Card',
                                                onSelected: (f) =>
                                                    _panCardFile = f,
                                              ),
                                              onRemove: () => setState(
                                                () => _panCardFile = null,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          _buildUploadBox(
                                            palette: palette,
                                            disableAnim: disableAnim,
                                            title: 'Resident selfie',
                                            subtitle:
                                                'Clear front-facing portrait for your resident ID',
                                            icon: Icons.camera_alt_outlined,
                                            isUploaded: _selfieFile != null,
                                            fileName: _selfieFile != null
                                                ? '${_selfieFile!.name} (${(_selfieFile!.size / 1024).toStringAsFixed(1)} KB)'
                                                : '',
                                            onTap: () => _pickFile(
                                              fileType: 'Selfie Photo',
                                              onSelected: (f) =>
                                                  _selfieFile = f,
                                            ),
                                            onRemove: () => setState(
                                              () => _selfieFile = null,
                                            ),
                                          ),
                                        ],
                                      ),
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
                ),

                // 5. Sticky Bottom Submission Area
                _buildStickyBottomBar(palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(_RegisterPalette palette) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: palette.bg.withValues(alpha: 0.90),
          child: Row(
            children: [
              TactilePress(
                scaleDown: 0.92,
                child: Material(
                  color: palette.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: palette.line),
                  ),
                  child: InkWell(
                    onTap: _handleBackNavigation,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: palette.ink,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeThemeTokens.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: palette.ink,
                  ),
                ),
              ),
              TactilePress(
                scaleDown: 0.95,
                child: Material(
                  color: palette.softTeal,
                  borderRadius: BorderRadius.circular(99),
                  child: InkWell(
                    onTap: _fillDemoData,
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            color: palette.teal,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Demo',
                            style: HomeThemeTokens.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: palette.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(
    _RegisterPalette palette,
    double progress,
    bool disableAnim,
  ) {
    return Container(
      height: 5,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: palette.line,
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: progress),
        duration: disableAnim
            ? Duration.zero
            : const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: LinearGradient(
              colors: palette.progressColors,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelfOnboardingBanner(_RegisterPalette palette) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2231), Color(0xFF12394A)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -70,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0x4742C8B4),
                      Color(0x0042C8B4),
                    ],
                    stops: [0.0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Color(0xFF5EEAD4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Self-onboarding',
                        style: HomeThemeTokens.manrope(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add your details and KYC documents. Once approved, your room and rent key are allotted.',
                        style: HomeThemeTokens.manrope(
                          color: Colors.white.withValues(alpha: 0.76),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required _RegisterPalette palette,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
        boxShadow: palette.isDark
            ? const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A0E1A1F),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
                BoxShadow(
                  color: Color(0x180E1A1F),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.softTeal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: palette.teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: HomeThemeTokens.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFieldLabel(_RegisterPalette palette, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: HomeThemeTokens.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required _RegisterPalette palette,
    String? hintText,
    IconData? prefixIcon,
    bool showCountryCodePrefix = false,
    bool multiline = false,
    double horizontalPadding = 14,
  }) {
    Widget? resolvedPrefix;
    if (prefixIcon != null && showCountryCodePrefix) {
      resolvedPrefix = Padding(
        padding: EdgeInsets.only(left: horizontalPadding, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(prefixIcon, color: palette.mute, size: 20),
            const SizedBox(width: 10),
            Text(
              '+91',
              style: HomeThemeTokens.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: palette.ink,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 18, color: palette.line),
          ],
        ),
      );
    } else if (prefixIcon != null) {
      resolvedPrefix = Padding(
        padding: EdgeInsets.only(
          left: horizontalPadding,
          right: 10,
          top: multiline ? 2 : 0,
        ),
        child: Icon(prefixIcon, color: palette.mute, size: 20),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: HomeThemeTokens.manrope(
        color: palette.mute.withValues(alpha: 0.7),
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: resolvedPrefix,
      prefixIconConstraints: prefixIcon != null
          ? const BoxConstraints(minWidth: 40, minHeight: 24)
          : null,
      counterText: '',
      filled: true,
      fillColor: Colors.transparent,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 15,
      ),
      errorStyle: HomeThemeTokens.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: palette.error,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.field, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.teal, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.error, width: 1.5),
      ),
    );
  }

  Widget _buildInputField({
    required _RegisterPalette palette,
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    bool showCountryCodePrefix = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(palette, label),
        _FocusGlowField(
          palette: palette,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: HomeThemeTokens.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
            validator: validator,
            decoration: _buildInputDecoration(
              palette: palette,
              hintText: hintText,
              prefixIcon: prefixIcon,
              showCountryCodePrefix: showCountryCodePrefix,
              multiline: maxLines > 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationSegmentedControl({
    required _RegisterPalette palette,
    required bool isPassportSelected,
    required bool disableAnim,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final halfWidth = (constraints.maxWidth) / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: disableAnim
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: isPassportSelected
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: halfWidth,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x220E1A1F),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          setState(() => _selectedDocType = 'Aadhaar & PAN'),
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 16,
                              color: !isPassportSelected
                                  ? palette.teal
                                  : palette.mute,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Aadhaar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: !isPassportSelected
                                      ? palette.teal
                                      : palette.mute,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          setState(() => _selectedDocType = 'Passport'),
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.flight_takeoff_rounded,
                              size: 16,
                              color: isPassportSelected
                                  ? palette.teal
                                  : palette.mute,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Passport',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isPassportSelected
                                      ? palette.teal
                                      : palette.mute,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadBox({
    required _RegisterPalette palette,
    required bool disableAnim,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isUploaded,
    required String fileName,
    required VoidCallback onTap,
    required VoidCallback onRemove,
  }) {
    final animDuration =
        disableAnim ? Duration.zero : const Duration(milliseconds: 240);

    return TactilePress(
      scaleDown: 0.985,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          foregroundPainter: isUploaded
              ? null
              : _DashedRRectPainter(
                  color: palette.line,
                  radius: 16,
                  strokeWidth: 1.5,
                ),
          child: AnimatedContainer(
            duration: animDuration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUploaded ? palette.softTeal : palette.field,
              borderRadius: BorderRadius.circular(16),
              border: isUploaded
                  ? Border.all(color: palette.teal, width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey('${title}_$isUploaded'),
                  tween: Tween<double>(
                    begin: isUploaded ? 0.82 : 1.0,
                    end: 1.0,
                  ),
                  duration: disableAnim || !isUploaded
                      ? Duration.zero
                      : const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isUploaded ? palette.teal : palette.softTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isUploaded ? Icons.check_rounded : icon,
                      color: isUploaded ? Colors.white : palette.teal,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isUploaded ? fileName : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeThemeTokens.manrope(
                          fontSize: 12,
                          fontWeight:
                              isUploaded ? FontWeight.w600 : FontWeight.w500,
                          color: isUploaded ? palette.teal : palette.mute,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isUploaded) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: palette.mute,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_upload_outlined,
                        size: 15,
                        color: palette.teal,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isUploaded ? 'Change' : 'Upload',
                        style: HomeThemeTokens.manrope(
                          color: palette.teal,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
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
    );
  }

  Widget _buildStickyBottomBar(_RegisterPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.32],
          colors: [
            palette.bg.withValues(alpha: 0.0),
            palette.bg,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TactilePress(
            scaleDown: 0.98,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _isSubmitting
                    ? null
                    : [
                        BoxShadow(
                          color: palette.teal.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmitRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.teal,
                  disabledBackgroundColor: palette.teal.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: AnimatedSwitcher(
                  duration: (MediaQuery.maybeDisableAnimationsOf(context) ??
                          false)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: _isSubmitting
                      ? const SizedBox(
                          key: ValueKey('submitting'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_outline_rounded, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Register & verify OTP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Already registered? ',
                  style: HomeThemeTokens.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.mute,
                  ),
                ),
                GestureDetector(
                  onTap: _handleBackNavigation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      'Go to login',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: palette.teal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusGlowField extends StatefulWidget {
  final _RegisterPalette palette;
  final Widget child;

  const _FocusGlowField({
    required this.palette,
    required this.child,
  });

  @override
  State<_FocusGlowField> createState() => _FocusGlowFieldState();
}

class _FocusGlowFieldState extends State<_FocusGlowField> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Focus(
      onFocusChange: (focused) {
        if (mounted && _hasFocus != focused) {
          setState(() => _hasFocus = focused);
        }
      },
      child: AnimatedContainer(
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hasFocus ? widget.palette.card : widget.palette.field,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: widget.palette.teal.withValues(alpha: 0.14),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
