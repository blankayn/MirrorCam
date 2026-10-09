"""Read-only static analysis of the official Iris12 0.0.2 package; never loads its code."""
from pathlib import Path
import hashlib
import io
import json
import plistlib
import re
import struct
import tarfile
import urllib.request

root = Path(__file__).resolve().parents[1] / "build/iris12-analysis"
root.mkdir(parents=True, exist_ok=True)
url = "https://michaelmelita1.github.io/debs/com.michaelmelita1.iris12_0.0.2_iphoneos-arm.deb"
expected = "afcbd6936c732eba284fffc22fc6ce1f552e1c8a678bda53b5b05c44c1904282"
package = urllib.request.urlopen(url, timeout=30).read()
assert hashlib.sha256(package).hexdigest() == expected, "Unexpected package version/hash"
assert package.startswith(b"!<arch>\n"), "Not a Debian ar archive"
offset = 8
control = None
filter_info = None
binary = None
while offset + 60 <= len(package):
    header = package[offset:offset + 60]
    offset += 60
    name = header[:16].decode().strip().rstrip("/")
    size = int(header[48:58])
    content = package[offset:offset + size]
    offset += size + size % 2
    if not name.startswith(("control.tar", "data.tar")):
        continue
    with tarfile.open(fileobj=io.BytesIO(content), mode="r:*") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            data = archive.extractfile(member).read()
            if member.name.endswith("/control") or member.name == "control":
                control = data.decode()
            elif member.name.endswith("iris.plist"):
                filter_info = plistlib.loads(data)
            elif member.name.endswith("iris.dylib"):
                binary = data
assert binary is not None and filter_info is not None
magic, count = struct.unpack_from(">II", binary)
if magic == 0xCAFEBABE:
    slices = [struct.unpack_from(">IIIII", binary, 8 + i * 20) for i in range(count)]
    _, _, offset, size, _ = next(s for s in slices if s[0] == 0x0100000C)
    binary = binary[offset:offset + size]
assert struct.unpack_from("<I", binary)[0] == 0xFEEDFACF, "Expected arm64 Mach-O"
commands = struct.unpack_from("<I", binary, 16)[0]
offset = 32
sections = {}
section_records = {}
symbol_table = None
indirect_table = None
for _ in range(commands):
    command, size = struct.unpack_from("<II", binary, offset)
    if command == 0x19:
        section_count = struct.unpack_from("<I", binary, offset + 64)[0]
        for index in range(section_count):
            record = struct.unpack_from("<16s16sQQIIIIIIII", binary, offset + 72 + index * 80)
            name = record[0].rstrip(b"\0").decode()
            sections[name] = (record[2], record[3], record[4])
            section_records[name] = record
    elif command == 0x2:  # LC_SYMTAB
        symbol_table = struct.unpack_from("<IIII", binary, offset + 8)
    elif command == 0xB:  # LC_DYSYMTAB
        indirect_table = struct.unpack_from("<II", binary, offset + 56)
    offset += size
address, size, offset = sections["__text"]
code = binary[offset:offset + size]
# arm64 little-endian encodings for `mov w0, #1; ret`.
constant_true = [address + m.start() for m in re.finditer(re.escape(bytes.fromhex("20008052c0035fd6")), code)]


def bytes_at(virtual_address, length):
    """Translate a virtual address through file-backed sections, without loading code."""
    for name, (base, section_size, file_offset) in sections.items():
        if name == "__bss":
            continue
        if base <= virtual_address and virtual_address + length <= base + section_size:
            begin = file_offset + virtual_address - base
            return binary[begin:begin + length]
    raise AssertionError(f"Address {virtual_address:#x} is not file-backed")


def cstring_at(virtual_address):
    for name in ("__cstring", "__objc_methname"):
        base, section_size, file_offset = sections[name]
        if base <= virtual_address < base + section_size:
            tail = binary[file_offset + virtual_address - base:file_offset + section_size]
            return tail.split(b"\0", 1)[0].decode("utf-8")
    raise AssertionError(f"Address {virtual_address:#x} is not a class/method string")


def signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


assert symbol_table is not None and indirect_table is not None
symbol_offset, symbol_count, string_offset, string_size = symbol_table
symbol_names = []
imports = []
for index in range(symbol_count):
    string_index, symbol_type, _, _, _ = struct.unpack_from("<IBBHQ", binary, symbol_offset + index * 16)
    assert string_index < string_size
    symbol_name = binary[string_offset + string_index:string_offset + string_size].split(b"\0", 1)[0].decode()
    symbol_names.append(symbol_name)
    if symbol_type & 0x0E == 0 and symbol_type & 0x01:
        imports.append(symbol_name)

