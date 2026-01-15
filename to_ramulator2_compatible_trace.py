#!/usr/bin/env python3

import re
import argparse

def convert_line(line):
    line = line.strip()
    if not line or line.startswith('#') or line.startswith('//'):
        return None

    match = re.match(r'^(0x[0-9a-fA-F]+|\d+)\s+([RW])$', line)
    if not match:
        return None

    addr, rw = match.groups()
    instr = 'LD' if rw == 'R' else 'ST'

    if addr.startswith('0x') or addr.startswith('0X'):
        return f"{instr} {addr.lower()}"
    else:
        return f"{instr} {int(addr)}"

def main():
    print("start to_ramulator2_compatible_trace.py\n")
    parser = argparse.ArgumentParser(description="Convert Ramulator1 trace (0xADDR R/W) to LD/ST format.")
    parser.add_argument("-i", "--input", required=True, help="Input trace file (Ramulator1 format)")
    parser.add_argument("-o", "--output", required=True, help="Output trace file (LD/ST format)")
    args = parser.parse_args()

    total = 0
    converted = 0
    failed = 0

    with open(args.input, 'r') as fin, open(args.output, 'w') as fout:
        for line in fin:
            total += 1
            res = convert_line(line)
            if res:
                fout.write(res + '\n')
                converted += 1
            else:
                failed += 1

    print(f"[r1_trace_to_ldst] total={total}, converted={converted}, failed={failed}")

if __name__ == "__main__":
    main()

