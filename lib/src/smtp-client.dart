library emailer.smtpclient;

import 'dart:async';
import 'dart:io';

import 'email.dart';
import 'smtp-options.dart';

import 'package:cryptoutils/cryptoutils.dart';
import 'package:logging/logging.dart';

typedef void SmtpResponseAction(String message);

/**
 * A SMTP client for sending emails.
 */
class SmtpClient {
  Socket             _connection;
  SmtpResponseAction _currentAction;
  Email              _email;
  final Logger       _logger                   = new Logger('Emailer');
  StreamController   _onIdleController         = new StreamController();
  StreamController   _onSendController         = new StreamController();
  final SmtpOptions  _options;
  int                _recipientIndex           = 0;
  final List<int>    _remainder                = [];
  final List<String> _supportedAuthentications = [];

  /**
   * Constructor.
   *
   * Set [logLevel] to [Level.OFF] to disable SMTP logging.
   */
  SmtpClient(this._options, {Level logLevel: Level.ALL}) {
    hierarchicalLoggingEnabled = true;
    _logger.level = logLevel;
  }

  /**
   * Check that authentication went well, and if so, go idle.
   */
  void _actionAuthenticateComplete(String message) {
    if(message.startsWith('2') == false) {
      throw 'Invalid login: ${message}';
    }

    _currentAction = _actionIdle;
    _onIdleController.add(true);
  }

  /**
   * Send the [_options.username] to the server.
   */
  void _actionAuthenticateLoginUser(String message) {
    if(message.startsWith('334 VXNlcm5hbWU6') == false) {
      throw 'Invalid logic sequence while waiting for "334 VXNlcm5hbWU6": ${message}';
    }

    _currentAction = _actionAuthenticateLoginPassword;
    sendCommand(CryptoUtils.bytesToBase64(_options.username.codeUnits));
  }

  /**
   * Send the [_options.password] to the server.
   */
  void _actionAuthenticateLoginPassword(String message) {
    if(message.startsWith('334 UGFzc3dvcmQ6') == false) {
      throw 'Invalid logic sequence while waiting for "334 UGFzc3dvcmQ6": ${message}';
    }

    _currentAction = _actionAuthenticateComplete;
    sendCommand(CryptoUtils.bytesToBase64(_options.password.codeUnits));
  }

  /**
   * If DATA went OK, move on to sending the actual email.
   */
  void _actionData(String message) {
    if(message.startsWith('2') == false && message.startsWith('3') == false) {
      /// The response should be either 354 or 250.
      throw 'DATA command failed: ${message}';
    }

    _currentAction = _actionFinishEmail;
    sendCommand(_email.getData());
  }

  /**
   * Send HELO if EHLO failed. Upgrade to secure socket if supported and add all
   * supported authentication methods to [_supportedAuthentications].
   */
  void _actionEHLO(String message) {
    if(message.startsWith('2') == false) {
      /// EHLO wasn't cool? Let's go with HELO.
      _currentAction = _actionHELO;
      sendCommand('HELO ${_options.name}');
      return;
    }

    if(_connection is! SecureSocket && new RegExp('[ \\-]STARTTLS\\r?\$', caseSensitive: false, multiLine: true).hasMatch(message)) {
      /// The server supports TLS and we haven't switched to it yet, so let's do it.
      sendCommand('STARTTLS');
      _currentAction = _actionStartTLS;
      return;
    }

    final String AUTH = 'AUTH(?:\\s+[^\\n]*\\s+|\\s+)';
    _addAuthentications('PLAIN', new RegExp('${AUTH}PLAIN', caseSensitive: false), message);
    _addAuthentications('LOGIN', new RegExp('${AUTH}LOGIN', caseSensitive: false), message);
    _addAuthentications('CRAM-MD5', new RegExp('${AUTH}CRAM-MD5', caseSensitive: false), message);
    _addAuthentications('XOAUTH', new RegExp('${AUTH}XOAUTH', caseSensitive: false), message);
    _addAuthentications('XOAUTH2', new RegExp('${AUTH}XOAUTH2', caseSensitive: false), message);

    _authenticateUser();
  }

  /**
   * Check server greeting and if OK send EHLO.
   */
  void _actionGreeting(String message) {
    if(message.startsWith('220') == false) {
      throw('Invalid greeting from server: ${message}');
    }

    _currentAction = _actionEHLO;
    sendCommand('EHLO ${_options.name}');
  }

  /**
   * If HELO is accepted, move on to authenticate user.
   */
  void _actionHELO(String message) {
    if(message.startsWith('2') == false) {
      throw('Invalid response for EHLO/HELO: ${message}');
    }

    _authenticateUser();
  }

  /**
   * If sending the email DATA went OK, move on to closing the connection.
   */
  _actionFinishEmail(String message) {
    if(message.startsWith('2') == false) {
      throw 'Could not send email: ${message}';
    }

    _currentAction = _actionIdle;
    _onSendController.add(_email);
    _email = null;
    _close();
  }

  /**
   * Calling this is actually an error condition, either of the known or unknown
   * kind.
   */
  void _actionIdle(String message) {
    if(int.parse(message.substring(0, 1)) > 3) {
      throw 'Error: ${message}';
    }

    throw 'We should never get here -- bug? Message: ${message}';
  }

