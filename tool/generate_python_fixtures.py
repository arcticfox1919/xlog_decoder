"""Execute Mars' Python decoder functions under Python 3.9/3.10.

Only Python 2 syntax/byte conversions and retired dependency APIs are bridged.
Framing, TEA and DecodeBuffer branches execute from the original source file.
Requires cryptography and zstandard; neither is a Dart runtime dependency.
"""
import argparse
import hashlib
import json
import struct
import types
import zlib
from lib2to3.refactor import RefactoringTool, get_fixers_from_package
from pathlib import Path

import zstandard
from cryptography.hazmat.primitives.asymmetric import ec


class LegacyEcc:
    """Bridge pyelliptic's old ECC interface to cryptography's raw ECDH."""

    def __init__(self, curve):
        assert curve == "secp256k1"

    def get_pubkey(self):
        return ec.EllipticCurvePublicNumbers(
            int.from_bytes(self.pubkey_x, "big"),
            int.from_bytes(self.pubkey_y, "big"),
            ec.SECP256K1(),
        ).public_key()

    def get_ecdh_key(self, public_key):
        private = ec.derive_private_key(int.from_bytes(self.privkey, "big"), ec.SECP256K1())
        return private.exchange(ec.ECDH(), public_key)


class LegacyZstd:
    def read_from(self, reader, *sizes):
        yield zstandard.ZstdDecompressor().decompressobj().decompress(reader.buffer)


class LegacyByteArray(bytearray):
    def extend(self, value):
        super().extend(value.encode("utf-8") if isinstance(value, str) else value)


def load_decoder(path):
    source = path.read_text(encoding="utf-8")
    converted = str(RefactoringTool(get_fixers_from_package("lib2to3.fixes"))
                    .refactor_string(source, str(path)))
    converted = (converted
                 .replace("import pyelliptic", "")
                 .replace("import zstandard as zstd", "")
                 .replace("len(v) / 8", "len(v) // 8")
                 .replace("crypt_key_len/2", "crypt_key_len//2")
                 .replace("ret = ''", "ret = b''")
                 .replace("str(buffer(", "bytes(buffer(")
                 .replace("str(tmpbuffer)", "bytes(tmpbuffer)")
                 .replace("str(decompress_data)", "bytes(decompress_data)"))
    namespace = {
        "__name__": "mars_reference",
        "bytearray": LegacyByteArray,
        "buffer": lambda data, offset, size: bytes(data[offset:offset + size]),
        "pyelliptic": types.SimpleNamespace(ECC=LegacyEcc),
        "zstd": types.SimpleNamespace(ZstdDecompressor=LegacyZstd),
    }
    exec(compile(converted, str(path), "exec"), namespace)
    return namespace, hashlib.sha256(source.encode("utf-8")).hexdigest()


def decode(namespace, data):
    data = LegacyByteArray(data)
    output = LegacyByteArray()
    namespace["lastseq"] = 0
    offset = namespace["GetLogStartPos"](data, 2)
    while offset != -1:
        offset = namespace["DecodeBuffer"](data, offset, output)
    return bytes(output)


def legacy_frame(magic, payload):
    return struct.pack("<BHBBI", magic, 1, 9, 10, len(payload)) + bytes(4) + payload + b"\0"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mars-root", type=Path,
                        default=Path(__file__).resolve().parents[3] / "c++/xlog/mars")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    reference = json.loads((project / "test/fixtures/mars_reference.json").read_text())
    crypt_dir = args.mars_root / "xlog/crypt"
    encrypted, crypt_hash = load_decoder(crypt_dir / "decode_mars_crypt_log_file.py")
    plain, plain_hash = load_decoder(crypt_dir / "decode_mars_nocrypt_log_file.py")
    encrypted["PRIV_KEY"] = reference["privateKey"]
    expected = bytes.fromhex(reference["plain"])
    cases = []

    def add(name, data, namespace, key=None):
        output = decode(namespace, data)
        assert output == expected, name
        cases.append(dict(name=name, input=data.hex(), output=output.hex(), privateKey=key))

    for magic, value in reference["modern"].items():
        data = bytes.fromhex(value)
        add("crypt_" + magic, data, encrypted, reference["privateKey"])
        if magic not in ("06", "07", "0a", "0c"):
            add("nocrypt_" + magic, data, plain)

    compressor = zlib.compressobj(wbits=-zlib.MAX_WBITS)
    compressed = compressor.compress(expected) + compressor.flush(zlib.Z_SYNC_FLUSH)
    split = len(compressed) // 2
    chunks = (struct.pack("<H", split) + compressed[:split]
              + struct.pack("<H", len(compressed) - split) + compressed[split:])
    for magic, payload in [(3, expected), (4, compressed), (5, chunks)]:
        data = legacy_frame(magic, payload)
        add("legacy_crypt_%02x" % magic, data, encrypted)
        add("legacy_nocrypt_%02x" % magic, data, plain)

    # A structurally valid candidate followed by garbage must not be the start;
    # ParseFile requires two consecutive frames, or an exact end of file.
    valid = bytes.fromhex(reference["modern"]["08"])
    starts = []
    for name, data, count in [
        ("single_at_eof", valid, 2),
        ("reject_isolated_candidate", valid + b"garbage", 2),
        ("skip_false_candidate", valid + b"garbage" + valid, 2),
        ("recovery_accepts_one", valid + b"garbage", 1),
    ]:
        offset = plain["GetLogStartPos"](LegacyByteArray(data), count)
        starts.append(dict(name=name, input=data.hex(), count=count, offset=offset))

    result = dict(sources={"cryptSha256": crypt_hash, "nocryptSha256": plain_hash},
                  cases=cases, starts=starts)
    target = project / "test/fixtures/python_reference.json"
    target.write_text(json.dumps(result, separators=(",", ":")) + "\n", encoding="utf-8")
    print("Python reference: %d payload cases and %d start searches verified" % (len(cases), len(starts)))


if __name__ == "__main__":
    main()
