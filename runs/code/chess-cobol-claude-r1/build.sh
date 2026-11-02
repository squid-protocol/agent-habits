#!/bin/bash
cd "$(dirname "$0")"
cobc -x -free -O2 -o engine_bin chess.cob || exit 1
cat > engine <<'EOS'
#!/bin/bash
exec "$(dirname "$(readlink -f "$0")")/engine_bin"
EOS
chmod +x engine
