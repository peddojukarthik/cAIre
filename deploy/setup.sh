#!/usr/bin/env bash
# cAIre: Supabase + Vercel setup (no card required for Supabase free tier).
#
# This script handles what CAN be automated. Two steps must be done manually
# in a browser because they require account-level actions with no CLI:
#   1. Creating the Supabase project (supabase.com -> New Project)
#   2. Getting a Google AI Studio API key (aistudio.google.com/apikey)
#
# Run this AFTER you've created the Supabase project and have its connection
# details in hand (Project Settings -> Database, and Project Settings -> API).

set -euo pipefail

echo "==================================================================="
echo "cAIre setup -- Supabase + Vercel"
echo "==================================================================="
echo ""
echo "Before running the rest of this script, make sure you have:"
echo "  1. Created a Supabase project at https://supabase.com (free, no card)"
echo "  2. Got a Google AI Studio API key at https://aistudio.google.com/apikey (free, no card)"
echo ""
read -p "Have you done both of the above? (y/n) " ready
if [ "$ready" != "y" ]; then
  echo "Do those first, then re-run this script."
  exit 1
fi

read -p "Supabase project ref (e.g. abcdefghij from your project URL): " SUPABASE_REF
read -p "Supabase database password (set when you created the project): " -s DB_PASSWORD
echo ""
read -p "Supabase JWT secret (Project Settings > API > JWT Secret): " -s JWT_SECRET
echo ""
read -p "Google AI Studio API key: " GOOGLE_AI_KEY

SUPABASE_URL="https://${SUPABASE_REF}.supabase.co"
DB_HOST="db.${SUPABASE_REF}.supabase.co"

echo ""
echo ">> Generating document-signing key pair (replaces Cloud KMS)"
python3 -c "
from app.services.signing import generate_key_pair_pem
priv, pub = generate_key_pair_pem()
with open('.signing_private_key.pem', 'w') as f:
    f.write(priv)
with open('docs/signing_public_key.pem', 'w') as f:
    f.write(pub)
print('Private key -> .signing_private_key.pem (DO NOT COMMIT -- add to .gitignore)')
print('Public key  -> docs/signing_public_key.pem (safe to commit)')
" 2>/dev/null || {
  echo "Run this from the backend/ directory with dependencies installed."
  echo "Or run it manually: python -m app.services.signing"
}

AADHAAR_SALT=$(openssl rand -hex 32)

echo ""
echo ">> Running schema migration against Supabase"
PGPASSWORD="${DB_PASSWORD}" psql \
  "host=${DB_HOST} port=5432 dbname=postgres user=postgres sslmode=require" \
  -f backend/migrations/001_init_schema.sql

echo ""
echo ">> Enabling pgvector extension (if not already on)"
PGPASSWORD="${DB_PASSWORD}" psql \
  "host=${DB_HOST} port=5432 dbname=postgres user=postgres sslmode=require" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"

echo ""
echo "==================================================================="
echo "Schema applied. Now set these in Vercel (Project Settings > Environment Variables):"
echo "==================================================================="
cat <<EOF

SUPABASE_URL=${SUPABASE_URL}
SUPABASE_DB_HOST=${DB_HOST}
SUPABASE_DB_NAME=postgres
SUPABASE_DB_USER=postgres
SUPABASE_DB_PASSWORD=${DB_PASSWORD}
SUPABASE_JWT_SECRET=${JWT_SECRET}
GOOGLE_AI_API_KEY=${GOOGLE_AI_KEY}
AADHAAR_HASH_SALT=${AADHAAR_SALT}
DOCUMENT_SIGNING_PRIVATE_KEY=<contents of .signing_private_key.pem, with real
                               newlines replaced by \n before pasting>

EOF
echo "Set these via: vercel env add <NAME>"
echo "Or paste them into the Vercel dashboard directly."
echo "==================================================================="
