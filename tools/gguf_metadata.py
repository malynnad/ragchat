#!/usr/bin/env python3
"""读 GGUF 元数据，确认模型的实际维度与池化方式。

为什么需要它：ADR-0016 要把嵌入接进检索，维度写死在代码里，
一旦模型文件选错（比如拿 0.6B 生成模型当嵌入模型），后续阈值和
预算全部作废。与其跑到真机上看报错，不如先读文件头。

用法：
    python3 tools/gguf_metadata.py path/to/model.gguf

只想验维度、不想下 600 MB 时，先抓头部再解析（魔搭/ HF 都支持 Range）：
    curl -L -r 0-41943039 -o /tmp/head.bin '<模型直链>'
    python3 tools/gguf_metadata.py /tmp/head.bin

只读元数据与张量形状，不加载权重。
"""

import struct
import sys

T_U8, T_I8, T_U16, T_I16, T_U32, T_I32, T_F32, T_BOOL, T_STR, T_ARR, T_U64, T_I64, T_F64 = range(13)

# 大数组（词表、合并表）只取长度，不保留内容
MAX_ARRAY_KEEP = 64


class Reader:
    def __init__(self, buf: bytes):
        self.buf = buf
        self.p = 0

    def take(self, n: int) -> bytes:
        if self.p + n > len(self.buf):
            raise EOFError
        b = self.buf[self.p:self.p + n]
        self.p += n
        return b

    def unpack(self, fmt: str):
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))[0]

    def u32(self) -> int:
        return self.unpack("<I")

    def u64(self) -> int:
        return self.unpack("<Q")

    def string(self) -> str:
        return self.take(self.unpack("<Q")).decode("utf-8", "replace")

    def value(self, t: int):
        if t == T_U8:
            return self.unpack("<B")
        if t == T_I8:
            return self.unpack("<b")
        if t == T_U16:
            return self.unpack("<H")
        if t == T_I16:
            return self.unpack("<h")
        if t == T_U32:
            return self.unpack("<I")
        if t == T_I32:
            return self.unpack("<i")
        if t == T_F32:
            return self.unpack("<f")
        if t == T_BOOL:
            return bool(self.unpack("<B"))
        if t == T_STR:
            return self.string()
        if t == T_U64:
            return self.unpack("<Q")
        if t == T_I64:
            return self.unpack("<q")
        if t == T_F64:
            return self.unpack("<d")
        if t == T_ARR:
            et, n = self.unpack("<I"), self.unpack("<Q")
            vals = [self.value(et) for _ in range(n)]
            return vals if n <= MAX_ARRAY_KEEP else f"<array {n} of type {et}>"
        raise ValueError(f"未知类型 {t}")


def main(path: str) -> int:
    with open(path, "rb") as f:
        r = Reader(f.read())

    try:
        magic = r.take(4)
        if magic != b"GGUF":
            print(f"不是 GGUF：magic={magic!r}")
            return 1
        version, tensors, kv_count = r.u32(), r.u64(), r.u64()
        print(f"gguf v{version}  tensors={tensors}  kv={kv_count}")

        for _ in range(kv_count):
            key = r.string()
            t = r.u32()
            val = r.value(t)
            s = str(val)
            if len(s) > 160:
                s = s[:160] + "…"
            print(f"  {key} = {s}")

        print("\n--- tensors ---")
        for _ in range(tensors):
            name = r.string()
            n_dims = r.u32()
            dims = [r.u64() for _ in range(n_dims)]
            ttype, off = r.u32(), r.u64()
            print(f"  {name} dims={dims} type={ttype} off={off}")
    except EOFError:
        print("\n[元数据超出文件范围] 头部没下全，至少要包含 tokenizer 数组；"
              "把 Range 加大（例如 0-41943039）再试。")
        return 2
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
