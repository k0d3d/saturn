import struct
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def first_row(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    position = 8
    idat = bytearray()
    width = height = depth = color = interlace = None
    while position < len(data):
        length = int.from_bytes(data[position:position + 4], "big")
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
    assert depth == 8 and color == 6 and interlace == 0, "mark must be 8-bit RGBA PNG"
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    assert len(raw) > stride
    filt = raw[0]
    source = raw[1:stride + 1]
    result = bytearray(stride)
    previous = bytearray(stride)
    for i in range(stride):
        value = source[i]
        left = result[i - 4] if i >= 4 else 0
        above = previous[i]
        upper_left = previous[i - 4] if i >= 4 else 0
        if filt == 0:
            result[i] = value
        elif filt == 1:
            result[i] = (value + left) & 255
        elif filt == 2:
            result[i] = (value + above) & 255
        elif filt == 3:
            result[i] = (value + (left + above) // 2) & 255
        elif filt == 4:
            p = left + above - upper_left
            distances = (abs(p - left), abs(p - above), abs(p - upper_left))
            predictor = (left, above, upper_left)[distances.index(min(distances))]
            result[i] = (value + predictor) & 255
        else:
            raise AssertionError("unsupported PNG filter")
    return width, result


class BrandMarkTests(unittest.TestCase):
    def test_png_mark_has_a_transparent_background(self):
        width, row = first_row(ROOT / "assets" / "saturn.png")
        self.assertEqual(row[3], 0)
        self.assertEqual(row[(width - 1) * 4 + 3], 0)

    def test_svg_mark_has_no_full_canvas_backdrop(self):
        svg = (ROOT / "assets" / "saturn.svg").read_text()
        self.assertNotIn("M 0 0 L 2048 0 L 2048 2048 L 0 2048 L 0 0 z", svg)


if __name__ == "__main__":
    unittest.main()
