#!/usr/bin/env bash
# Repro: concurrent structured-output (guided JSON) requests overflow the
# grammar-bitmask buffer (max_num_seqs*(1+num_spec)) under DSpark speculative
# decoding -> IndexError in structured_output/_fill_bitmasks -> EngineDeadError.
# Unpatched: engine dies (500s / connection errors + /v1/models stops). Patched: all 200.
BASE="${1:-http://127.0.0.1:8000}"; N="${2:-32}"
req() {
  curl -s -m 120 "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d '{
    "model":"deepseek-v4.1-flash",
    "messages":[{"role":"user","content":"Give 8 prime numbers as JSON."}],
    "max_tokens":256,"temperature":0,
    "chat_template_kwargs":{"thinking":false},
    "response_format":{"type":"json_schema","json_schema":{"name":"primes","schema":{"type":"object","properties":{"primes":{"type":"array","items":{"type":"integer"}}},"required":["primes"],"additionalProperties":false}}}
  }' -o /dev/null -w "%{http_code} "
}
echo "firing $N concurrent guided-JSON requests at $BASE ..."
for i in $(seq 1 "$N"); do req & done; wait
echo; echo "engine alive after burst: $(curl -sf --max-time 8 "$BASE/v1/models" >/dev/null 2>&1 && echo YES || echo NO-ENGINE-DEAD)"
