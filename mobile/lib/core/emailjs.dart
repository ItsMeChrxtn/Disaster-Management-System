import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Sends the 6-digit verification code through EmailJS, exactly like
/// sendVerificationEmail() in frontend/assets/js/auth-pages.js.
class EmailJs {
  EmailJs._();

  static Future<bool> sendVerification(Map<String, dynamic> verification) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
            headers: {'Content-Type': 'application/json', 'Origin': AppConfig.emailJsOrigin, 'Referer': '${AppConfig.emailJsOrigin}/frontend/register.html'},
            body: jsonEncode({
              'service_id': AppConfig.emailJsServiceId,
              'template_id': AppConfig.emailJsVerifyTemplateId,
              'user_id': AppConfig.emailJsPublicKey,
              'template_params': {'to_email': verification['to_email'], 'to_name': verification['to_name'], 'code': verification['code'], 'expires_in_minutes': verification['expires_in_minutes']},
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
