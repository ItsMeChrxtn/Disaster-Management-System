import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/notifications.dart';
import 'core/session.dart';
import 'core/ui.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/public/landing_screen.dart';
import 'screens/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.init();
  await AlertNotifier.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
  runApp(const DisasterMapApp());
}

/// Theme mirrors frontend/assets/css/theme.css (Inter, blue primary, soft
/// borders, 8-16px radii) so the app and the website read as one product.
class DisasterMapApp extends StatelessWidget {
  const DisasterMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Ui.indigo, brightness: Brightness.light).copyWith(primary: Ui.indigo, surface: Colors.white, onSurface: Ui.slate900, outline: Ui.lineStrong);
    final textTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(bodyColor: const Color(0xFF1F2937), displayColor: Ui.slate900);
    final shape8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final shape10 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));

    return MaterialApp(
      title: 'Disaster Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        textTheme: textTheme,
        scaffoldBackgroundColor: Ui.slate100,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Ui.slate900,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: const Border(bottom: BorderSide(color: Ui.line)),
          titleTextStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Ui.slate900),
        ),
        cardTheme: const CardThemeData(color: Colors.white, surfaceTintColor: Colors.transparent),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titleTextStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: Ui.slate900),
          contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Ui.slate500, height: 1.5),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        ),
        dividerTheme: const DividerThemeData(color: Ui.line, thickness: 1),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: Ui.primarySoft,
          side: const BorderSide(color: Ui.lineStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.slate900),
          checkmarkColor: Ui.indigo,
          showCheckmark: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: Ui.slate400, fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.lineStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.lineStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.indigo, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.red, width: 1.6),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Ui.line),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Ui.indigo,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: shape8,
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Ui.slate900,
            backgroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            side: const BorderSide(color: Ui.lineStrong),
            shape: shape8,
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Ui.indigo,
            shape: shape8,
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        listTileTheme: ListTileThemeData(shape: shape10),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: shape10,
          contentTextStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Ui.line),
          ),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(),
      ),
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/verify-email': (_) => const VerifyEmailScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/reset-password': (_) => const ResetPasswordScreen(),
      },
    );
  }
}

/// Shows the public landing map when signed out and the role-aware shell when
/// signed in. A 401 from the API clears the session and lands back here.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final session = Session.instance;
        if (session.isAuthenticated) {
          return AppShell(key: ValueKey('shell-${session.user?['id']}'));
        }
        return const LandingScreen();
      },
    );
  }
}
