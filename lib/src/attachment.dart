library emailer.attachment;

import 'dart:io';

import 'package:cryptoutils/cryptoutils.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';

/**
 * Represents a single email attachment.
 */
class Attachment {
  List<int> _data;
  File      _file;
  String    _fileName;
  String    _mimeType;

  /**
   * Constructor for attachment based on a list of int.
   */
  Attachment.data(List<int> data, String fileName, String mimeType) {
    _data = data;
    _fileName = fileName;
    _mimeType = mimeType;
  }

  /**
   * Constructor for attachment based on [file].
   */
  Attachment.file(File file) {
    _file = file;
    _fileName = basename(file.path);
    _mimeType = _getMimeType(file.path);
  }

  /**
   * Return the attachment content as a list of integers.
   */
  List<int> get bytes => _data != null ? _data : _file.readAsBytesSync();

  /**
   * Return the attachment content as a Base64 encoded string, broken into 76
   * character blocks, each separated by a "\r\n".
   */
  String get content => _data != null
      ? CryptoUtils.bytesToBase64(_data, false, true)
      : CryptoUtils.bytesToBase64(_file.readAsBytesSync(), false, true);

  /**
   * Return the attachment filename.
   */
  String get fileName => _fileName;

  /**
   * Return the MIME type for [path].
   */
  String _getMimeType(String path) {
    final mtype = lookupMimeType(path);
    return mtype != null ? mtype : 'application/octet-stream';
  }

  /**
   * Return the MIME type for this attachment.
   */
  String get mimeType => _mimeType;
}
