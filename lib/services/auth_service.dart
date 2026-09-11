import '../models/employee.dart';
import 'session_storage.dart';

enum UserRole {
  admin,
  employee,
}

class AuthSession {
  final UserRole role;
  final String? epCode;
  final Employee? employee;

  AuthSession({
    required this.role,
    this.epCode,
    this.employee,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isEmployee => role == UserRole.employee;
}

class AuthService {
  // Admin password configured for the system owner
  static const String adminPassword = 'Churn2543';

  // Storage keys
  static const String _keyRole = 'sp_auth_role';
  static const String _keyEpCode = 'sp_auth_ep_code';

  /// Verify admin login credentials
  static bool verifyAdmin(String password) {
    return password.trim() == adminPassword;
  }

  /// Verify employee login credentials (EP Code + PIN)
  static Employee? verifyEmployee({
    required List<Employee> employees,
    required String epCode,
    required String pin,
  }) {
    final cleanEp = epCode.trim().toUpperCase();
    final cleanPin = pin.trim();

    for (final emp in employees) {
      if (emp.epCode.trim().toUpperCase() == cleanEp) {
        if (emp.pin.trim() == cleanPin) {
          return emp;
        }
      }
    }
    return null;
  }

  /// Load session from browser storage if saved
  static AuthSession? loadSavedSession(List<Employee> employees) {
    final roleStr = SessionStorage.get(_keyRole);
    if (roleStr == null || roleStr.isEmpty) return null;

    if (roleStr == 'admin') {
      return AuthSession(role: UserRole.admin);
    } else if (roleStr == 'employee') {
      final ep = SessionStorage.get(_keyEpCode) ?? '';
      if (ep.isNotEmpty) {
        final cleanEp = ep.trim().toUpperCase();
        final emp = employees.firstWhere(
          (e) => e.epCode.trim().toUpperCase() == cleanEp,
          orElse: () => Employee(
            epCode: cleanEp,
            nickname: cleanEp,
            status: 'Active',
            baseSalary: 0,
            payGroup: 'Date : 10',
          ),
        );
        return AuthSession(role: UserRole.employee, epCode: cleanEp, employee: emp);
      }
    }
    return null;
  }

  /// Save session to storage
  static void saveSession(UserRole role, {String? epCode, bool remember = true}) {
    if (!remember) return;
    if (role == UserRole.admin) {
      SessionStorage.set(_keyRole, 'admin');
      SessionStorage.remove(_keyEpCode);
    } else {
      SessionStorage.set(_keyRole, 'employee');
      if (epCode != null) {
        SessionStorage.set(_keyEpCode, epCode.trim().toUpperCase());
      }
    }
  }

  /// Clear session from storage on logout
  static void clearSession() {
    SessionStorage.remove(_keyRole);
    SessionStorage.remove(_keyEpCode);
  }
}
