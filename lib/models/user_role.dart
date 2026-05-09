
enum UserRole {
  employee,
  manager,
}

class UserRoleModel {
  final String userId;
  final UserRole role;
  final String email;
  
  UserRoleModel({
    required this.userId,
    required this.role,
    required this.email,
  });
  
  // Simple role checking
  bool isManager() => role == UserRole.manager;
  bool isEmployee() => role == UserRole.employee;
  
  // Convert to/from Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role.toString().split('.').last, // 'employee' or 'manager'
      'email': email,
    };
  }
  
  static UserRoleModel fromMap(Map<String, dynamic> map) {
    return UserRoleModel(
      userId: map['userId'] ?? '',
      role: map['role'] == 'manager' ? UserRole.manager : UserRole.employee,
      email: map['email'] ?? '',
    );
  }
}