  /**
   * If MAIL FROM succeeded send the RCPT TO: commands.
   */
  void _actionMail(String message) {
    if(message.startsWith('2') == false) {
      throw 'MAIL FROM command failed: ${message}';
    }

    Address recipient;

    if(_recipientIndex == _email.recipients.length - 1) {
      /// We are processing the last recipient.
      _recipientIndex = 0;

      _currentAction = _actionRecipient;
      recipient = _email.recipients[_recipientIndex];
    } else {
      /// There are more recipients to process. We need to send RCPT TO multiple
      /// times.
      _currentAction = _actionMail;
      recipient = _email.recipients[++_recipientIndex];
    }

    sendCommand('RCPT TO:<${recipient.addrSpec}>');
  }

  /**
   * If RCPT TO: commands went OK, move on to DATA.
   */
  void _actionRecipient(String message) {
    if(message.startsWith('2') == false) {
      throw('Recipient failure: ${message}');
    }

    _currentAction = _actionData;
    sendCommand('DATA');
  }

  /**
   * Upgrade connection if STARTTLS succeeded.
   */
  void _actionStartTLS(String message) {
    if(message.startsWith('2') == false) {
      _currentAction = _actionHELO;
      sendCommand('HELO ${_options.name}');
      return;
    }

    _upgradeConnection();
  }

  /**
   * Add the [kind] authentication to [_supportedAuthentications] if [regex] is
   * found in [message].
   */
  void _addAuthentications(String kind, RegExp regex, String message) {
    if(regex.hasMatch(message)) {
      _supportedAuthentications.add(kind);
    }
  }

  /**
   * Try to authenticate the [_options.username] user. Send the AUTH LOGIN
   * command.
   */
  void _authenticateUser() {
    if(_options.username == null) {
      _currentAction = _actionIdle;
      _onIdleController.add(true);
      return;
    }

    _currentAction = _actionAuthenticateLoginUser;
    sendCommand('AUTH LOGIN');
  }

  /**
   * Closes the connection.
   */
  void _close() {
    _connection.close();
  }

  /**
   * Initializes a connection to the given server.
   */
  Future _connect() {
    return new Future(() {
      /// Secured connection was demanded by the user.
      if(_options.secure) {
        return SecureSocket.connect(_options.hostName,
                                    _options.port,
                                    onBadCertificate: (_) => _options.ignoreBadCertificate);
      }

      return Socket.connect(_options.hostName, _options.port);
    }).then((socket) {
      _logger.finer("Connecting to ${_options.hostName} at port ${_options.port}.");

      _connection = socket;
      _connection.listen(_onData, onError: _onSendController.addError);
      _connection.done.catchError(_onSendController.addError);
    });
  }

  /**
   * This [onData] handler reads the message that the server sent us.
   */
  void _onData(List<int> chunk) {
    if(chunk == null || chunk.length == 0) {
      return;
    }

    _remainder.addAll(chunk);

    if(_remainder.last != 0x0A) {
      /// If the message comes in pieces, it does not end with \n.
      return;
    }

    final String message = new String.fromCharCodes(_remainder);

    if(new RegExp(r'(?:^|\n)\d{3}-[^\n]+\n$').hasMatch(message)) {
      /// A multi line reply, wait until ending.
      return;
    }

    _remainder.clear();

    _logger.fine(message);

    if(_currentAction != null) {
      try {
        _currentAction(message);
      } catch (e) {
        _onSendController.addError(e);
      }
    }
  }

  /**
   * Fires [true] when the connection is ready to consume a message.
   */
  Stream<bool> get onIdle => _onIdleController.stream.asBroadcastStream();

  /**
   * Fires when an [Email] has been sent.
   */
  Stream<Email> get onSend => _onSendController.stream.asBroadcastStream();

  /**
   * Send the [email].
   */
  Future send(Email email) {
    return new Future(() {
      onIdle.listen((_) {
        _currentAction = _actionMail;
        sendCommand('MAIL FROM:<${email.from.addrSpec}>');
      });

      _email = email;
      _currentAction = _actionGreeting;

      return _connect().then((_) {
        final Completer completer = new Completer();

        final Timer timeout = new Timer(const Duration(seconds: 60), () {
          _close();
          completer.completeError('Timed out sending an email.');
        });

        onSend.listen((Email sentEmail) {
          if(sentEmail == email) {
            timeout.cancel();
            completer.complete(true);
          }
        }, onError: (error) {
          _close();
          timeout.cancel();
          completer.completeError('Failed to send an email: ${error}');
        });

        return completer.future;
      });
    });
  }

  /**
   * Sends a command to the SMTP server.
   */
  void sendCommand(String command) {
    _logger.fine('> ${command}');
    _connection.write('${command}\r\n');
  }

  /**
   * Upgrades the connection to use TLS.
   */
  void _upgradeConnection() {
    SecureSocket.secure(_connection, onBadCertificate: (_) => _options.ignoreBadCertificate)
      .then((SecureSocket secured) {
        _connection = secured;
        _connection.listen(_onData, onError: _onSendController.addError);
        _connection.done.catchError(_onSendController.addError);

        _currentAction = _actionEHLO;
        sendCommand('EHLO ${_options.name}');
      });
  }
}
