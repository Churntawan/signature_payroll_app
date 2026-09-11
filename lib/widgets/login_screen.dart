import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';
import 'language_toggle.dart';

class LoginScreen extends StatefulWidget {
  final List<Employee> employees;
  final Function(AuthSession session) onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.employees,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserRole _selectedRole = UserRole.admin;
  final _adminPasswordCtrl = TextEditingController();
  final _epCodeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  AppText? _errorMessageKey;
  bool _isLoading = false;

  @override
  void dispose() {
    _adminPasswordCtrl.dispose();
    _epCodeCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _handleLogin() {
    setState(() {
      _errorMessageKey = null;
      _isLoading = true;
    });

    if (_selectedRole == UserRole.admin) {
      final pwd = _adminPasswordCtrl.text;
      if (pwd.isEmpty) {
        setState(() {
          _errorMessageKey = L10n.errAdminPwdEmpty;
          _isLoading = false;
        });
        return;
      }

      if (AuthService.verifyAdmin(pwd)) {
        AuthService.saveSession(UserRole.admin, remember: _rememberMe);
        final session = AuthSession(role: UserRole.admin);
        widget.onLoginSuccess(session);
      } else {
        setState(() {
          _errorMessageKey = L10n.errAdminPwdWrong;
          _isLoading = false;
        });
      }
    } else {
      final epCode = _epCodeCtrl.text.trim();
      final pin = _pinCtrl.text.trim();

      if (epCode.isEmpty) {
        setState(() {
          _errorMessageKey = L10n.errEpCodeEmpty;
          _isLoading = false;
        });
        return;
      }

      if (pin.isEmpty) {
        setState(() {
          _errorMessageKey = L10n.errPinEmpty;
          _isLoading = false;
        });
        return;
      }

      final emp = AuthService.verifyEmployee(
        employees: widget.employees,
        epCode: epCode,
        pin: pin,
      );

      if (emp != null) {
        AuthService.saveSession(UserRole.employee, epCode: emp.epCode, remember: _rememberMe);
        final session = AuthSession(role: UserRole.employee, epCode: emp.epCode, employee: emp);
        widget.onLoginSuccess(session);
      } else {
        setState(() {
          _errorMessageKey = L10n.errEmployeeNotFound;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;

    return ValueListenableBuilder<SubLanguage>(
      valueListenable: L10n.currentSubLang,
      builder: (context, sub, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B1120),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  color: const Color(0xFF1E293B),
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFF334155), width: 1),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 20 : 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Header with Language Switcher
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.diamond_outlined, size: 22, color: Colors.white),
                            ),
                            const LanguageToggle(isCompact: true),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Title
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SIGNATURE',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
                            ),
                            Row(
                              children: [
                                const Text(
                                  'PAYROLL SUITE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '(${L10n.appTitle.sub(sub)})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Role Toggle Tabs
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      _selectedRole = UserRole.admin;
                                      _errorMessageKey = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == UserRole.admin
                                          ? const Color(0xFF0284C7)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.admin_panel_settings_outlined,
                                          size: 16,
                                          color: _selectedRole == UserRole.admin ? Colors.white : const Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            L10n.roleAdmin.get(sub),
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _selectedRole == UserRole.admin ? Colors.white : const Color(0xFF94A3B8),
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
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      _selectedRole = UserRole.employee;
                                      _errorMessageKey = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == UserRole.employee
                                          ? const Color(0xFF0284C7)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.person_outline,
                                          size: 16,
                                          color: _selectedRole == UserRole.employee ? Colors.white : const Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            L10n.roleStaff.get(sub),
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _selectedRole == UserRole.employee ? Colors.white : const Color(0xFF94A3B8),
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
                        ),
                        const SizedBox(height: 20),

                        // Inputs for Admin vs Employee
                        if (_selectedRole == UserRole.admin) ...[
                          Text(
                            L10n.password.get(sub),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _adminPasswordCtrl,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: L10n.passwordHint.sub(sub),
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF38BDF8), size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                        ] else ...[
                          Text(
                            L10n.employeeCode.get(sub),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _epCodeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: L10n.employeeCodeHint.sub(sub),
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF38BDF8), size: 20),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            L10n.pinCode.get(sub),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pinCtrl,
                            obscureText: _obscurePassword,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: L10n.pinCodeHint.sub(sub),
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFF38BDF8), size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                        ],

                        // Error message
                        if (_errorMessageKey != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F1D1D).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 16, color: Color(0xFFF87171)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessageKey!.get(sub),
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFFCA5A5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Remember Me Checkbox
                        Row(
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: const Color(0xFF0284C7),
                                side: const BorderSide(color: Color(0xFF64748B)),
                                onChanged: (val) => setState(() => _rememberMe = val ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                L10n.rememberSession.get(sub),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  '${L10n.loginButton.get(sub)} (${_selectedRole == UserRole.admin ? L10n.roleAdmin.primary : L10n.roleStaff.primary})',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
