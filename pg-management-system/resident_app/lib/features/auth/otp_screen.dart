import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion_wrappers.dart';

class _OtpPalette {
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

  const _OtpPalette({
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
  });

  factory _OtpPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _OtpPalette(
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
      );
    }
    return const _OtpPalette(
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
    );
  }
}

/// Smooth slide-and-fade route helper honoring reduced motion accessibility settings.
Route<T> buildOtpPageRoute<T>(Widget screen) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => screen,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class OtpVerificationScreen extends StatefulWidget {
  final String destinationMasked;
  final String destinationChannel;
  final int initialCooldownSeconds;
  final int otpLength;
  final Future<Map<String, dynamic>> Function(String otp) onVerifyOtp;
  final Future<Map<String, dynamic>> Function()? onResendOtp;
  final void Function(BuildContext otpContext, Map<String, dynamic> result)
      onVerified;

  const OtpVerificationScreen({
    super.key,
    required this.destinationMasked,
    this.destinationChannel = 'registered email',
    this.initialCooldownSeconds = 60,
    this.otpLength = 6,
    required this.onVerifyOtp,
    this.onResendOtp,
    required this.onVerified,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with TickerProviderStateMixin {
  late final List<TextEditingController> _cellControllers;
  late final List<FocusNode> _cellFocusNodes;
  late final AnimationController _pulseController;
  late final AnimationController _shakeController;

  Timer? _resendTimer;
  late int _secondsRemaining;
  bool _pulseStarted = false;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _isVerified = false;
  String? _errorMessage;
  bool _hasErrorState = false;

  @override
  void initState() {
    super.initState();
    _cellControllers = List.generate(
      widget.otpLength,
      (_) => TextEditingController(),
    );
    _cellFocusNodes = List.generate(
      widget.otpLength,
      (index) {
        final node = FocusNode();
        node.addListener(() {
          if (mounted) setState(() {});
        });
        return node;
      },
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _secondsRemaining = math.max(0, widget.initialCooldownSeconds);
    _startCountdownTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pulseStarted) {
      _pulseStarted = true;
      _triggerShieldPulse();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _pulseController.dispose();
    _shakeController.dispose();
    for (final c in _cellControllers) {
      c.dispose();
    }
    for (final f in _cellFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _triggerShieldPulse() {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) {
      _pulseController.value = 1.0;
    } else {
      _pulseController.forward(from: 0.0);
    }
  }

  void _triggerErrorShake() {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!disableAnim) {
      _shakeController.forward(from: 0.0);
    }
  }

  void _startCountdownTimer() {
    _resendTimer?.cancel();
    if (_secondsRemaining <= 0) return;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  String get _otpCode => _cellControllers.map((c) => c.text).join();

  void _handleCellChanged(int index, String rawValue) {
    final digits = rawValue.replaceAll(RegExp(r'[^0-9]'), '');

    if (_hasErrorState || _errorMessage != null) {
      setState(() {
        _hasErrorState = false;
        _errorMessage = null;
      });
    }

    if (digits.isEmpty) {
      _cellControllers[index].value = TextEditingValue.empty;
      setState(() {});
      return;
    }

    // Handle pasted or autofilled multi-digit strings cleanly across cells
    if (digits.length > 1) {
      final startIdx = digits.length >= widget.otpLength ? 0 : index;
      int cursorIdx = startIdx;
      for (int k = 0; k < digits.length && cursorIdx < widget.otpLength; k++) {
        _cellControllers[cursorIdx].value = TextEditingValue(
          text: digits[k],
          selection: const TextSelection.collapsed(offset: 1),
        );
        cursorIdx++;
      }
      if (cursorIdx < widget.otpLength) {
        _cellFocusNodes[cursorIdx].requestFocus();
      } else {
        _cellFocusNodes[widget.otpLength - 1].unfocus();
      }
      setState(() {});
      return;
    }

    // Single digit typed
    _cellControllers[index].value = TextEditingValue(
      text: digits,
      selection: const TextSelection.collapsed(offset: 1),
    );
    if (index + 1 < widget.otpLength) {
      _cellFocusNodes[index + 1].requestFocus();
    } else {
      _cellFocusNodes[index].unfocus();
    }
    setState(() {});
  }

  KeyEventResult _handleCellKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _cellControllers[index].text.isEmpty &&
        index > 0) {
      _cellControllers[index - 1].clear();
      _cellFocusNodes[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        index > 0) {
      _cellFocusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        index + 1 < widget.otpLength) {
      _cellFocusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handleVerify() async {
    final otp = _otpCode.trim();
    if (otp.length != widget.otpLength || _isVerifying || _isVerified) {
      if (otp.length != widget.otpLength) {
        setState(() {
          _hasErrorState = true;
          _errorMessage =
              'Please enter all ${widget.otpLength} digits of the verification code.';
        });
        _triggerErrorShake();
      }
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasErrorState = false;
      _errorMessage = null;
    });

    try {
      final result = await widget.onVerifyOtp(otp);
      if (!mounted) return;

      _resendTimer?.cancel();
      setState(() {
        _isVerifying = false;
        _isVerified = true;
      });

      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!disableAnim) {
        await Future.delayed(const Duration(milliseconds: 320));
      }
      if (!mounted) return;
      widget.onVerified(context, result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _hasErrorState = true;
        _errorMessage = e.message;
      });
      _triggerErrorShake();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _hasErrorState = true;
        _errorMessage = 'Verification failed. Check the code and try again.';
      });
      _triggerErrorShake();
    }
  }

  Future<void> _handleResend() async {
    if (widget.onResendOtp == null ||
        _secondsRemaining > 0 ||
        _isResending ||
        _isVerifying ||
        _isVerified) {
      return;
    }

    setState(() {
      _isResending = true;
      _hasErrorState = false;
      _errorMessage = null;
    });

    try {
      final res = await widget.onResendOtp!();
      if (!mounted) return;

      for (final c in _cellControllers) {
        c.clear();
      }
      _cellFocusNodes.first.requestFocus();

      final cooldownFromApi =
          (res['cooldown_seconds'] as num?)?.toInt() ?? widget.initialCooldownSeconds;
      setState(() {
        _isResending = false;
        _secondsRemaining = math.max(1, cooldownFromApi);
      });
      _startCountdownTimer();
      _triggerShieldPulse();

      final palette = _OtpPalette.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A new verification code is on its way.'),
          backgroundColor: palette.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _hasErrorState = true;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _hasErrorState = true;
        _errorMessage = 'Could not resend verification code. Please try again.';
      });
    }
  }

  String _formatCountdown(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _OtpPalette.of(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isCodeComplete = _otpCode.length == widget.otpLength;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A. Minimal Top Navigation
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                            onTap: _isVerifying
                                ? null
                                : () => Navigator.of(context).maybePop(),
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
                    ],
                  ),
                ),

                // Scrollable Body (keyboard safe)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // B. OTP Hero Section with Shield & Pulse Rings
                        MotionEntrance(
                          slideOffset: const Offset(0, 0.03),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAnimatedShield(palette, disableAnim),
                              const SizedBox(height: 26),
                              Text(
                                "Verify it's you",
                                style: HomeThemeTokens.manrope(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                  height: 1.15,
                                  color: palette.ink,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'We’ve sent a ${widget.otpLength}-digit verification code to your ${widget.destinationChannel}',
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: palette.mute,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.destinationMasked,
                                style: HomeThemeTokens.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: palette.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // C. Individual 6-Cell OTP Input
                        MotionEntrance(
                          delay: const Duration(milliseconds: 80),
                          slideOffset: const Offset(0, 0.03),
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
                            child: Row(
                              children: List.generate(widget.otpLength, (i) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: i < widget.otpLength - 1 ? 8.0 : 0,
                                    ),
                                    child: _buildOtpCell(
                                      index: i,
                                      palette: palette,
                                      disableAnim: disableAnim,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),

                        // Error Banner
                        AnimatedSize(
                          duration: disableAnim
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: _errorMessage != null
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.softError,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            palette.error.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline_rounded,
                                          size: 16,
                                          color: palette.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: HomeThemeTokens.manrope(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: palette.error,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        // D. Resend OTP Countdown / Trigger
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 18, 0, 26),
                          child: _buildResendSection(palette, disableAnim),
                        ),

                        // E. Verify Button
                        MotionEntrance(
                          delay: const Duration(milliseconds: 140),
                          slideOffset: const Offset(0, 0.03),
                          child: TactilePress(
                            scaleDown: 0.98,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: (!isCodeComplete || _isVerifying)
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: palette.teal
                                              .withValues(alpha: 0.35),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed:
                                    (!isCodeComplete || _isVerifying || _isVerified)
                                        ? null
                                        : _handleVerify,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isVerified
                                      ? palette.success
                                      : palette.teal,
                                  disabledBackgroundColor: _isVerified
                                      ? palette.success
                                      : palette.teal.withValues(alpha: 0.55),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor:
                                      Colors.white.withValues(alpha: 0.9),
                                  minimumSize: const Size(double.infinity, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: AnimatedSwitcher(
                                  duration: disableAnim
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                                  child: _isVerifying
                                      ? const SizedBox(
                                          key: ValueKey('otp_loading'),
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : _isVerified
                                          ? Row(
                                              key: const ValueKey('otp_done'),
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.check_circle_outline_rounded,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Verified',
                                                  style:
                                                      HomeThemeTokens.manrope(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Text(
                                              'Verify OTP',
                                              key: const ValueKey('otp_idle'),
                                              style: HomeThemeTokens.manrope(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                ),
                              ),
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
      ),
    );
  }

  Widget _buildAnimatedShield(_OtpPalette palette, bool disableAnim) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (!disableAnim) ...[
            _buildPulseRing(palette, startFraction: 0.0),
            _buildPulseRing(palette, startFraction: 0.35),
          ],
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.86, end: 1.0),
            duration: disableAnim
                ? Duration.zero
                : const Duration(milliseconds: 460),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: palette.softTeal,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                _isVerified
                    ? Icons.verified_rounded
                    : Icons.verified_user_outlined,
                size: 40,
                color: _isVerified ? palette.success : palette.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseRing(_OtpPalette palette, {required double startFraction}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final v = _pulseController.value;
        if (v < startFraction || v >= 1.0) {
          return const SizedBox.shrink();
        }
        final localT = ((v - startFraction) / (1.0 - startFraction))
            .clamp(0.0, 1.0);
        final waveT = (localT * 2.0) % 1.0;
        final fadeOut = localT > 0.7 ? (1.0 - localT) / 0.3 : 1.0;
        final scale = 1.0 + waveT * 0.45;
        final opacity = (0.45 * (1.0 - waveT) * fadeOut).clamp(0.0, 1.0);

        return IgnorePointer(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: palette.teal,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOtpCell({
    required int index,
    required _OtpPalette palette,
    required bool disableAnim,
  }) {
    final controller = _cellControllers[index];
    final focusNode = _cellFocusNodes[index];
    final isFocused = focusNode.hasFocus;
    final isFilled = controller.text.isNotEmpty;

    Color cellBg = palette.field;
    Color borderCol = Colors.transparent;
    if (_isVerified) {
      cellBg = palette.softSuccess;
      borderCol = palette.success;
    } else if (_hasErrorState) {
      cellBg = palette.softError;
      borderCol = palette.error;
    } else if (isFocused) {
      cellBg = palette.card;
      borderCol = palette.teal;
    } else if (isFilled) {
      cellBg = palette.softTeal;
      borderCol = palette.teal;
    }

    Color textCol = palette.ink;
    if (_isVerified) {
      textCol = palette.success;
    } else if (_hasErrorState) {
      textCol = palette.error;
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey('otp_cell_${index}_${controller.text}_$_isVerified'),
      tween: Tween<double>(
        begin: (isFilled || _isVerified) ? 0.92 : 1.0,
        end: 1.0,
      ),
      duration: disableAnim || (!isFilled && !_isVerified)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
        duration:
            disableAnim ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 60,
        decoration: BoxDecoration(
          color: cellBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderCol, width: 1.5),
          boxShadow: isFocused && !_hasErrorState && !_isVerified
              ? [
                  BoxShadow(
                    color: palette.teal.withValues(alpha: 0.14),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : const [],
        ),
        child: Focus(
          onKeyEvent: (_, event) => _handleCellKeyEvent(index, event),
          child: Center(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_isVerifying && !_isVerified,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofillHints:
                  index == 0 ? const [AutofillHints.oneTimeCode] : null,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: HomeThemeTokens.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textCol,
              ),
              cursorColor: palette.teal,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (value) => _handleCellChanged(index, value),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResendSection(_OtpPalette palette, bool disableAnim) {
    if (widget.onResendOtp == null && _secondsRemaining <= 0) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration:
          disableAnim ? Duration.zero : const Duration(milliseconds: 200),
      child: _isResending
          ? Row(
              key: const ValueKey('resending'),
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sending a fresh code...',
                  style: HomeThemeTokens.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.mute,
                  ),
                ),
              ],
            )
          : _secondsRemaining > 0
              ? Align(
                  key: const ValueKey('countdown'),
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: 'Resend code in ',
                      style: HomeThemeTokens.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.mute,
                      ),
                      children: [
                        TextSpan(
                          text: _formatCountdown(_secondsRemaining),
                          style: HomeThemeTokens.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Align(
                  key: const ValueKey('resend_ready'),
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Didn’t get it? ',
                        style: HomeThemeTokens.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.mute,
                        ),
                      ),
                      GestureDetector(
                        onTap: _handleResend,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Text(
                            'Resend code',
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
    );
  }
}

