# Emailer

Library for sending email over SMTP. Heavily inspired by and copied from @kaisellgren/mailer

## Example
```dart
import 'emailer.dart';

main() {
  SmtpOptions options = new SmtpOptions()
                              ..hostName = 'smtp.server.dk'
                              ..port = 25;

  SmtpClient smtpClient = new SmtpClient(options);

  Email email = new Email(new Address('from@domain.tld', 'Some From Name'), 'fqdn.somewhere')
      ..attachments.add(new Attachment.file(new File('afile.stuff')))
      ..to = [new Address('to@domain.tld', 'Some To Name')]
      ..bcc = [new Address('bcc@domain.tld', 'Some Bcc Name')]
      ..cc = [new Address('cc@domain.tld', 'Some Cc Name')]
      ..subject = 'Subject!'
      ..partHtml = 'This is <strong>bold</strong>!'
      ..partText = 'This is bold!';

  smtpClient.send(email)
      .then((_) => log.info('\o/'))
      .catchError((e) => log.info('/o\'));
}
```
