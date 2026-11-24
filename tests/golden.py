#!/usr/bin/env python3
"""Golden tests: compare mq (native binary) against jq 1.7.
Compares parsed JSON values (not raw text), so number formatting
differences like 1.0 vs 1 do not count as failures.
Run: python3 tests/golden.py [path-to-mq]
Exit 0 if all pass.
"""
import json, subprocess, sys

MQ = sys.argv[1] if len(sys.argv) > 1 else "_build/native/debug/build/main/main.exe"

CASES = [
    ('{"name":"Yan","score":95}', ".name"),
    ('{"users":[{"name":"a"},{"name":"b"}]}', ".users[].name"),
    ("[1,2,3]", ".[]"),
    ("[3,1,2]", "sort"),
    ('{"a":1}', ".a + 1"),
    ("[1,2,3]", "map(. * 2)"),
    ("[1,2,3,4]", "map(select(. > 2))"),
    ('{"a":null}', '.a // "x"'),
    ('{"a":5}', 'if .a > 3 then "big" else "small" end'),
    ("[3,1,2]", "sort_by(.)"),
    ("[1,2,2,3,1]", "unique"),
    ("[1,2,3]", "add"),
    ("[5,2,9]", "min"),
    ("[5,2,9]", "max"),
    ('{"b":2,"a":1}', "keys"),
    ('{"a":1}', "{b: .a, c: 2}"),
    ("[1,2]", "[.[] + 10]"),
    ('"hello"', "length"),
    ('"hello"', '. + "!"'),
    ("5", ". * 2 + 1"),
    ('{"a":{"b":42}}', ".a.b"),
    ("[1,2,3]", ".[1]"),
    ("[1,2,3]", ".[-1]"),
    ('{"a":true}', ".a and true"),
    ('{"a":true}', ".a or false"),
    ("42", "type"),
    ('"x"', "type"),
    ("[]", "type"),
    ("null", "type"),
    ("42", "tostring"),
    ('"42"', "tonumber"),
    ("[1,2,3]", ".[] | select(. % 2 == 1)"),
    ('{"score":85}', "select(.score >= 90)"),
    ('{"name":"Yan"}', '.missing // "none"'),
    ("[10,20]", ".[] * 2"),
    ('{"a":[1,2]}', ".a | length"),
    ("1", "1 + 2 * 3"),
    ('{"x":1}', ".x == 1"),
    ('{"x":1}', ".x != 1"),
    ('{"x":1}', ".x < 2"),
    ("[1,2,3]", ".[0:2]"),
    ("[0,1,2,3,4]", ".[1:3]"),
    ("[0,1,2,3,4]", ".[2:]"),
    ("[0,1,2,3,4]", ".[:2]"),
    ("[0,1,2,3,4]", ".[-2:]"),
    ("[0,1,2,3,4]", ".[:-1]"),
    ("[0,1,2,3,4]", ".[10:20]"),
    ("[0,1,2,3,4]", ".[-10:2]"),
    ("[0,1,2,3,4]", ".[3:1]"),
    ('"abcdef"', ".[1:3]"),
    ('"abcdef"', ".[-2:]"),
    ("[0,1,2,3]", ".[1:null]"),
    ("[0,1,2,3]", ".[null:2]"),
    ("[0,1,2,3]", ".[0:1+1]"),
    ("[0,1,2,3]", ".[1.5:3]"),
    ("[0,1,2,3]", ".[-1.5:3]"),
    ("null", ".[0:1]"),
    ("[0,1,2,3]", ".[0:length]"),
    ('{"a":1,"b":2}', ".a, .b"),
    ('{"a":1}', ".a // 2 | . + 10"),
    ("[2,1]", "sort | .[]"),
    ('"a,b,c"', 'split(",")'),
    ('"a,b,c"', 'split("")'),
    ('"a,b,c"', 'split("x")'),
    ('"a,b,"', 'split(",")'),
    ('""', 'split(",")'),
    ('""', 'split("")'),
    ('"a"', 'split("a")'),
    ('"a::b"', 'split("::")'),
    ('{"name":"Yan","score":95}', '"\\(.name) has \\(.score) points"'),
    ('{"a":2}', '"\\(.a + 1) and \\(.a * 10)"'),
    ('null', '"\\(null)|\\(true)|\\([1,2])|\\(.missing)"'),
    ('{"a":1,"b":2}', '"\\(.a, .b)"'),
    ('{"name":"Yan"}', '"outer \\("inner \\(.name)") end"'),
    ('{"a":1}', '{s: "v=\\(.a)"}'),
    ('{"a":1}', '{"\\(.a)": 1}'),
    ('null', '"\\\\(x)"'),
]

def run(cmd, inp):
    r = subprocess.run(cmd, input=inp.encode(), capture_output=True)
    return r.returncode, r.stdout.decode(), r.stderr.decode()

def parse_lines(out):
    vals = []
    for line in out.strip().splitlines():
        if line.strip():
            try:
                vals.append(json.loads(line))
            except json.JSONDecodeError:
                vals.append(("RAW", line))
    return vals

fails = 0
for inp, filt in CASES:
    mq_rc, mq_out, mq_err = run([MQ, filt], inp)
    jq_rc, jq_out, jq_err = run(["jq", "-c", filt], inp)
    mq_vals = parse_lines(mq_out)
    jq_vals = parse_lines(jq_out)
    if mq_rc != 0 or jq_rc != 0:
        # both should fail, or mq fails where jq succeeds = fail
        if mq_rc == 0 and jq_rc == 0:
            pass
        elif mq_rc != 0 and jq_rc != 0:
            print(f"OK (both error): {filt}")
            continue
        else:
            print(f"FAIL rc: input={inp} filter={filt} mq_rc={mq_rc} mq_err={mq_err.strip()} jq_rc={jq_rc} jq_err={jq_err.strip()}")
            fails += 1
            continue
    if mq_vals != jq_vals:
        print(f"FAIL: input={inp} filter={filt}\n  mq: {mq_vals}\n  jq: {jq_vals}")
        fails += 1
    else:
        print(f"OK: {filt} on {inp[:40]} -> {mq_vals}")

print(f"\n{len(CASES)} cases, {fails} failures (excluding SKIPs)")
sys.exit(1 if fails else 0)
