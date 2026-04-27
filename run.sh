#!/bin/bash
echo "🚀 Запуск LUMI·NET..."
cd "$(dirname "$0")"
docker compose down 2>/dev/null
docker compose up --build "$@"
