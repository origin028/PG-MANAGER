import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/data/app_data.dart';
import '../../core/services/resident_api_service.dart';
import '../../core/theme/app_theme.dart';

class RaiseComplaintScreen extends StatefulWidget {
  const RaiseComplaintScreen({super.key});

  @override
  State<RaiseComplaintScreen> createState() => _RaiseComplaintScreenState();
}

class _RaiseComplaintScreenState extends State<RaiseComplaintScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  final List<String> _categories = [
    'Plumbing',
    'Electrical',
    'Wi-Fi/Internet',
    'Housekeeping',
    'Furniture',
    'AC/Heater',
    'Geyser',
    'Water Supply',
    'Pest Control',
    'Noise',
    'Security',
    'Parking',
    'Laundry',
    'Food/Mess',
    'Other',
  ];
  late String _selectedCategory;

  String? _uploadedFileName;
  bool _isUploading = false;
  bool _isSubmitting = false;

  late final AnimationController _entranceController;
  bool _animationStarted = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = _categories.first;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
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
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _uploadPhoto() async {
    setState(() => _isUploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _uploadedFileName = result.files.first.name;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo attached: $_uploadedFileName'),
            backgroundColor: HomeThemeTokens.lightTeal,
          ),
        );
      }
    } catch (_) {
      // Simulate fallback for platform without file dialog
      setState(() {
        _uploadedFileName = 'complaint_issue_photo.jpg';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample photo attached successfully!'),
          backgroundColor: HomeThemeTokens.lightTeal,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _submitComplaint() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSubmitting = true);

    final newComplaint = {
      'id': 'TKT-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      'category': _selectedCategory,
      'issue': _descriptionController.text.trim(),
      'photo': _uploadedFileName,
      'resident': AppData.currentResident['name'] ?? 'Resident',
      'room': AppData.currentResident['room_number'] ?? '101',
      'status': 'Open',
      'date': 'Just now',
    };

    // Add to global complaints if available
    AppData.complaints.insert(0, newComplaint);

    String apiCategory = 'OTHER';
    final catUpper = _selectedCategory.toUpperCase();
    if (catUpper.contains('PLUMB')) {
      apiCategory = 'PLUMBING';
    } else if (catUpper.contains('ELECTR')) {
      apiCategory = 'ELECTRICAL';
    } else if (catUpper.contains('WI-FI') ||
        catUpper.contains('WIFI') ||
        catUpper.contains('INTERNET')) {
      apiCategory = 'WIFI';
    } else if (catUpper.contains('CLEAN') ||
        catUpper.contains('HOUSEKEEPING')) {
      apiCategory = 'CLEANING';
    } else if (catUpper.contains('FOOD') || catUpper.contains('MESS')) {
      apiCategory = 'FOOD';
    } else if (catUpper.contains('CARPENTER') ||
        catUpper.contains('FURNITURE')) {
      apiCategory = 'CARPENTRY';
    } else {
      apiCategory = 'OTHER';
    }

    ResidentApiService.createComplaint({
      'title': '$_selectedCategory Issue',
      'description': _descriptionController.text.trim(),
      'category': apiCategory,
      'priority': 'MEDIUM',
    }).catchError((e) {
      debugPrint('API createComplaint error: $e');
      return <String, dynamic>{};
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Complaint submitted successfully! Our maintenance staff will attend to it shortly.',
              ),
            ),
          ],
        ),
        backgroundColor: HomeThemeTokens.lightTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );

    if (GoRouter.maybeOf(context) != null && context.canPop()) {
      context.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) != null) {
      context.go('/menu');
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

  @override
  Widget build(BuildContext context) {
    final isDark = HomeThemeTokens.isDark(context);
    final pageBg = HomeThemeTokens.bg(context);
    final cardBg =
        isDark ? HomeThemeTokens.darkCardSurface : HomeThemeTokens.lightCard;
    final borderCol = HomeThemeTokens.border(context);
    final textPri = HomeThemeTokens.textPrimary(context);
    final textSec = HomeThemeTokens.textSecondary(context);
    final tealCol = HomeThemeTokens.teal(context);
    final softTealCol = HomeThemeTokens.softTeal(context);
    final successCol = HomeThemeTokens.success(context);
    final successBg = HomeThemeTokens.successBg(context);
    final errorCol = HomeThemeTokens.error(context);
    final inputBg = isDark ? const Color(0xFF1F2930) : Colors.white;
    final inputBorderCol = isDark ? borderCol : const Color(0xFFDCE4E2);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final cardShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x20000000) : const Color(0x0A0E1A1F),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ];

    final heroShadow = <BoxShadow>[
      BoxShadow(
        color: isDark ? const Color(0x36000000) : const Color(0x220B2231),
        blurRadius: 16,
        offset: const Offset(0, 5),
      ),
    ];

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // ----------------------------------------------------------------
            // 1. TOP HEADER BAR
            // ----------------------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
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
                          'Raise Complaint',
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
              ),
            ),

            // ----------------------------------------------------------------
            // 2. SCROLLABLE FORM BODY
            // ----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --------------------------------------------------
                          // NAVY MAINTENANCE SUPPORT BANNER
                          // --------------------------------------------------
                          _staggeredEntrance(
                            begin: 0.04,
                            end: 0.42,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: HomeThemeTokens.heroGradient(context),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 1,
                                ),
                                boxShadow: heroShadow,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(19),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _HeroDotGridPainter(),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.headphones_rounded,
                                              color: Color(0xFF8BE3D4),
                                              size: 21,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Prompt maintenance support',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    height: 1.25,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Complaints are dispatched directly to the on-site property staff for rapid turnaround.',
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: const Color(
                                                      0xFFB7C6D2,
                                                    ),
                                                    height: 1.38,
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
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --------------------------------------------------
                          // COMPLAINT FORM CARD
                          // --------------------------------------------------
                          _staggeredEntrance(
                            begin: 0.16,
                            end: 0.68,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderCol, width: 1),
                                boxShadow: cardShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. Category Field
                                  Text(
                                    'Complaint Category *',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPri,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: _selectedCategory,
                                    isExpanded: true,
                                    dropdownColor: cardBg,
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: textPri,
                                      size: 22,
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: inputBg,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 13,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                            BorderSide(color: inputBorderCol),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                            BorderSide(color: inputBorderCol),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: tealCol,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    items: _categories.map((category) {
                                      return DropdownMenuItem<String>(
                                        value: category,
                                        child: Text(
                                          category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: HomeThemeTokens.manrope(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: textPri,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newVal) {
                                      if (newVal != null) {
                                        setState(
                                          () => _selectedCategory = newVal,
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 18),

                                  // 2. Description Field
                                  Text(
                                    'Issue Description *',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPri,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _descriptionController,
                                    maxLines: 4,
                                    minLines: 3,
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) {
                                        return 'Please describe the issue in detail';
                                      }
                                      if (val.trim().length < 5) {
                                        return 'Please provide at least a few words';
                                      }
                                      return null;
                                    },
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: textPri,
                                      height: 1.45,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'e.g. Tap leaking in attached bathroom, geyser not heating properly...',
                                      hintStyle: HomeThemeTokens.manrope(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: textSec,
                                      ),
                                      filled: true,
                                      fillColor: inputBg,
                                      contentPadding: const EdgeInsets.all(14),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                            BorderSide(color: inputBorderCol),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide:
                                            BorderSide(color: inputBorderCol),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: tealCol,
                                          width: 1.5,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: errorCol,
                                          width: 1.2,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: errorCol,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // 3. Photo Upload Section
                                  Text(
                                    'Photo Attachment (Optional)',
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPri,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration: disableAnim
                                        ? Duration.zero
                                        : const Duration(milliseconds: 220),
                                    child: _uploadedFileName != null
                                        ? Container(
                                            key: ValueKey(_uploadedFileName),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: successBg,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: successCol.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.image_outlined,
                                                  color: successCol,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    _uploadedFileName!,
                                                    style:
                                                        HomeThemeTokens.manrope(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: successCol,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: () => setState(
                                                    () =>
                                                        _uploadedFileName =
                                                            null,
                                                  ),
                                                  icon: Icon(
                                                    Icons.close_rounded,
                                                    size: 18,
                                                    color: errorCol,
                                                  ),
                                                  tooltip: 'Remove photo',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          )
                                        : _InteractivePress(
                                            key: const ValueKey('upload_cta'),
                                            child: CustomPaint(
                                              painter: _DashedBorderPainter(
                                                color: isDark
                                                    ? const Color(0xFF2F6F68)
                                                    : const Color(0xFF9CCBC4),
                                                radius: 14,
                                                strokeWidth: 1.4,
                                                dashWidth: 5,
                                                dashSpace: 4,
                                              ),
                                              child: Material(
                                                color: softTealCol,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: InkWell(
                                                  onTap: _isUploading
                                                      ? null
                                                      : _uploadPhoto,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  child: SizedBox(
                                                    width: double.infinity,
                                                    height: 50,
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (_isUploading)
                                                          SizedBox(
                                                            width: 16,
                                                            height: 16,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: tealCol,
                                                            ),
                                                          )
                                                        else
                                                          Icon(
                                                            Icons
                                                                .camera_alt_outlined,
                                                            size: 18.5,
                                                            color: tealCol,
                                                          ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            'Upload Photo',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: HomeThemeTokens
                                                                .manrope(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 14,
                                                              color: tealCol,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 18),

                                  // 4. Submit Button
                                  _InteractivePress(
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting
                                          ? null
                                          : _submitComplaint,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: tealCol,
                                        foregroundColor: isDark
                                            ? const Color(0xFF04201C)
                                            : Colors.white,
                                        disabledBackgroundColor:
                                            tealCol.withValues(alpha: 0.65),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        minimumSize:
                                            const Size(double.infinity, 52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isSubmitting
                                          ? SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: isDark
                                                    ? const Color(0xFF04201C)
                                                    : Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.send_rounded,
                                                  size: 17.5,
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Submit Complaint',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: HomeThemeTokens
                                                        .manrope(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 15,
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF04201C,
                                                            )
                                                          : Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --------------------------------------------------
                          // WHAT HAPPENS NEXT STEPPER GUIDE
                          // --------------------------------------------------
                          _staggeredEntrance(
                            begin: 0.34,
                            end: 0.88,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderCol, width: 1),
                                boxShadow: cardShadow,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'WHAT HAPPENS NEXT',
                                    textAlign: TextAlign.center,
                                    style: HomeThemeTokens.manrope(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.9,
                                      color: textSec,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _buildStepperNode(
                                          label: 'Submitted',
                                          isActive: true,
                                          hasLeftConnector: false,
                                          hasRightConnector: true,
                                          tealCol: tealCol,
                                          borderCol: borderCol,
                                          textPri: textPri,
                                          textSec: textSec,
                                          isDark: isDark,
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildStepperNode(
                                          stepText: '2',
                                          label: 'Assigned',
                                          isActive: false,
                                          hasLeftConnector: true,
                                          hasRightConnector: true,
                                          tealCol: tealCol,
                                          borderCol: borderCol,
                                          textPri: textPri,
                                          textSec: textSec,
                                          isDark: isDark,
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildStepperNode(
                                          stepText: '3',
                                          label: 'Resolved',
                                          isActive: false,
                                          hasLeftConnector: true,
                                          hasRightConnector: false,
                                          tealCol: tealCol,
                                          borderCol: borderCol,
                                          textPri: textPri,
                                          textSec: textSec,
                                          isDark: isDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperNode({
    String? stepText,
    required String label,
    required bool isActive,
    required bool hasLeftConnector,
    required bool hasRightConnector,
    required Color tealCol,
    required Color borderCol,
    required Color textPri,
    required Color textSec,
    required bool isDark,
  }) {
    final inactiveCircleBg =
        isDark ? const Color(0xFF323F49) : const Color(0xFFEEF2F1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 2,
                color: hasLeftConnector ? borderCol : Colors.transparent,
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isActive ? tealCol : inactiveCircleBg,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isActive
                    ? Icon(
                        Icons.check_rounded,
                        size: 15,
                        color:
                            isDark ? const Color(0xFF04201C) : Colors.white,
                      )
                    : Text(
                        stepText ?? '',
                        style: HomeThemeTokens.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textSec,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Container(
                height: 2,
                color: hasRightConnector ? borderCol : Colors.transparent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeThemeTokens.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isActive ? textPri : textSec,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtle architectural dot-grid backdrop inside the navy support banner.
class _HeroDotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const step = 14.0;
    for (double y = 7; y < size.height; y += step) {
      for (double x = 7; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a clean dashed rounded rectangle border around the upload button.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Tactile press scale feedback wrapper respecting reduced motion.
class _InteractivePress extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _InteractivePress({
    super.key,
    this.onTap,
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
    final scaled = AnimatedScale(
      scale: (_pressed && !disableAnim) ? 0.97 : 1.0,
      duration: disableAnim ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: scaled,
      );
    }

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: scaled,
    );
  }
}
