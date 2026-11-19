#!/usr/bin/env bash
# Repro: a per-request `thinking_token_budget` degenerates at temperature>0.
# The DSpark TileLang budget kernel forces the reasoning-end marker by setting
# its logit to 1e9. Greedy (temp 0) picks it via argmax and works, but at
# temperature>0 that 1e9 flows into the top-k/top-p softmax where exp(1e9)
# overflows to NaN, masks the whole row, and sampling degenerates to token id 0
# -> the forced </think> never commits, the model loops past its budget, and the
# repetition detector ends the request with empty content.
# Unpatched: finish=repetition, reasoning_tokens pinned at the budget, </think>
#   never emitted (token 128822 count 0), content empty.
# Patched: finish=stop, reasoning cut exactly at the budget, </think> emitted,
#   a real answer follows -- at every temperature, with speculative decoding on.
BASE="${1:-http://127.0.0.1:8000}"; BUDGET="${2:-1500}"
python3 - "$BASE" "$BUDGET" <<'PY'
import json, sys, urllib.request
base, budget = sys.argv[1], int(sys.argv[2])
Q = ("Think step by step about every way an attacker could bypass an Android "
     "WebView host check that only tests Uri.getHost().endsWith(\"example.com\"), "
     "then answer in one short paragraph.")
def run(temp):
    body = {"model": "deepseek-v4.1-flash",
            "messages": [{"role": "user", "content": Q}],
            "max_tokens": 2000, "temperature": temp, "top_p": 0.95,
            "chat_template_kwargs": {"thinking": True, "reasoning_effort": "high"},
            "thinking_token_budget": budget, "return_token_ids": True}
    r = json.load(urllib.request.urlopen(urllib.request.Request(
        base + "/v1/chat/completions", json.dumps(body).encode(),
        {"Content-Type": "application/json"}), timeout=600))
    c = r["choices"][0]; m = c["message"]; tids = m.get("token_ids") or []
    det = r["usage"].get("completion_tokens_details") or {}
    ok = c["finish_reason"] == "stop" and tids.count(128822) >= 1 and bool(m.get("content"))
    print(f"temp={temp}: finish={c['finish_reason']} reasoning_tok={det.get('reasoning_tokens')} "
          f"</think>x{tids.count(128822)} content={'yes' if m.get('content') else 'EMPTY'}  "
          f"=> {'PASS' if ok else 'FAIL'}")
for t in (0.0, 0.7, 1.0):
    run(t)
PY
