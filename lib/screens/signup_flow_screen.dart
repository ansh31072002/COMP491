import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/mfa_service.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../utils/auth_errors.dart';
import '../services/audit_service.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignupFlowScreen extends StatefulWidget {
  final String email;
  final String password;
  final String name;
  final UserRole selectedRole;

  SignupFlowScreen({
    required this.email,
    required this.password,
    required this.name,
    required this.selectedRole,
  });

  @override
  _SignupFlowScreenState createState() => _SignupFlowScreenState();
}

class _SignupFlowScreenState extends State<SignupFlowScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _mfaCodeController = TextEditingController();
  
  bool _isLoading = false;
  String _userEmail = '';
  String _currentStep = 'register'; // 'register', 'mfa_setup', 'mfa_verify'

  @override
  void initState() {
    super.initState();
    _startSignupFlow();
  }

  Future<void> _startSignupFlow() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.registerWithEmailAndPassword(
        widget.email,
        widget.password,
        widget.name,
      );

      if (user != null) {
        await _authService.setUserRole(user.uid, widget.selectedRole);
        
        // Store user info for MFA
        _userEmail = widget.email;

        setState(() {
          _currentStep = 'mfa_setup';
          _isLoading = false;
        });
        
        await Future.delayed(Duration(milliseconds: 500));
        await _setupMFA();
      } else {
        _showError('Registration failed. Please try again.');
      }
    } catch (e) {
      _showError(authErrorMessage(e));
    }
  }

  Future<void> _setupMFA() async {
    setState(() {
      _currentStep = 'mfa_verify';
    });
    await _sendMFACode();
  }

  Future<void> _sendMFACode() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sent = await MFAService.sendEmailMFA(_userEmail);

      if (!mounted) return;

      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code sent! Check your email.'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not send email. On Android: enable non-browser API in EmailJS Security (see notification_config comments).',
            ),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authErrorMessage(e)),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
        // MFA verified - go to home automatically
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
      _showError(authErrorMessage(e));
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _mfaCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text(
              'Complete Signup',
              style: tt.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Go back to login screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => LoginScreen()),
            );
          },
        ),
      ),
      body: Container(
        color: AppTheme.surfaceGray,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress indicator
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _getProgressValue(),
                      backgroundColor: AppTheme.lightGray,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    SizedBox(height: 12),
                    Text(
                      _getProgressText(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                  ],
                ),
              ),
            
            SizedBox(height: 20),
            
              // Step content
              Expanded(
                child: _buildCurrentStep(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getProgressValue() {
    switch (_currentStep) {
      case 'register':
        return 0.33;
      case 'mfa_setup':
        return 0.66;
      case 'mfa_verify':
        return 1.0;
      default:
        return 0.0;
    }
  }

  String _getProgressText() {
    switch (_currentStep) {
      case 'register':
        return 'Creating your account...';
      case 'mfa_setup':
        return 'Setting up security...';
      case 'mfa_verify':
        return 'Verifying your identity...';
      default:
        return 'Getting started...';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 'register':
        return _buildRegisterStep();
      case 'mfa_setup':
        return _buildMFASetupStep();
      case 'mfa_verify':
        return _buildMFAVerifyStep();
      default:
        return Container();
    }
  }

  Widget _buildRegisterStep() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(32),
        margin: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, AppTheme.lightGray],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading) ...[
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Creating your account...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkSlate,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please wait while we set up your account',
                style: TextStyle(
                  color: AppTheme.mediumGray,
                ),
              ),
            ] else ...[
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(Icons.person_add, size: 36, color: Colors.white),
              ),
              SizedBox(height: 20),
              Text(
                'Setting up your account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkSlate,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please wait while we create your account...',
                style: TextStyle(
                  color: AppTheme.mediumGray,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMFASetupStep() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(32),
        margin: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, AppTheme.lightGray],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentCyan.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentCyan.withOpacity(0.3),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.security, size: 36, color: Colors.white),
            ),
            SizedBox(height: 20),
            Text(
              'Setting up 2FA',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkSlate,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Setting up security for your account...',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.mediumGray,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            if (_isLoading) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Setting up MFA...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMFAVerifyStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.3),
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.security, size: 36, color: Colors.white),
        ),
        SizedBox(height: 16),
        Text(
          'Verify Your Account',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppTheme.darkSlate,
            letterSpacing: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 16),
        Text(
          'Check your email: $_userEmail\nWe sent you a verification code.',
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.mediumGray,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        
        SizedBox(height: 20),
        
        
        // Code input
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _mfaCodeController,
            decoration: InputDecoration(
              labelText: 'Enter verification code',
              hintText: '123456',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
        
        SizedBox(height: 20),
        
        // Verify button
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.3),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyMFA,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : Text(
                    'Verify & Complete Signup',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        
        SizedBox(height: 16),
        
        // Resend Code Button
        TextButton(
          onPressed: _isLoading ? null : _sendMFACode,
          child: Text(
            'Resend Code',
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: 8),
        
      ],
    );
  }

}
