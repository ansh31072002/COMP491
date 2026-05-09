import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/audit_service.dart';
import '../services/report_service.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/user_avatar.dart';

class AdminPanelScreen extends StatefulWidget {
  @override
  _AdminPanelScreenState createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  UserRoleModel? _currentUserRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final userRole = await _authService.getCurrentUserRole();
      setState(() {
        _currentUserRole = userRole;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user role: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changeUserRole(String userId, String targetEmail, UserRole oldRole, UserRole newRole) async {
    if (oldRole == newRole) return;
    try {
      await _firestore.collection('user_roles').doc(userId).update({
        'role': newRole.toString().split('.').last,
      });
      await AuditService.logRoleChange(
        targetUserId: userId,
        targetEmail: targetEmail,
        oldRole: oldRole.toString().split('.').last,
        newRole: newRole.toString().split('.').last,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated successfully'),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating role. Please try again.'),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceGray,
        appBar: _buildAppBar('Admin'),
        body: Container(
          color: AppTheme.surfaceGray,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: AppTheme.primaryBlue,
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Loading Admin Panel...',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_currentUserRole == null || !_currentUserRole!.isManager()) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceGray,
        appBar: _buildAppBar('Admin'),
        body: Container(
          color: AppTheme.surfaceGray,
          child: Center(
            child: Container(
              margin: EdgeInsets.all(24),
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.errorRed, AppTheme.accentPink],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.block, color: Colors.white, size: 32),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Access Denied',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You need manager privileges to access this panel.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.mediumGray,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceGray,
      appBar: _buildAppBar('Admin'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final double sideBySideCardHeight = 360;
          return Container(
            color: AppTheme.surfaceGray,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAdminStatusCard(),
                  const SizedBox(height: 16),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildUserManagementSection(
                            isDense: true,
                            height: sideBySideCardHeight,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildAuditLogSection(
                            isDense: true,
                            height: sideBySideCardHeight,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildUserManagementSection(),
                    const SizedBox(height: 16),
                    _buildAuditLogSection(),
                  ],
                  const SizedBox(height: 16),
                  _buildReportsSection(isDense: isWide, height: isWide ? sideBySideCardHeight : 300),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================
  // SUB-WIDGET BUILDERS
  // ===========================

  AppBar _buildAppBar(String title) {
    final tt = Theme.of(context).textTheme;
    return AppBar(
      backgroundColor: AppTheme.primaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 0,
      leading: Navigator.of(context).canPop()
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Row(
        children: [
          const AppLogo(size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Manage access, roles & activity',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You are a manager',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'View users, update roles and review recent security activity from this panel.',
                  style: TextStyle(
                    color: AppTheme.mediumGray,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementSection({bool isDense = false, double? height}) {
    final Widget card = Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.people_alt_outlined, color: AppTheme.primaryBlue, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Users & roles',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGray,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: AppTheme.mediumGray),
                        const SizedBox(width: 4),
                        Text(
                          'Tap menu to change role',
                          style: TextStyle(fontSize: 11, color: AppTheme.mediumGray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('user_roles').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: AppTheme.primaryBlue,
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading users...',
                            style: TextStyle(
                              color: AppTheme.mediumGray,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: AppTheme.errorRed),
                          SizedBox(height: 16),
                          Text(
                            'Error: ${snapshot.error}',
                            style: TextStyle(
                              color: AppTheme.errorRed,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  final users = snapshot.data?.docs ?? [];

                  if (users.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: AppTheme.warmGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.people_outline, color: Colors.white, size: 32),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkSlate,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Users will appear here once they register',
                            style: TextStyle(
                              color: AppTheme.mediumGray,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final userData = users[index].data() as Map<String, dynamic>;
                      final userRole = UserRoleModel.fromMap(userData);
                      final isCurrentUser = userRole.userId == FirebaseAuth.instance.currentUser?.uid;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGray,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (userRole.isManager()
                                    ? AppTheme.primaryBlue
                                    : AppTheme.mediumGray)
                                .withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: _firestore
                                  .collection('users')
                                  .doc(userRole.userId)
                                  .snapshots(),
                              builder: (context, userSnap) {
                                final u = userSnap.data?.data();
                                final displayName = u?['name'] as String? ??
                                    userRole.email.split('@').first;
                                final photo = u?['photoUrl'] as String?;
                                final b64 = u?['profilePhotoBase64'] as String?;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    UserAvatar(
                                      name: displayName,
                                      profilePhotoBase64: b64,
                                      photoUrl: photo,
                                      radius: 22,
                                      backgroundColor: userRole.isManager()
                                          ? AppTheme.primaryBlue.withOpacity(0.12)
                                          : AppTheme.mediumGray.withOpacity(0.14),
                                      foregroundColor: userRole.isManager()
                                          ? AppTheme.primaryBlue
                                          : AppTheme.mediumGray,
                                    ),
                                    if (userRole.isManager())
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: CircleAvatar(
                                          radius: 9,
                                          backgroundColor: AppTheme.primaryBlue,
                                          child: Icon(
                                            Icons.admin_panel_settings,
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userRole.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppTheme.darkSlate,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: userRole.isManager()
                                              ? AppTheme.primaryBlue.withOpacity(0.08)
                                              : AppTheme.lightGray,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          userRole.isManager() ? 'Manager' : 'Employee',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: userRole.isManager()
                                                ? AppTheme.primaryBlue
                                                : AppTheme.mediumGray,
                                          ),
                                        ),
                                      ),
                                      if (isCurrentUser) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          'You',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.successGreen,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (!isCurrentUser)
                              PopupMenuButton<String>(
                                tooltip: 'Change role',
                                onSelected: (value) {
                                  final newRole = value == 'manager'
                                      ? UserRole.manager
                                      : UserRole.employee;
                                  _changeUserRole(
                                      userRole.userId, userRole.email, userRole.role, newRole);
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'employee',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_outline,
                                            color: AppTheme.mediumGray, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Set as employee'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'manager',
                                    child: Row(
                                      children: [
                                        Icon(Icons.admin_panel_settings,
                                            color: AppTheme.primaryBlue, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Set as manager'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    if (height != null) {
      return SizedBox(height: height, child: card);
    }
    return SizedBox(
      height: isDense ? 420 : 380,
      child: card,
    );
  }

  Widget _buildAuditLogSection({bool isDense = false, double? height}) {
    final double boxHeight = height ?? (isDense ? 260 : 220);
    return SizedBox(
      height: boxHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.timeline, color: AppTheme.primaryBlue, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Logins, MFA events and role updates',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.mediumGray,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: AuditService.recentLogsStream(limit: 30),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load audit log',
                        style: TextStyle(color: AppTheme.mediumGray, fontSize: 14),
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No security events yet',
                        style: TextStyle(color: AppTheme.mediumGray, fontSize: 13),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final d = docs[index].data() as Map<String, dynamic>;
                      final action = d['action'] as String? ?? '—';
                      final ts = d['timestamp'];
                      String timeStr = '';
                      if (ts is Timestamp) {
                        final dt = ts.toDate();
                        timeStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                      }
                      final success = d['success'];
                      final who = _whoForEntry(d, action);
                      String subtitle = timeStr;
                      if (action == 'login') {
                        subtitle = (success == true ? 'Success' : 'Failed') + (timeStr.isNotEmpty ? ' · $timeStr' : '');
                      } else if (action == 'role_change') {
                        subtitle = '${d['oldRole'] ?? '?'} → ${d['newRole'] ?? '?'}' + (timeStr.isNotEmpty ? ' · $timeStr' : '');
                      } else if (action == 'mfa_verify') {
                        subtitle = (success == true ? 'Success' : 'Failed') + (timeStr.isNotEmpty ? ' · $timeStr' : '');
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceGray,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Icon(
                                _iconForAction(action),
                                size: 14,
                                color: AppTheme.mediumGray,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _labelForAction(action),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: AppTheme.darkSlate,
                                        ),
                                      ),
                                      if (timeStr.isNotEmpty)
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.mediumGray,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (who.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        who,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.primaryBlue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  if (subtitle.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        subtitle,
                                        style: TextStyle(fontSize: 11, color: AppTheme.mediumGray),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsSection({bool isDense = false, double? height}) {
    final double boxHeight = height ?? (isDense ? 320 : 280);
    return SizedBox(
      height: boxHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.flag_outlined, color: AppTheme.errorRed, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'User-submitted issues for review',
                        style: TextStyle(fontSize: 11, color: AppTheme.mediumGray),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: ReportService.recentReportsStream(limit: 50),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load reports',
                        style: TextStyle(color: AppTheme.mediumGray, fontSize: 13),
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No reports yet',
                        style: TextStyle(color: AppTheme.mediumGray, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final d = doc.data() as Map<String, dynamic>;
                      final status = (d['status'] as String?) ?? 'open';
                      final isResolved = status == 'resolved';
                      final reason = (d['reason'] as String?) ?? '—';
                      final details = (d['details'] as String?) ?? '';
                      final reporterEmail = (d['reporterEmail'] as String?) ?? '—';
                      final reportedEmail = (d['reportedEmail'] as String?) ?? '—';

                      Color chipBg = isResolved
                          ? AppTheme.successGreen.withOpacity(0.10)
                          : AppTheme.errorRed.withOpacity(0.10);
                      Color chipFg = isResolved ? AppTheme.successGreen : AppTheme.errorRed;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGray,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.lightGray),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isResolved ? 'Resolved' : 'Open',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chipFg),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.darkSlate,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reported user: $reportedEmail',
                                    style: TextStyle(fontSize: 12, color: AppTheme.mediumGray),
                                  ),
                                  Text(
                                    'Reporter: $reporterEmail',
                                    style: TextStyle(fontSize: 12, color: AppTheme.mediumGray),
                                  ),
                                  if (details.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      details,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Report actions',
                              onSelected: (value) async {
                                if (value == 'resolve') {
                                  await ReportService.setReportResolved(
                                    reportId: doc.id,
                                    resolved: true,
                                  );
                                } else if (value == 'reopen') {
                                  await ReportService.setReportResolved(
                                    reportId: doc.id,
                                    resolved: false,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                if (!isResolved)
                                  PopupMenuItem(
                                    value: 'resolve',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Mark resolved'),
                                      ],
                                    ),
                                  ),
                                if (isResolved)
                                  PopupMenuItem(
                                    value: 'reopen',
                                    child: Row(
                                      children: [
                                        Icon(Icons.undo, color: AppTheme.mediumGray, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Reopen'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForAction(String action) {
    switch (action) {
      case 'login': return Icons.login;
      case 'logout': return Icons.logout;
      case 'mfa_verify': return Icons.verified_user;
      case 'role_change': return Icons.admin_panel_settings;
      default: return Icons.circle;
    }
  }

  String _labelForAction(String action) {
    switch (action) {
      case 'login': return 'Login';
      case 'logout': return 'Logout';
      case 'mfa_verify': return 'MFA verify';
      case 'role_change': return 'Role change';
      default: return action;
    }
  }

  /// Returns the "who" line for an audit entry (email or description).
  String _whoForEntry(Map<String, dynamic> d, String action) {
    if (action == 'role_change') {
      final target = d['targetEmail'] as String?;
      return target?.isNotEmpty == true ? target! : '—';
    }
    final email = d['email'] as String?;
    return email?.isNotEmpty == true ? email! : '—';
  }

  Widget _buildSecurityFeaturesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: AppTheme.successGreen.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.security, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Security at a glance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your workspace is protected by multiple layers of security and continuous auditing.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.mediumGray,
            ),
          ),
          const SizedBox(height: 14),
          _buildSecurityFeature('AES‑256 encrypted data in transit', Icons.lock_outline),
          _buildSecurityFeature('Multi‑factor authentication (MFA)', Icons.verified_user_outlined),
          _buildSecurityFeature('Role‑based access control (RBAC)', Icons.admin_panel_settings_outlined),
          _buildSecurityFeature('Audit trail for key events', Icons.receipt_long_outlined),
        ],
      ),
    );
  }

  Widget _buildSecurityFeature(String text, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.successGreen, size: 16),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.darkSlate,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

}
