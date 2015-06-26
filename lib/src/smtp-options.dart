library emailer.smtp;

import 'dart:io';

/**
 * Options for a SMTP connection.
 */
class SmtpOptions {
  String hostName;
  bool   ignoreBadCertificate = true;
  String name                 = Platform.localHostname;
  String password;
  int    port                 = 465;
  bool   secure               = false;
  String username;
}

/**
 * Predefined options for connecting to Gmail SMTP.
 */
class GmailSmtpOptions extends SmtpOptions {
  final String hostName = 'smtp.gmail.com';
  final int    port     = 465;
  final bool   secure   = true;
}
