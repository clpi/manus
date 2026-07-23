import sys

content = open('scripts/run_wasm_benchmark.sh').read()

def replace_ct(match):
    return '        for j in "${!FOUND_RUNTIMES[@]}"; do\n            if [[ "${FOUND_RUNTIMES[$j]}" == "$rt" ]]; then\n                ct=${CURRENT_TIMES[$j]:-0}\n                bt=${BASELINE_TIMES[$j]:-0}\n                break\n            fi\n        done'

content = content.replace('        ct=${CURRENT_TIMES[$rt]:-0}\n        bt=${BASELINE_TIMES[$rt]:-0}', replace_ct(None))

open('scripts/run_wasm_benchmark.sh', 'w').write(content)
