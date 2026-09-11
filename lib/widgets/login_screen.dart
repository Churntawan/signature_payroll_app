import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/auth_service.dart';

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
  String? _errorMessage;
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
      _errorMessage = null;
      _isLoading = true;
    });

    if (_selectedRole == UserRole.admin) {
      final pwd = _adminPasswordCtrl.text;
      if (pwd.isEmpty) {
        setState(() {
          _errorMessage = 'กรุณากรอกรหัสผ่านผู้ดูแลระบบ';
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
          _errorMessage = 'รหัสผ่านไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
          _isLoading = false;
        });
      }
    } else {
      final epCode = _epCodeCtrl.text.trim();
      final pin = _pinCtrl.text.trim();

      if (epCode.isEmpty) {
        setState(() {
          _errorMessage = 'กรุณาระบุรหัสพนักงาน (เช่น EP39)';
          _isLoading = false;
        });
        return;
      }

      if (pin.isEmpty) {
        setState(() {
          _errorMessage = 'กรุณาระบุรหัส PIN 4-6 หลัก';
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
          _errorMessage = 'รหัสพนักงานหรือ PIN ไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;

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
                    // Brand Logo & Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.diamond_outlined, size: 28, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SIGNATURE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'PAYROLL SUITE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

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
                                  _errorMessage = null;
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
                                    Text(
                                      'ผู้ดูแลระบบ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedRole == UserRole.admin ? Colors.white : const Color(0xFF94A3B8),
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
                                  _errorMessage = null;
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
                                    Text(
                                      'พนักงาน',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedRole == UserRole.employee ? Colors.white : const Color(0xFF94A3B8),
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
                    const SizedBox(height: 24),

                    // Inputs for Admin vs Employee
                    if (_selectedRole == UserRole.admin) ...[
                      const Text(
                        'รหัสผ่านผู้ดูแลระบบ (Admin Password)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _adminPasswordCtrl,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'กรอกรหัสผ่านเพื่อเข้าสู่ระบบ',
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
                      const Text(
                        'รหัสพนักงาน (Employee Code)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _epCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'เช่น EP01, EP39',
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
                      const Text(
                        'รหัส PIN (4-6 หลัก)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pinCtrl,
                        obscureText: _obscurePassword,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'กรอกรหัส PIN ประจำตัว',
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
                    if (_errorMessage != null) ...[
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
                                _errorMessage!,
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
                        const Expanded(
                          child: Text(
                            'จดจำการเข้าสู่ระบบบนอุปกรณ์นี้',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
                              _selectedRole == UserRole.admin ? 'เข้าสู่ระบบจัดการ (Admin)' : 'เข้าสู่ระบบพนักงาน (Portal)',
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
  }
}
