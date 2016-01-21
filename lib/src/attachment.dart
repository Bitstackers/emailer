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
  File _file;
  String _fileName;
  String _mimeType;

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
