library emailer.email;

import 'dart:convert';
import 'dart:math' show Random;

import 'attachment.dart';

import 'package:cryptoutils/cryptoutils.dart';
import 'package:intl/intl.dart';

/**
 * The kinds of emails this library supports.
 */
enum EmailKind {Empty,
                Text,
                Html,
                TextHtml,
                TextAttach,
                HtmlAttach,
                TextHtmlAttach}

/**
 * This class represents an email address. It MUST contain a valid email address
 * (addrSpec) and it MAY contain the display name of the address.
 *
 * See https://tools.ietf.org/html/rfc5322 for more information.
 */
class Address {
  String _addrSpec;
  String _displayName;

  String get addrSpec    => _addrSpec;
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

    if(displayName.isEmpty) {
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
    if(value == null) {
      return '';
    }

    return value.replaceAll(new RegExp('(\\r|\\n|\\t|"|,|<|>)+', caseSensitive: false), '');
  }
}

/**
 * This is class represents an email. Add text/html parts, attachments, subject,
 * recipients, from and then send it using the Smtp.Send function.
 *
 * Recipients are defined as lists of [Address]'s.
 */
class Email {
  final List<Attachment> attachments      = [];
  final List<Address>    _ccRecipients    = [];
  int                    _counter         = 0;
  Encoding               encoding         = UTF8;
  final String           fqdnSendingHost;
  final Address          from;
  final String           identityString   = 'dart-mailer';
  String                 partHtml;
  String                 partText;
  final List<Address>    _recipients      = [];
  String                 subject;
  final List<Address>    _toRecipients    = [];

  /**
   * Constructor.
   *
   * fqdnSendingHost is SHOULD part of the Message-ID: header per RFC 5322. It
   * is recommended to set this to the actual sending host.
   */
  Email(Address this.from, String this.fqdnSendingHost);

  /**
   * Add all the [attachments] to the [sb] buffer, separated by [boundary].
   */
  void _addAttachments(StringBuffer sb, String boundary) {
    attachments.forEach((attachment) {
      sb.write('--${boundary}\n');
      sb.write('Content-Type: ${attachment.mimeType}; name="${attachment.fileName}"\n');
      sb.write('Content-Transfer-Encoding: base64\n');
      sb.write('Content-Disposition: attachment; filename="${attachment.fileName}"\n\n');
      sb.write('${attachment.content}\n\n');
    });
  }

  /**
   * Add the Cc: header to the [sb] buffer. This is populated with the contents
   * of [_ccRecipients].
   */
  void _addCc(StringBuffer sb) {
    if(!_ccRecipients.isEmpty) {
      final String cc = _ccRecipients.map((recipient) => recipient.render()).toList().join(',');
      sb.write('Cc: ${cc}\n');
    }
  }

  /**
   * Add the Date: header to the [sb] buffer.
   */
  void _addDate(StringBuffer sb) {
    sb.write('Date: ${new DateFormat('EEE, dd MMM yyyy HH:mm:ss +0000').format(new DateTime.now().toUtc())}\n');
  }

  /**
   * Add the From: header to the [sb] buffer.
   */
  void _addFrom(StringBuffer sb) {
    sb.write('From: ${from.render()}\n');
  }

  /**
   * Add the HTML part to the [sb] buffer. If [boundary] is set, use that as
   * boundary between parts.
   */
  void _addHtmlPart(StringBuffer sb, [String boundary = '']) {
    String lf = '';
    if(boundary.isNotEmpty) {
      lf = '\n\n';
      sb.write('--${boundary}\n');
    }
    sb.write('Content-Type: text/html; charset="${encoding.name}"\n');
    sb.write('Content-Transfer-Encoding: 7bit\n\n');
    sb.write('${partHtml == null ? '' : partHtml}${lf}');
  }

  /**
   * Add the Message-ID: header to the [sb] buffer.
   */
  void _addMessageId(StringBuffer sb) {
    final int now = new DateTime.now().millisecondsSinceEpoch;
    final int random1 = new Random(now).nextInt((1<<32) - 1);
    final int random2 = new Random(now+1).nextInt((1<<32) - 1);
    final int random3 = new Random(now+2).nextInt((1<<32) - 1);

    sb.write('Message-ID: <${random1}.${random2}.${random3}.${now}@${fqdnSendingHost}>\n');
  }

  /**
   * Add the Mime-Version: header to the [sb] buffer.
   */
  void _addMimeVersion(StringBuffer sb) {
    sb.write('Mime-Version: 1.0\n');
  }

