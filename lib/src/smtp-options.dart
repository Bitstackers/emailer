/*        Copyright (C) 2015-, BitStackers K/S and Kai Sellgren

  This is free software;  you can redistribute it and/or modify it
  under terms of the  GNU General Public License  as published by the
  Free Software  Foundation;  either version 3,  or (at your  option) any
  later version. This software is distributed in the hope that it will be
  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  You should have received a copy of the GNU General Public License along with
  this program; see the file COPYING3. If not, see http://www.gnu.org/licenses.
*/

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
