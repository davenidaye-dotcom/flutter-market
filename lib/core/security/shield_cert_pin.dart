import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 正式包只核对源站证书的公钥指纹，不保存、不发送域名。
/// 指纹是 SubjectPublicKeyInfo 的 SHA-256，64 位小写十六进制。
/// 空字符串表示还没填，握手一律拒绝。
const shieldSpkiSha256 =
    '17723aa234db44a43fd4062eb68c0cc49bca8de82c317317e13666e10ea40a4c';

bool shieldCertPinMatches(List<int> certDer) {
  final expect = shieldSpkiSha256.trim().toLowerCase();
  if (expect.length != 64) return false;
  final got = sha256.convert(subjectPublicKeyInfoDer(certDer)).toString();
  if (got.length != expect.length) return false;
  var diff = 0;
  for (var i = 0; i < got.length; i++) {
    diff |= got.codeUnitAt(i) ^ expect.codeUnitAt(i);
  }
  return diff == 0;
}

/// 从证书 DER 取出 SubjectPublicKeyInfo 的完整编码（含 tag 和 length）。
List<int> subjectPublicKeyInfoDer(List<int> certDer) {
  final cert = _read(certDer, 0);
  if (cert.tag != 0x30) {
    throw const FormatException('certificate');
  }
  final top = _Cursor(cert.value);
  final tbs = top.read();
  if (tbs.tag != 0x30) {
    throw const FormatException('tbsCertificate');
  }
  final body = _Cursor(tbs.value);
  final first = body.read();
  if (first.tag != 0xA0) {
    // 没有显式 version 时，first 已是 serialNumber，后面再跳 4 个字段。
    for (var i = 0; i < 4; i++) {
      body.read();
    }
  } else {
    for (var i = 0; i < 5; i++) {
      body.read();
    }
  }
  final spki = body.read();
  if (spki.tag != 0x30) {
    throw const FormatException('subjectPublicKeyInfo');
  }
  return spki.full;
}

class _Asn {
  _Asn(this.tag, this.full, this.value);

  final int tag;
  final Uint8List full;
  final Uint8List value;
}

class _Cursor {
  _Cursor(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  int _i = 0;

  _Asn read() => _read(_bytes, _i, onNext: (next) => _i = next);
}

_Asn _read(List<int> bytes, int offset, {void Function(int next)? onNext}) {
  var i = offset;
  if (i >= bytes.length) {
    throw const FormatException('truncated');
  }
  final tag = bytes[i++];
  if (i >= bytes.length) {
    throw const FormatException('truncated');
  }
  var length = bytes[i++];
  if (length & 0x80 != 0) {
    final count = length & 0x7f;
    if (count == 0 || count > 3 || i + count > bytes.length) {
      throw const FormatException('length');
    }
    length = 0;
    for (var n = 0; n < count; n++) {
      length = (length << 8) | bytes[i++];
    }
  }
  if (i + length > bytes.length) {
    throw const FormatException('truncated');
  }
  final next = i + length;
  onNext?.call(next);
  return _Asn(
    tag,
    Uint8List.fromList(bytes.sublist(offset, next)),
    Uint8List.fromList(bytes.sublist(i, next)),
  );
}
