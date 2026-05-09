import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/mfa_service.dart';
import '../services/mfa_session_service.dart';
import '../services/audit_service.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../utils/auth_errors.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';
import 'signup_flow_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mfaCodeController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _showMFA = false;
  String _userEmail = '';
  Timer? _resendCooldownTimer;
  int _resendCooldownSeconds = 0;
  UserRole _selectedRole = UserRole.employee;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppTheme.surfaceGray,
      appBar: AppBar(
        title: Row(
          children: [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text(
              _showMFA ? 'Verify 2FA' : 'SECURELY',
              style: textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.surfaceGray,
              Color(0xFFEFF6FF).withValues(alpha: 0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                if (!_showMFA) ...[
                  _buildTitleSection(),
                  if (!_isLogin) ...[
                    _buildNameField(),
                    SizedBox(height: 20),
                    _buildPhoneField(),
                    SizedBox(height: 20),
                    _buildRoleDropdown(),
                    SizedBox(height: 20),
                  ],
                  _buildEmailField(),
                  SizedBox(height: 20),
                  _buildPasswordField(),
                  if (_isLogin) ...[
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showPasswordRecoveryDialog,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 0),
                          minimumSize: Size(0, 32),
                        ),
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 24),
                  _buildAuthButton(),
                  SizedBox(height: 16),
                  _buildToggleButton(),
                  SizedBox(height: 16),
                ],

                if (_showMFA) ...[
                  _buildMfaIntro(),
                  SizedBox(height: 20),
                  Text(
                    'Check your email: $_userEmail\nWe sent you a verification code.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppTheme.mediumGray,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  _decoratedField(_buildMfaCodeField()),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyMFA,
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text('Verify & Login'),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: (_isLoading ||
                            _resendCooldownSeconds > 0 ||
                            _userEmail.isEmpty)
                        ? null
                        : () => _sendMFACode(isManualResend: true),
                    child: Text(
                      _resendCooldownSeconds > 0
                          ? 'Resend code (${_resendCooldownSeconds}s)'
                          : 'Resend code',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection() => Container(
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        margin: EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.softShadowLight(),
        ),
        child: Column(
          children: [
            AppLogo(size: 44),
            SizedBox(height: 14),
            Text(
              'SECURELY',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkSlate,
                    letterSpacing: -0.5,
                  ),
            ),
            SizedBox(height: 6),
            Text(
              'Secure chat for your team',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: AppTheme.accentCyan, size: 14),
                SizedBox(width: 6),
                Text(
                  'End-to-end encrypted',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildNameField() => _decoratedField(
        TextFormField(
          controller: _nameController,
          style: TextStyle(
            color: AppTheme.darkSlate,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration('Full Name'),
          validator: (v) =>
              v == null || v.isEmpty ? 'Please enter your name' : null,
        ),
      );

  Widget _buildPhoneField() => _decoratedField(
        TextFormField(
          controller: _phoneController,
          style: TextStyle(
            color: AppTheme.darkSlate,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration('Phone Number').copyWith(
            hintText: '+1234567890',
          ),
          validator: (v) =>
              v == null || v.isEmpty ? 'Please enter your phone number' : null,
        ),
      );

  Widget _buildRoleDropdown() => _decoratedField(
        DropdownButtonFormField<UserRole>(
          value: _selectedRole,
          decoration: _inputDecoration('Role'),
          items: [
            DropdownMenuItem(
                value: UserRole.employee, child: Text('Employee')),
            DropdownMenuItem(value: UserRole.manager, child: Text('Manager')),
          ],
          onChanged: (v) => setState(() => _selectedRole = v!),
        ),
      );

  Widget _buildEmailField() => _decoratedField(
        TextFormField(
          controller: _emailController,
          style: TextStyle(
            color: AppTheme.darkSlate,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration('Email'),
          validator: (v) =>
              v == null || v.isEmpty ? 'Please enter your email' : null,
        ),
      );

  Widget _buildPasswordField() => _decoratedField(
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          style: TextStyle(
            color: AppTheme.darkSlate,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration('Password'),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Please enter your password';
            if (v.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
        ),
      );

  Widget _buildAuthButton() => Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: _isLoading ? null : AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          boxShadow: _isLoading ? null : AppTheme.buttonShadow,
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleAuth,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isLoading ? AppTheme.mediumGray : Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.inputRadius)),
          ),
          child: _isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Processing...',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isLogin ? Icons.login : Icons.person_add,
                        color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      _isLogin ? 'Login' : 'Register',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
      );

  Widget _buildToggleButton() => TextButton(
          onPressed: () => setState(() => _isLogin = !_isLogin),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            _isLogin ? 'Need an account? Register' : 'Have an account? Login',
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        );

  Future<void> _showPasswordRecoveryDialog() async {
    final emailController = TextEditingController(text: _emailController.text.trim());
    final formKey = GlobalKey<FormState>();
    bool sending = false;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: !sending,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            title: Row(
              children: [
                Icon(Icons.lock_reset, color: AppTheme.primaryBlue, size: 26),
                SizedBox(width: 10),
                Text(
                  'Reset password',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your email and we\'ll send you a link to reset your password.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.mediumGray,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 20),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: TextStyle(
                        color: AppTheme.darkSlate,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Email',
                        hintStyle: TextStyle(color: AppTheme.mediumGray),
                        filled: true,
                        fillColor: AppTheme.lightGray,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your email';
                        if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.mediumGray, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final email = emailController.text.trim();
                        setDialogState(() => sending = true);
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Reset link sent! Check your email—and spam folder—for the link.',
                              ),
                              backgroundColor: AppTheme.successGreen,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => sending = false);
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(authErrorMessage(e)),
                              backgroundColor: AppTheme.errorRed,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  ),
                ),
                child: sending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Send link', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
    emailController.dispose();
  }

  Widget _buildMfaIntro() => Container(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        margin: EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.softShadowLight(),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined,
                  color: AppTheme.primaryBlue, size: 32),
            ),
            SizedBox(height: 16),
            Text(
              'Verify your identity',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkSlate,
                  ),
            ),
            SizedBox(height: 8),
            Text(
              'Enter the 6-digit code we emailed you',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.mediumGray,
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _buildMfaCodeField() => TextFormField(
          controller: _mfaCodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: '2FA Code',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.transparent,
            counterText: '',
          ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Enter the 6-digit code';
          if (value.length != 6) return 'Code must be 6 digits';
          return null;
        },
      );

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.primaryBlue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
      );

  Widget _decoratedField(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          boxShadow: AppTheme.softShadowLight(),
        ),
        child: child,
      );

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      User? user;
      if (_isLogin) {
        user = await _authService.signInWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SignupFlowScreen(
              email: _emailController.text,
              password: _passwordController.text,
              name: _nameController.text,
              selectedRole: _selectedRole,
            ),
          ),
        );
        return;
      }

      if (user != null) {
        await AuditService.logLogin(success: true, userId: user.uid, email: _emailController.text.trim());
        final hasMFA = await MFAService.hasMFAEnabled();
        if (hasMFA) {
          _userEmail = _emailController.text;

          setState(() {
            _showMFA = true;
            _isLoading = false;
          });

          await _sendMFACode();
        } else {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
        }
      } else {
        await AuditService.logLogin(success: false, email: _emailController.text.trim());
        if (mounted) {
          _showSnackBar('Wrong email or password. Please try again.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(authErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startResendCooldown() {
    _resendCooldownTimer?.cancel();
    const seconds = 45;
    setState(() => _resendCooldownSeconds = seconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldownSeconds--;
        if (_resendCooldownSeconds <= 0) {
          t.cancel();
          _resendCooldownSeconds = 0;
        }
      });
    });
  }

  Future<void> _sendMFACode({bool isManualResend = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sent = await MFAService.sendEmailMFA(_userEmail);

      if (!mounted) return;
      if (sent) {
        _showSnackBar('Code sent! Check your email.', isError: false);
        if (isManualResend) {
          _startResendCooldown();
        }
      } else {
        _showSnackBar(
          'Could not send email. On Android: EmailJS → Account → Security → allow API for non-browser apps.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyMFA() async {
    final code = _mfaCodeController.text.trim();
    if (code.isEmpty) {
      _showError('Enter the code');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final isValid = MFAService.verifyEmailMFA(code);
      
      if (isValid) {
        await AuditService.logMfa(success: true, userId: FirebaseAuth.instance.currentUser?.uid, email: _userEmail);
        await MFASessionService.markMFACompleted();

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
      } else {
        await AuditService.logMfa(success: false, userId: FirebaseAuth.instance.currentUser?.uid, email: _userEmail);
        if (MFAService.isCodeExpired()) {
          _showError('Code expired. Please request a new one.');
        } else {
          _showError('Wrong code. Please try again.');
        }
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  void _showError(String message) {
    setState(() => _isLoading = false);
    _showSnackBar(message, isError: true);
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorRed : AppTheme.successGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final void Function(String message, {required bool isError}) showSnackBar;

  const _ResetPasswordDialog({
    required this.initialEmail,
    required this.showSnackBar,
  });

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _controller.text.trim();
    if (email.isEmpty) {
      widget.showSnackBar('Please enter your email.', isError: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.showSnackBar(
        'Check your email for a link to reset your password.',
        isError: false,
      );
    } catch (e) {
      if (mounted) {
        widget.showSnackBar(authErrorMessage(e), isError: true);
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return Theme(
      data: Theme.of(ctx).copyWith(
        dialogBackgroundColor: Colors.white,
        colorScheme: Theme.of(ctx).colorScheme.copyWith(
          surface: Colors.white,
          onSurface: AppTheme.darkSlate,
        ),
      ),
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius + 4),
        ),
        title: Row(
          children: [
            Icon(Icons.lock_reset, color: AppTheme.primaryBlue, size: 24),
            SizedBox(width: 10),
            Text(
              'Reset password',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkSlate,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your email and we\'ll send a link to reset your password.',
                style: TextStyle(
                  color: AppTheme.mediumGray,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: TextStyle(color: AppTheme.darkSlate),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: AppTheme.mediumGray),
                  hintText: 'you@example.com',
                  hintStyle: TextStyle(color: AppTheme.mediumGray),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceGray,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppTheme.mediumGray)),
          ),
          TextButton(
            onPressed: _sending ? null : _sendReset,
            child: _sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryBlue,
                    ),
                  )
                : Text(
                    'Send link',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
