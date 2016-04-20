/*                 Copyright (C) 2015-, BitStackers K/S

  This is free software;  you can redistribute it and/or modify it
  under terms of the  GNU General Public License  as published by the
  Free Software  Foundation;  either version 3,  or (at your  option) any
  later version. This software is distributed in the hope that it will be
  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  You should have received a copy of the GNU General Public License along with
  this program; see the file COPYING3. If not, see http://www.gnu.org/licenses.
*/

library emailer.email;

import 'dart:convert';
import 'dart:math' show Random;

import 'attachment.dart';

import 'package:cryptoutils/cryptoutils.dart';
import 'package:intl/intl.dart';

/**
 * The kinds of emails this library supports.
 */
enum EmailKind {
  empty,
  text,
  html,
  textHtml,
  textAttach,
  htmlAttach,
  textHtmlAttach
}

/**
 * This class represents an email address. It MUST contain a valid email address
 * (addrSpec) and it MAY contain the display name of the address.
 *
 * See https://tools.ietf.org/html/rfc5322 for more information.
 */
class Address {
  String _addrSpec;
  String _displayName;

  String get addrSpec => _addrSpec;
  String get displayName => _displayName;

  /**
   * Constructor.
   */
  Address(String addrSpec, [String displayName = '']) {
    _addrSpec = _sanitize(addrSpec);
    _displayName = _sanitize(displayName);
  }

  /**
   * This returns a name-adr String where the display name part is BASE64
   * encoded. This function expects displayName to be UTF-8.
   */
  String render() {
    final StringBuffer sb = new StringBuffer();

    if (displayName.isEmpty) {
      sb.write(addrSpec);
    } else {
      sb.write(_encode(_displayName));
      sb.write(' <${_addrSpec}>');
    }

    return sb.toString();
  }

  /**
   * Remove linefeeds, tabs and potentially harmful characters from [value].
   */
  _sanitize(String value) {
    if (value == null) {
      return '';
    }

    return value.replaceAll(
        new RegExp('(\\r|\\n|\\t|"|,|<|>)+', caseSensitive: false), '');
  }
}

/**
 * This is class represents an email. Add text/html parts, attachments, subject,
 * recipients, from and then send it using the Smtp.Send function.
 *
 * Recipients are defined as lists of [Address]'s.
 */
class Email {
  final List<Attachment> attachments = [];
  final List<Address> _ccRecipients = [];
  int _counter = 0;
  String customMessageId = '';
  Encoding encoding = UTF8;
  final String fqdnSendingHost;
  final Address from;
  final String identityString = 'dart-emailer';
  String partHtml;
  String partText;
  final List<Address> _recipients = [];
  String subject;
  final List<Address> _toRecipients = [];
  final Map<String, String> _xHeaders = new Map<String, String>();

  /**
   * Constructor.
   *
   * fqdnSendingHost is a SHOULD part of the Message-ID: header per RFC 5322. It
   * is recommended to set this to the actual sending host, so we force it here in
   * the constructor.
   */
  Email(Address this.from, String this.fqdnSendingHost);

  /**
   * Add all the [attachments] to the [sb] buffer, separated by [boundary].
   */
  void _addAttachments(StringBuffer sb, String boundary) {
    attachments.forEach((Attachment attachment) {
      sb.writeln('--${boundary}');
      sb.writeln(
          'Content-Type: ${attachment.mimeType}; name="${attachment.fileName}"');
      sb.writeln('Content-Transfer-Encoding: base64');
      sb.write(
          'Content-Disposition: attachment; filename="${attachment.fileName}"\n\n');
      sb.write('${attachment.content}\n\n');
    });
  }

  /**
   * Add the Cc: header to the [sb] buffer. This is populated with the contents
   * of [_ccRecipients].
   */
  void _addCc(StringBuffer sb) {
    if (!_ccRecipients.isEmpty) {
      final String cc = _ccRecipients
          .map((recipient) => recipient.render())
          .toList()
          .join(',');
      sb.writeln('Cc: ${cc}');
    }
  }

  /**
   * Add the Date: header to the [sb] buffer.
   */
  void _addDate(StringBuffer sb) {
    sb.writeln(
        'Date: ${new DateFormat('EEE, dd MMM yyyy HH:mm:ss +0000').format(new DateTime.now().toUtc())}');
  }