indirect_offset, indirect_count = indirect_table
indirect_symbols = struct.unpack_from(f"<{indirect_count}I", binary, indirect_offset)
stub_record = section_records["__stubs"]
stub_address, stub_size, stub_stride = stub_record[2], stub_record[3], stub_record[10]
assert stub_stride > 0 and stub_size % stub_stride == 0
stubs = {}
for index in range(stub_size // stub_stride):
    symbol_index = indirect_symbols[stub_record[9] + index]
    assert symbol_index < len(symbol_names), "Expected imported symbol for each stub"
    stubs[stub_address + index * stub_stride] = symbol_names[symbol_index]

init_address, init_size, init_offset = sections["__mod_init_func"]
assert init_size == 8, "Expected one arm64 constructor"
constructor = struct.unpack_from("<Q", binary, init_offset)[0]
assert address <= constructor < min(constant_true)
registers = {}
observed_hooks = []
instruction_trace = []
# This deliberately supports only the instructions used by the pinned package.
# Unknown opcodes fail closed instead of silently claiming a general disassembly.
stack_instructions = {0xA9BE4FF4, 0xA9017BFD, 0x910043FD, 0xA9417BFD, 0xA8C24FF4}
for pc in range(constructor, min(constant_true), 4):
    word = struct.unpack("<I", bytes_at(pc, 4))[0]
    if word == 0xD503201F or word in stack_instructions:
        continue
    if word & 0x9F000000 == 0x10000000:  # ADR Xd, signed PC-relative address
        immediate = signed(((word >> 5) & 0x7FFFF) << 2 | ((word >> 29) & 3), 21)
        destination = word & 31
        registers[destination] = pc + immediate
        instruction_trace.append(f"{pc:#x}: ADR x{destination}, {pc + immediate:#x}")
    elif word & 0xFF000000 == 0x58000000:  # LDR Xt, literal pointer
        pointer_address = pc + signed((word >> 5) & 0x7FFFF, 19) * 4
        destination = word & 31
        registers[destination] = struct.unpack("<Q", bytes_at(pointer_address, 8))[0]
        instruction_trace.append(f"{pc:#x}: LDR x{destination}, [{pointer_address:#x}]")
    elif word & 0xFFE0FFE0 == 0xAA0003E0:  # MOV Xd, Xm (ORR alias)
        destination, source = word & 31, (word >> 16) & 31
        assert source in registers
        registers[destination] = registers[source]
        instruction_trace.append(f"{pc:#x}: MOV x{destination}, x{source}")
    elif word & 0xFC000000 in (0x94000000, 0x14000000):  # BL or tail B
        target = pc + signed(word & 0x03FFFFFF, 26) * 4
        assert target in stubs, f"Unknown branch target {target:#x}"
        function = stubs[target]
        instruction_trace.append(f"{pc:#x}: {'BL' if word & 0xFC000000 == 0x94000000 else 'B'} {function} ({target:#x})")
        if function == "_objc_getClass":
            assert isinstance(registers.get(0), int)
            result = {"class": cstring_at(registers[0])}
        elif function == "_MSHookMessageEx":
            assert isinstance(registers.get(0), dict) and isinstance(registers.get(1), int)
            assert registers.get(2) in constant_true, "Replacement is not the verified constant-YES function"
            observed_hooks.append({
                "class": registers[0]["class"],
                "selector": cstring_at(registers[1]),
                "replacement_address": hex(registers[2]),
                "original_imp_slot": hex(registers[3]),
                "hook_call_address": hex(pc),
                "replacement_instructions": "mov w0, #1; ret",
            })
            result = None
        else:
            raise AssertionError(f"Unexpected constructor call {function}")
        # Calls may clobber x0-x18; callee-saved x19 keeps the class object.
        for register in range(19):
            registers.pop(register, None)
        if result is not None:
            registers[0] = result
    else:
        raise AssertionError(f"Unsupported constructor opcode {word:#010x} at {pc:#x}")

assert len(observed_hooks) == len(constant_true) == 3
assert {int(hook["replacement_address"], 16) for hook in observed_hooks} == set(constant_true)
report = {
    "source": url,
    "sha256": expected,
    "control": control,
    "filter": filter_info,
    "classes": list(dict.fromkeys(hook["class"] for hook in observed_hooks)),
    "selectors": [hook["selector"] for hook in observed_hooks],
    "imports": imports,
    "constructor_address": hex(constructor),
    "observed_hooks": observed_hooks,
    "constructor_instruction_trace": instruction_trace,
    "arm64_code_size": size,
    "constant_true_function_addresses": [hex(value) for value in constant_true],
}
assert len(constant_true) == 3
(root / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
