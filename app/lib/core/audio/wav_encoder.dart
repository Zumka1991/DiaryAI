import 'dart:typed_data';

Uint8List pcm16ToWav({
  required List<Uint8List> chunks,
  required int sampleRate,
  required int channels,
}) {
  final dataSize = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final bytes = BytesBuilder(copy: false);

  bytes.add(_ascii('RIFF'));
  bytes.add(_uint32LE(36 + dataSize));
  bytes.add(_ascii('WAVE'));
  bytes.add(_ascii('fmt '));
  bytes.add(_uint32LE(16)); // PCM fmt chunk size.
  bytes.add(_uint16LE(1)); // PCM audio format.
  bytes.add(_uint16LE(channels));
  bytes.add(_uint32LE(sampleRate));
  bytes.add(_uint32LE(sampleRate * channels * 2));
  bytes.add(_uint16LE(channels * 2));
  bytes.add(_uint16LE(16));
  bytes.add(_ascii('data'));
  bytes.add(_uint32LE(dataSize));
  for (final chunk in chunks) {
    bytes.add(chunk);
  }

  return bytes.toBytes();
}

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

Uint8List _uint16LE(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _uint32LE(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}
