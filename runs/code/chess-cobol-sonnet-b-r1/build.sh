#!/bin/bash
set -e
cd "$(dirname "$0")"
cobc -x -free -O2 -fnotrunc -o engine_bin src/chess.cob
cat > engine <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/engine_bin" "$@"
EOF
chmod +x engine
