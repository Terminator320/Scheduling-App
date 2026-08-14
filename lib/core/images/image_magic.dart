/// Whether the first bytes of a file match a JPEG or PNG magic signature.
///
/// Extension and MIME type are attacker-controlled, so this is the real format
/// gate on the client side. It is deliberately the same test the server runs.
///
/// **Hand-mirrored** by `hasValidImageMagic` in `functions/image_magic.js`,
/// which is the server-side backstop — `validateUploadedImage` deletes an
/// uploaded object outright when its check fails. The two MUST agree: while
/// they didn't, this side accepted PNG on three bytes (`89 50 4E`) and the
/// server required four (`89 50 4E 47`), so a file starting `89 50 4E` with
/// any other fourth byte passed here, uploaded, and was then deleted
/// server-side as `deleted-invalid` — the user watched a photo upload succeed
/// and silently vanish, with no error on either side.
///
/// Four bytes is the correct half of that pair: `89 50 4E` alone is not the
/// PNG signature (the full one is `89 50 4E 47 0D 0A 1A 0A`).
///
/// The two length guards are asymmetric ON PURPOSE, because that is what the
/// JS does: it reads `b[3]` only on the PNG branch, and an out-of-range read
/// there is `undefined`, which fails the comparison. So a three-byte JPEG
/// prefix is accepted by both and a three-byte PNG prefix is rejected by both.
/// Don't "tidy" this into one `length < 4` check — that would re-open the gap
/// in the other direction.
bool hasValidImageMagic(List<int> bytes) {
  final isJpeg =
      bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  final isPng =
      bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
  return isJpeg || isPng;
}