  /**
   * Add the From: header to the [sb] buffer.
   */
  void _addFrom(StringBuffer sb) {
    sb.writeln('From: ${from.render()}');
  }

  /**
   * Add the HTML part to the [sb] buffer. If [boundary] is set, use that as
   * boundary between parts.
   */
  void _addHtmlPart(StringBuffer sb, [String boundary = '']) {
    String lf = '';
    if (boundary.isNotEmpty) {
      lf = '\n\n';
      sb.writeln('--${boundary}');
    }
    sb.writeln('Content-Type: text/html; charset="${encoding.name}"');
    sb.write('Content-Transfer-Encoding: 7bit\n\n');
    sb.write('${partHtml == null ? '' : partHtml}${lf}');
  }

  /**
   * Add the Message-ID: header to the [sb] buffer.
   */
  void _addMessageId(StringBuffer sb) {
    if (customMessageId.isEmpty) {
      sb.writeln('Message-ID: <$id@$fqdnSendingHost>');
    } else {
      sb.writeln('Message-ID: $customMessageId');
    }
  }

  /**
   * Add the Mime-Version: header to the [sb] buffer.
   */
  void _addMimeVersion(StringBuffer sb) {
    sb.writeln('Mime-Version: 1.0');
  }

  /**
   * Add the Subject: header to the [sb] buffer.
   */
  void _addSubject(StringBuffer sb) {
    if (subject != null && subject.isNotEmpty) {
      final String b64 =
          CryptoUtils.bytesToBase64(UTF8.encode(subject), false, true);
      final List<String> b64List = b64.split('\r\n');
      sb.writeln(
          'Subject: ${b64List.map((value) => '=?utf-8?B?${value}?=').join('\r\n ')}');
    }
  }

  /**
   * Add the text part to the [sb] buffer. If [boundary] is set, use that as
   * boundary between parts.
   */
  void _addTextPart(StringBuffer sb, [String boundary = '']) {
    String lf = '';
    if (boundary.isNotEmpty) {
      lf = '\n\n';
      sb.writeln('--${boundary}');
    }
    sb.writeln('Content-Type: text/plain; charset="${encoding.name}"');
    sb.write('Content-Transfer-Encoding: 7bit\n\n');
    sb.write('${partText == null ? '' : partText}${lf}');
  }

  /**
   * Add the To: header to the [sb] buffer. This is populated with the contents
   * of [_tocRecipients].
   */
  void _addTo(StringBuffer sb) {
    if (!_toRecipients.isEmpty) {
      final String to = _toRecipients
          .map((recipient) => recipient.render())
          .toList()
          .join(',');
      sb.write('To: ${to}\n');
    }
  }

  /**
   * Add the x-Mailer: header to the [sb] buffer.
   */
  void _addXHeader(StringBuffer sb) {
    _xHeaders.forEach((String key, String value) {
      sb.writeln('X-$key: $value');
    });
  }

  /**
   * Add the x-Mailer: header to the [sb] buffer.
   */
  void _addXMailer(StringBuffer sb) {
    sb.writeln('X-Mailer: Dart Emailer library');
  }

  /**
   * Add [bccList] to [_recipients].
   */
  set bcc(List<Address> bccList) {
    _recipients.addAll(bccList);
  }

  /**
   * Add [ccList] to [_ccRecipients] and to [_recipients].
   */
  set cc(List<Address> ccList) {
    _ccRecipients.addAll(ccList);
    _recipients.addAll(ccList);
  }

  /**
   * Create a boundary string. Calling this several times will always return
   * different boundary strings.
   */
  String _getBoundary() =>
      '${identityString}_${new DateTime.now().millisecondsSinceEpoch}_${++_counter}';

