import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/user_role.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache user role to avoid repeated Firebase calls
  UserRoleModel? _cachedUserRole;
  String? _cachedUserId;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      return null;
    }
  }

  Future<User?> registerWithEmailAndPassword(String email, String password, String name) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (result.user != null) {
        await result.user!.updateDisplayName(name);
        await result.user!.reload();
        await _saveUserToFirestore(result.user!.uid, email, name);
      }
      
      return result.user;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveUserToFirestore(String uid, String email, String name) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      await _firestore.collection('user_roles').doc(uid).set({
        'userId': uid,
        'role': 'employee',
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
      });
      
      await _firestore.collection('user_roles').doc(uid).set({
        'userId': uid,
        'role': 'employee',
        'email': email,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _cachedUserRole = null;
    _cachedUserId = null;
  }

  Future<void> setUserRole(String userId, UserRole role) async {
    try {
      await _firestore.collection('user_roles').doc(userId).set({
        'userId': userId,
        'role': role.toString().split('.').last,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      await _firestore.collection('user_roles').doc(userId).set({
        'userId': userId,
        'role': role.toString().split('.').last,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
  }
  
  Future<UserRoleModel?> getCurrentUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      
      if (_cachedUserRole != null && _cachedUserId == user.uid) {
        return _cachedUserRole;
      }
      
      final doc = await _firestore
          .collection('user_roles')
          .doc(user.uid)
          .get()
          .timeout(Duration(seconds: 5));
      
      if (doc.exists && doc.data() != null) {
        _cachedUserRole = UserRoleModel.fromMap(doc.data()!);
        _cachedUserId = user.uid;
        return _cachedUserRole;
      }
      
      _cachedUserRole = UserRoleModel(
        userId: user.uid,
        role: UserRole.employee,
        email: user.email ?? '',
      );
      _cachedUserId = user.uid;
      return _cachedUserRole;
    } catch (e) {
      _cachedUserRole = UserRoleModel(
        userId: _auth.currentUser?.uid ?? '',
        role: UserRole.employee,
        email: _auth.currentUser?.email ?? '',
      );
      _cachedUserId = _auth.currentUser?.uid;
      return _cachedUserRole;
    }
  }
  
  Future<bool> isUserManager() async {
    try {
      final userRole = await getCurrentUserRole();
      return userRole?.isManager() ?? false;
    } catch (e) {
      return false;
    }
  }

}