  /**
   * Add the Subject: header to the [sb] buffer.
   */
  void _addSubject(StringBuffer sb) {
    if(subject != null && subject.isNotEmpty) {
      final String b64 = CryptoUtils.bytesToBase64(UTF8.encode(subject), false, true);
      final List<String> b64List = b64.split('\r\n');
      sb.write('Subject: ${b64List.map((value) => '=?utf-8?B?${value}?=').join('\r\n ')}\n');
    }
  }

  /**
   * Add the text part to the [sb] buffer. If [boundary] is set, use that as
   * boundary between parts.
   */
  void _addTextPart(StringBuffer sb, [String boundary = '']) {
    String lf = '';
    if(boundary.isNotEmpty) {
      lf = '\n\n';
      sb.write('--${boundary}\n');
    }
    sb.write('Content-Type: text/plain; charset="${encoding.name}"\n');
    sb.write('Content-Transfer-Encoding: 7bit\n\n');
    sb.write('${partText == null ? '' : partText}${lf}');
  }

  /**
   * Add the To: header to the [sb] buffer. This is populated with the contents
   * of [_tocRecipients].
   */
  void _addTo(StringBuffer sb) {
    if(!_toRecipients.isEmpty) {
      final String to = _toRecipients.map((recipient) => recipient.render()).toList().join(',');
      sb.write('To: ${to}\n');
    }
  }

  /**
   * Add the x-Mailer: header to the [sb] buffer.
   */
  void _addXMailer(StringBuffer sb) {
    sb.write('X-Mailer: Dart Emailer library\n');
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
    _addXMailer(buffer);
    _addSubject(buffer);
    _addFrom(buffer);
    _addTo(buffer);
    _addCc(buffer);

    switch(emailKind) {
      case EmailKind.Empty:
        /// Nothing to do! So easy. :o)
        break;

      case EmailKind.Text:
        _addTextPart(buffer);
        break;

      case EmailKind.Html:
        _addHtmlPart(buffer);
        break;

      case EmailKind.TextHtml:
        final String boundary = _getBoundary();

        buffer.write('Content-Type: multipart/alternative; boundary="${boundary}"\n\n');

        _addTextPart(buffer, boundary);
        _addHtmlPart(buffer, boundary);

        buffer.write('--${boundary}--');
        break;

      case EmailKind.TextAttach:
        final String boundary = _getBoundary();

        buffer.write('Content-Type: multipart/mixed; boundary="${boundary}"\n\n');

        _addTextPart(buffer, boundary);
        _addAttachments(buffer, boundary);

        buffer.write('--${boundary}--');

        break;

      case EmailKind.HtmlAttach:
        final String boundary = _getBoundary();

        buffer.write('Content-Type: multipart/mixed; boundary="${boundary}"\n\n');

        _addHtmlPart(buffer, boundary);
        _addAttachments(buffer, boundary);

        buffer.write('--${boundary}--');

        break;

      case EmailKind.TextHtmlAttach:
        final String outerBoundary = _getBoundary();
        final String innerBoundary = _getBoundary();

        buffer.write('Content-Type: multipart/mixed; boundary="${outerBoundary}"\n\n');

        buffer.write('--${outerBoundary}\n');
        buffer.write('Content-Type: multipart/alternative; boundary="${innerBoundary}"\n\n');

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
    if(partText != null && partHtml == null && attachments.isEmpty) {
      return EmailKind.Text;
    }

    if(partText == null && partHtml != null && attachments.isEmpty) {
      return EmailKind.Html;
    }

    if(partText != null && partHtml != null && attachments.isEmpty) {
      return EmailKind.TextHtml;
    }

    if(partText == null && partHtml == null && attachments.isNotEmpty) {
      /// This case can be handled in many ways. The most simple seems to be to
      /// just create a TextAttach email with an empty partText.
      return EmailKind.TextAttach;
    }

    if(partText != null && partHtml == null && attachments.isNotEmpty) {
      return EmailKind.TextAttach;
    }

    if(partText == null && partHtml != null && attachments.isNotEmpty) {
      return EmailKind.HtmlAttach;
    }

    if(partText != null && partHtml != null && attachments.isNotEmpty) {
      return EmailKind.TextHtmlAttach;
    }

    return EmailKind.Empty;
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
}

/**
 * Return the BASE64 for [input]. Expects input to be UTF-8.
 */
String _encode(String input) =>
    '=?utf-8?B?${CryptoUtils.bytesToBase64(UTF8.encode(input))}?=';