  /**
   * Returns the email data.
   */
  String getData() {
    final StringBuffer buffer = new StringBuffer();
    final EmailKind emailKind = _getEmailKind();

    _addMessageId(buffer);
    _addDate(buffer);
    _addMimeVersion(buffer);
    _addXHeader(buffer);
    _addXMailer(buffer);
    _addSubject(buffer);
    _addFrom(buffer);
    _addTo(buffer);
    _addCc(buffer);

    switch (emailKind) {
      case EmailKind.empty:

        /// Nothing to do! So easy. :o)
        break;

      case EmailKind.text:
        _addTextPart(buffer);
        break;

      case EmailKind.html:
        _addHtmlPart(buffer);
        break;

      case EmailKind.textHtml:
        final String boundary = _getBoundary();

        buffer.write(
            'Content-Type: multipart/alternative; boundary="${boundary}"\n\n');

        _addTextPart(buffer, boundary);
        _addHtmlPart(buffer, boundary);

        buffer.write('--${boundary}--');
        break;

      case EmailKind.textAttach:
        final String boundary = _getBoundary();

        buffer
            .write('Content-Type: multipart/mixed; boundary="${boundary}"\n\n');

        _addTextPart(buffer, boundary);
        _addAttachments(buffer, boundary);

        buffer.write('--${boundary}--');

        break;

      case EmailKind.htmlAttach:
        final String boundary = _getBoundary();

        buffer
            .write('Content-Type: multipart/mixed; boundary="${boundary}"\n\n');

        _addHtmlPart(buffer, boundary);
        _addAttachments(buffer, boundary);

        buffer.write('--${boundary}--');

        break;

      case EmailKind.textHtmlAttach:
        final String outerBoundary = _getBoundary();
        final String innerBoundary = _getBoundary();

        buffer.write(
            'Content-Type: multipart/mixed; boundary="${outerBoundary}"\n\n');

        buffer.write('--${outerBoundary}\n');
        buffer.write(
            'Content-Type: multipart/alternative; boundary="${innerBoundary}"\n\n');

        _addTextPart(buffer, innerBoundary);
        _addHtmlPart(buffer, innerBoundary);

        buffer.write('--${innerBoundary}--\n\n');

        _addAttachments(buffer, outerBoundary);

        buffer.write('--${outerBoundary}--');
        break;
    }

    buffer.write('\n\r\n.'); // Note. the \r actually needs to be there.
    return buffer.toString();
  }

  /**
   * This figures out what kind of email we're trying to send.
   */
  EmailKind _getEmailKind() {
    if (partText != null && partHtml == null && attachments.isEmpty) {
      return EmailKind.text;
    }

    if (partText == null && partHtml != null && attachments.isEmpty) {
      return EmailKind.html;
    }

    if (partText != null && partHtml != null && attachments.isEmpty) {
      return EmailKind.textHtml;
    }

    if (partText == null && partHtml == null && attachments.isNotEmpty) {
      /// This case can be handled in many ways. The most simple seems to be to
      /// just create a TextAttach email with an empty partText.
      return EmailKind.textAttach;
    }

    if (partText != null && partHtml == null && attachments.isNotEmpty) {
      return EmailKind.textAttach;
    }

    if (partText == null && partHtml != null && attachments.isNotEmpty) {
      return EmailKind.htmlAttach;
    }

    if (partText != null && partHtml != null && attachments.isNotEmpty) {
      return EmailKind.textHtmlAttach;
    }

    return EmailKind.empty;
  }

  /**
   * Get the list of recipient [Address] objects. This includes To, Cc and Bcc
   * recipients.
   */
  List<Address> get recipients => _recipients;

  /**
   * Add [toList] to [_toRecipients] and to [_recipients].
   */
  set to(List<Address> toList) {
    _toRecipients.addAll(toList);
    _recipients.addAll(toList);
  }

  /**
   * Add X header [headerName] with [headerValue] to this email.
   *
   * NOTE: Does NOT do any kind of encoding on the given values.
   *
   * Usage:
   *  xHeader('Foo', 'bar');
   * Adds 'X-Foo: bar' to the email.
   */
  void xHeader(String headerName, String headerValue) {
    _xHeaders[headerName] = headerValue;
  }
}

/**
 * Return the BASE64 for [input]. Expects input to be UTF-8.
 */
String _encode(String input) =>
    '=?utf-8?B?${CryptoUtils.bytesToBase64(UTF8.encode(input))}?=';

/**
 * Return an id constructed from a epoch timestamp and a random 32 bit number.
 */
String get id {
  final int now = new DateTime.now().microsecondsSinceEpoch;
  final int random1 = new Random(now).nextInt((1 << 32) - 1);
  return '$random1$now';
}
