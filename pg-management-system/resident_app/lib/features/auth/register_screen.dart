import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_exception.dart';
import '../../core/services/resident_auth_service.dart';
import '../../core/theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback? onSwitchToLogin;
  const RegisterScreen({super.key, this.onSwitchToLogin});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
    _loadProperties();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _occupationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _emergencyController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
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
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
      0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
      0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0xFF,
      0xD9
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
      _addressController.text = 'Flat 304, Green Glen Residency, Bellandur, Bengaluru, Karnataka';
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
      const SnackBar(
        content: Text('Demo registration details and sample documents auto-filled!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(1999, 1, 1),
      firstDate: DateTime(1960),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              onSurface: AppTheme.textDark,
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
              content: Text('File exceeds 5MB size limit. Please choose a smaller file.'),
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
            backgroundColor: Colors.green,
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
    final parts = raw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

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

  Future<void> _handleSubmitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required personal, contact and address fields.'),
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

    // Build real files list
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

    setState(() => _isSubmitting = true);

    try {
      final res = await ResidentAuthService.requestRegistrationOtp(
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

      if (!mounted) return;

      final emailMasked = res['email_masked']?.toString() ?? _emailController.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification code sent to $emailMasked! Check your inbox.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      _showOtpDialog(
        phone: _phoneController.text.trim(),
        emailMasked: emailMasked,
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

  void _showOtpDialog({
    required String phone,
    required String emailMasked,
  }) {
    final otpController = TextEditingController();
    bool isVerifying = false;
    String? localError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Circular blue icon
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppTheme.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D4F46E5),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Verify Email OTP',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the 6-digit verification code sent to your registered email ($emailMasked)',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
              ),
              const SizedBox(height: 20),

              // OTP Input
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.softGrey,
                  hintText: '• • • • • •',
                  hintStyle: const TextStyle(letterSpacing: 4, color: AppTheme.textLight),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFEDF2F7)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                  ),
                ),
                maxLength: 6,
              ),

              if (localError != null) ...[
                const SizedBox(height: 10),
                Text(
                  localError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],

              const SizedBox(height: 24),

              // Verify OTP Button
              ElevatedButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        final otp = otpController.text.trim();
                        if (otp.length != 6) {
                          setDialogState(() => localError = 'Please enter a valid 6-digit OTP code.');
                          return;
                        }

                        setDialogState(() {
                          isVerifying = true;
                          localError = null;
                        });

                        try {
                          final result = await ResidentAuthService.verifyRegistrationOtp(
                            phone: phone,
                            otp: otp,
                          );

                          if (!dialogCtx.mounted) return;
                          Navigator.pop(dialogCtx);

                          if (!mounted) return;
                          _showRegistrationSuccessDialog(
                            residentName: result['full_name']?.toString() ?? _nameController.text.trim(),
                            propertyName: result['property_name']?.toString() ?? _selectedPropertyName ?? 'PG Property',
                          );
                        } on ApiException catch (e) {
                          setDialogState(() {
                            isVerifying = false;
                            localError = e.message;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isVerifying = false;
                            localError = 'Verification failed: $e';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: isVerifying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Verify OTP & Submit',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRegistrationSuccessDialog({
    required String residentName,
    required String propertyName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Registration Submitted Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Status: PENDING APPROVAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Your registration has been submitted and is awaiting administrator approval. You will be able to log in after your registration is approved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.45),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (widget.onSwitchToLogin != null) {
                  widget.onSwitchToLogin!();
                } else {
                  context.go('/login');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text(
                'Go to Login',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPassportSelected = _selectedDocType == 'Passport';

    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        leading: widget.onSwitchToLogin != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textDark),
                onPressed: widget.onSwitchToLogin,
              )
            : null,
        title: const Text(
          'Registration',
          style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: InkWell(
              onTap: _fillDemoData,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x144F46E5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on_rounded, color: AppTheme.primaryBlue, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Demo',
                      style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header card
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: AppTheme.blueGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x4D4F46E5),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0x4DFFFFFF)),
                            ),
                            child: const Icon(Icons.assignment_ind_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Self-Onboarding Portal',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Submit your details & KYC documents. Once approved, your room and rent key will be allotted.',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // SECTION 0: Target PG Property Selection
                    _buildSectionCard(
                      title: 'Select PG Property',
                      icon: Icons.apartment_rounded,
                      children: [
                        const Text(
                          'Target PG Property *',
                          style: TextStyle(color: AppTheme.textGrey, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        _isLoadingProperties
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : DropdownButtonFormField<String>(
                                initialValue: _selectedPropertyId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  filled: true,
                                  fillColor: AppTheme.softGrey,
                                  prefixIcon: const Icon(Icons.home_work_rounded, color: AppTheme.primaryBlue, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFFEDF2F7)),
                                  ),
                                ),
                                items: _properties.map((p) {
                                  final id = p['id']?.toString() ?? '';
                                  final name = p['name']?.toString() ?? 'PG Property';
                                  final city = p['city']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: id,
                                    child: Text(
                                      city.isNotEmpty ? '$name ($city)' : name,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedPropertyId = val;
                                      final matched = _properties.firstWhere(
                                        (p) => p['id']?.toString() == val,
                                        orElse: () => {},
                                      );
                                      _selectedPropertyName = matched['name']?.toString() ?? '';
                                    });
                                  }
                                },
                                validator: (val) => (val == null || val.isEmpty) ? 'Please select a PG property' : null,
                              ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SECTION 1: Personal Information
                    _buildSectionCard(
                      title: '1. Personal Information',
                      icon: Icons.person_outline_rounded,
                      children: [
                        _buildInputField(
                          controller: _nameController,
                          label: 'Full Name *',
                          hintText: 'e.g. Aarav Sharma',
                          prefixIcon: Icons.badge_outlined,
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter your full name' : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: InkWell(
                                onTap: _selectDateOfBirth,
                                child: IgnorePointer(
                                  child: _buildInputField(
                                    controller: _dobController,
                                    label: 'Date of Birth *',
                                    hintText: 'DD/MM/YYYY',
                                    prefixIcon: Icons.calendar_today_rounded,
                                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Select DOB' : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Gender *', style: TextStyle(color: AppTheme.textGrey, fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedGender,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      filled: true,
                                      fillColor: AppTheme.softGrey,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(color: Color(0xFFEDF2F7)),
                                      ),
                                    ),
                                    items: ['Male', 'Female', 'Other'].map((g) {
                                      return DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 14)));
                                    }).toList(),
                                    onChanged: (val) => setState(() => _selectedGender = val!),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: _occupationController,
                          label: 'Occupation / Designation *',
                          hintText: 'e.g. Software Engineer / Student',
                          prefixIcon: Icons.work_outline_rounded,
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter occupation' : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SECTION 2: Contact Information
                    _buildSectionCard(
                      title: '2. Contact Information',
                      icon: Icons.contact_phone_outlined,
                      children: [
                        _buildInputField(
                          controller: _phoneController,
                          label: 'Primary Phone Number *',
                          hintText: '10-digit mobile number',
                          prefixIcon: Icons.phone_android_rounded,
                          keyboardType: TextInputType.phone,
                          validator: (val) {
                            final digits = (val ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits.length < 10) return 'Enter 10-digit mobile number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: _emailController,
                          label: 'Email Address *',
                          hintText: 'e.g. name@example.com',
                          prefixIcon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || !val.contains('@') || !val.contains('.')) {
                              return 'Enter valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: _emergencyController,
                          label: 'Emergency Contact *',
                          hintText: '10-digit emergency contact',
                          prefixIcon: Icons.contact_emergency_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (val) {
                            final digits = (val ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits.length < 10) return 'Enter 10-digit contact';
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SECTION 3: Permanent Address
                    _buildSectionCard(
                      title: '3. Permanent Address',
                      icon: Icons.location_on_outlined,
                      children: [
                        _buildInputField(
                          controller: _addressController,
                          label: 'Address Details *',
                          hintText: 'House/Flat No, Street, Landmark, City, State',
                          prefixIcon: Icons.home_work_outlined,
                          maxLines: 2,
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter permanent address' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: _pincodeController,
                          label: 'Pincode *',
                          hintText: '6-digit pincode',
                          prefixIcon: Icons.pin_drop_outlined,
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            final digits = (val ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits.length != 6) return 'Enter valid 6-digit pincode';
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SECTION 4: KYC Document Upload
                    _buildSectionCard(
                      title: '4. Identity & Verification (KYC)',
                      icon: Icons.verified_user_outlined,
                      children: [
                        const Text(
                          'Choose Document Verification Method *',
                          style: TextStyle(color: AppTheme.textGrey, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),

                        // Document selector
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _selectedDocType = 'Aadhaar & PAN'),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: !isPassportSelected
                                        ? const Color(0x144F46E5)
                                        : AppTheme.softGrey,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: !isPassportSelected
                                          ? AppTheme.primaryBlue
                                          : const Color(0xFFE2E8F0),
                                      width: !isPassportSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.credit_card_rounded,
                                        size: 18,
                                        color: !isPassportSelected ? AppTheme.primaryBlue : AppTheme.textGrey,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Aadhaar + PAN',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: !isPassportSelected ? AppTheme.primaryBlue : AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _selectedDocType = 'Passport'),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: isPassportSelected
                                        ? const Color(0x144F46E5)
                                        : AppTheme.softGrey,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isPassportSelected
                                          ? AppTheme.primaryBlue
                                          : const Color(0xFFE2E8F0),
                                      width: isPassportSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.flight_takeoff_rounded,
                                        size: 18,
                                        color: isPassportSelected ? AppTheme.primaryBlue : AppTheme.textGrey,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Passport Only',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isPassportSelected ? AppTheme.primaryBlue : AppTheme.textDark,
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
                        const SizedBox(height: 16),

                        if (isPassportSelected) ...[
                          _buildUploadBox(
                            title: 'Upload Passport Document *',
                            subtitle: 'Front bio page & back address page (PDF, PNG or JPG)',
                            icon: Icons.flight_takeoff_rounded,
                            isUploaded: _passportFile != null,
                            fileName: _passportFile != null
                                ? '${_passportFile!.name} (${(_passportFile!.size / 1024).toStringAsFixed(1)} KB)'
                                : '',
                            onTap: () => _pickFile(
                              fileType: 'Passport',
                              onSelected: (f) => _passportFile = f,
                            ),
                            onRemove: () => setState(() => _passportFile = null),
                          ),
                        ] else ...[
                          _buildUploadBox(
                            title: '1. Upload Aadhaar Card (Front) *',
                            subtitle: 'Front side showing photo & Aadhaar number (PDF/JPG)',
                            icon: Icons.credit_card_rounded,
                            isUploaded: _aadhaarFrontFile != null,
                            fileName: _aadhaarFrontFile != null
                                ? '${_aadhaarFrontFile!.name} (${(_aadhaarFrontFile!.size / 1024).toStringAsFixed(1)} KB)'
                                : '',
                            onTap: () => _pickFile(
                              fileType: 'Aadhaar Front',
                              onSelected: (f) => _aadhaarFrontFile = f,
                            ),
                            onRemove: () => setState(() => _aadhaarFrontFile = null),
                          ),
                          const SizedBox(height: 12),
                          _buildUploadBox(
                            title: '2. Upload Aadhaar Card (Back) *',
                            subtitle: 'Back side showing address details (PDF/JPG)',
                            icon: Icons.credit_card_rounded,
                            isUploaded: _aadhaarBackFile != null,
                            fileName: _aadhaarBackFile != null
                                ? '${_aadhaarBackFile!.name} (${(_aadhaarBackFile!.size / 1024).toStringAsFixed(1)} KB)'
                                : '',
                            onTap: () => _pickFile(
                              fileType: 'Aadhaar Back',
                              onSelected: (f) => _aadhaarBackFile = f,
                            ),
                            onRemove: () => setState(() => _aadhaarBackFile = null),
                          ),
                          const SizedBox(height: 12),
                          _buildUploadBox(
                            title: '3. Upload PAN Card *',
                            subtitle: 'Front view showing PAN number & photograph',
                            icon: Icons.credit_card_outlined,
                            isUploaded: _panCardFile != null,
                            fileName: _panCardFile != null
                                ? '${_panCardFile!.name} (${(_panCardFile!.size / 1024).toStringAsFixed(1)} KB)'
                                : '',
                            onTap: () => _pickFile(
                              fileType: 'PAN Card',
                              onSelected: (f) => _panCardFile = f,
                            ),
                            onRemove: () => setState(() => _panCardFile = null),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildUploadBox(
                          title: 'Upload Resident Selfie Photo *',
                          subtitle: 'Clear front-facing portrait photo for resident ID (JPG/PNG)',
                          icon: Icons.camera_alt_outlined,
                          isUploaded: _selfieFile != null,
                          fileName: _selfieFile != null
                              ? '${_selfieFile!.name} (${(_selfieFile!.size / 1024).toStringAsFixed(1)} KB)'
                              : '',
                          onTap: () => _pickFile(
                            fileType: 'Selfie Photo',
                            onSelected: (f) => _selfieFile = f,
                          ),
                          onRemove: () => setState(() => _selfieFile = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Register & Verify OTP button
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmitRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.how_to_reg_rounded, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'Register & Verify OTP',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.onSwitchToLogin != null)
                      Center(
                        child: TextButton.icon(
                          onPressed: widget.onSwitchToLogin,
                          icon: const Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.primaryBlue),
                          label: const Text(
                            'Already registered? Go to Login',
                            style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDF2F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            prefixIcon: Icon(prefixIcon, color: AppTheme.textLight, size: 20),
            filled: true,
            fillColor: AppTheme.softGrey,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEDF2F7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadBox({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isUploaded,
    required String fileName,
    required VoidCallback onTap,
    required VoidCallback onRemove,
  }) {
    if (isUploaded) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D))),
                  const SizedBox(height: 2),
                  Text(fileName, style: const TextStyle(color: Color(0xFF166534), fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
              onPressed: onRemove,
              tooltip: 'Remove document',
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.softGrey,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x144F46E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_rounded, size: 14, color: AppTheme.primaryBlue),
                  SizedBox(width: 4),
                  Text('Upload', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
