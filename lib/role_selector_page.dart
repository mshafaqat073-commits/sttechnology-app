import 'package:flutter/material.dart';
import 'login_page.dart';
import 'teacher_login_page.dart';
import 'parent_login_page.dart';
import 'school_branding.dart';
import 'super_admin_subscription_page.dart';

/// When no user is logged in, this screen shows first — from here
/// admin/staff use their existing login, while teachers and parents go
/// to their own Login ID + PIN login. Each role has its own distinct
/// color identity so the right button can be recognized at a glance.
class RoleSelectorPage extends StatefulWidget {
  const RoleSelectorPage({super.key});

  @override
  State<RoleSelectorPage> createState() => _RoleSelectorPageState();
}

class _RoleSelectorPageState extends State<RoleSelectorPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          // School-binder style gradient — deep indigo at top (authority),
          // soft violet at the bottom (warmth). Each role card's own
          // accent color stands out against this background like a
          // "colored tab".
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241E63), Color(0xFF4A3B8C), Color(0xFF6C4EC4)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 64,
                      ),
                      child: IntrinsicHeight(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                    const SizedBox(height: 8),
                    Center(
                      // Long-pressing the logo for ~3 seconds opens the
                      // Super Admin (developer-only) Subscription Panel
                      // — normal users won't know it's there.
                      child: GestureDetector(
                        onLongPress: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const SuperAdminSubscriptionPage(),
                            ),
                          );
                        },
                        child: Container(
                          height: 104,
                          width: 104,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const ClipOval(
                            child: Image(
                              image: AssetImage(
                                'assets/st_technology_shafaqat_trust.png',
                              ),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: SchoolNameText(
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        "Continue as",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _RoleCard(
                      icon: Icons.admin_panel_settings_rounded,
                      title: "Admin",
                      subtitle: "School records, staff & settings",
                      colors: const [Color(0xFFFF5F6D), Color(0xFFFF9A44)],
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginPage())),
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      icon: Icons.school_rounded,
                      title: "Teacher",
                      subtitle: "Attendance, results & classes",
                      colors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherLoginPage())),
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      icon: Icons.family_restroom_rounded,
                      title: "Parent",
                      subtitle: "Track your child's progress",
                      colors: const [Color(0xFF4568DC), Color(0xFFB06AB3)],
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ParentLoginPage())),
                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each role has its own gradient-badge + card — the icon's color is the
/// role's identity (Admin = warm red/orange = authority, Teacher = green
/// = growth/classroom, Parent = blue/purple = trust/family), so the user
/// can find the right button at a glance without having to read the text.
class _RoleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  double _scale = 1.0;

  void _setPressed(bool pressed) =>
      setState(() => _scale = pressed ? 0.97 : 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.colors.last.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${widget.title} Login",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF241E63),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF241E63).withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Color(0xFF241E63)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
