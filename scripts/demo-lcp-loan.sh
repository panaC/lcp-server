#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8989}"
API_USER="${API_USER:-lcp_api_user}"
API_PASSWORD="${API_PASSWORD:-lcp_api_password}"

OUT_DIR="${OUT_DIR:-./.local/demo-loan}"
RESOURCE_DIR="${RESOURCE_DIR:-./.local/lcpserver/resources}"

PUBLICATION_ID="${PUBLICATION_ID:-$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)}"

USER_ID="${USER_ID:-demo-user-001}"
USER_NAME="${USER_NAME:-Demo User}"
USER_EMAIL="${USER_EMAIL:-demo@example.org}"
PASSPHRASE="${PASSPHRASE:-123 456}"

mkdir -p "$OUT_DIR" "$RESOURCE_DIR"

PUBLICATION_FILE="$RESOURCE_DIR/demo-publication.epub"
PUBLICATION_HREF="${BASE_URL}/resources/$(basename "$PUBLICATION_FILE")"

PUBLICATION_PAYLOAD="$OUT_DIR/publication.json"
LICENSE_PAYLOAD="$OUT_DIR/license-request.json"
FRESH_LICENSE_PAYLOAD="$OUT_DIR/fresh-license-request.json"
LICENSE_FILE="$OUT_DIR/license.lcpl"
FRESH_LICENSE_FILE="$OUT_DIR/fresh-license.lcpl"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi

echo "Generating dummy EPUB: $PUBLICATION_FILE"

python3 - "$PUBLICATION_FILE" "$PUBLICATION_ID" <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED, ZIP_DEFLATED
from datetime import datetime, timezone
import sys

out_path = Path(sys.argv[1])
publication_id = sys.argv[2]
modified = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

mimetype = "application/epub+zip"

container_xml = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0"
  xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="EPUB/content.opf"
      media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

content_opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf"
         version="3.0"
         unique-identifier="pub-id"
         xml:lang="en">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:{publication_id}</dc:identifier>
    <dc:title>Dummy EPUB Publication</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>LCP Server quickstart</dc:creator>
    <meta property="dcterms:modified">{modified}</meta>
  </metadata>

  <manifest>
    <item id="nav"
          href="nav.xhtml"
          media-type="application/xhtml+xml"
          properties="nav"/>
    <item id="chapter"
          href="chapter.xhtml"
          media-type="application/xhtml+xml"/>
  </manifest>

  <spine>
    <itemref idref="chapter"/>
  </spine>
</package>
"""

nav_xhtml = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops"
      lang="en"
      xml:lang="en">
  <head>
    <title>Navigation</title>
  </head>
  <body>
    <nav epub:type="toc" id="toc">
      <h1>Table of Contents</h1>
      <ol>
        <li><a href="chapter.xhtml">Dummy Chapter</a></li>
      </ol>
    </nav>
  </body>
</html>
"""

chapter_xhtml = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"
      lang="en"
      xml:lang="en">
  <head>
    <title>Dummy Chapter</title>
  </head>
  <body>
    <section>
      <h1>Dummy EPUB Publication</h1>
      <p>This is a minimal EPUB publication with exactly one XHTML document in the spine.</p>
    </section>
  </body>
</html>
"""

out_path.parent.mkdir(parents=True, exist_ok=True)

# EPUB requirement: the mimetype file must be the first ZIP entry
# and must be stored uncompressed.
with ZipFile(out_path, "w") as zf:
    zf.writestr("mimetype", mimetype, compress_type=ZIP_STORED)
    zf.writestr("META-INF/container.xml", container_xml, compress_type=ZIP_DEFLATED)
    zf.writestr("EPUB/content.opf", content_opf, compress_type=ZIP_DEFLATED)
    zf.writestr("EPUB/nav.xhtml", nav_xhtml, compress_type=ZIP_DEFLATED)
    zf.writestr("EPUB/chapter.xhtml", chapter_xhtml, compress_type=ZIP_DEFLATED)
PY

read -r PUBLICATION_SIZE PUBLICATION_CHECKSUM < <(
  python3 - "$PUBLICATION_FILE" <<'PY'
from pathlib import Path
import hashlib
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
print(path.stat().st_size, hashlib.sha256(data).hexdigest())
PY
)

ENCRYPTION_KEY="$(python3 - <<'PY'
import base64
import os
print(base64.b64encode(os.urandom(32)).decode("ascii"))
PY
)"

PASS_HASH="$(python3 - "$PASSPHRASE" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest().upper())
PY
)"

read -r START END < <(
  python3 - <<'PY'
from datetime import datetime, timedelta, timezone

start = datetime.now(timezone.utc)
end = start + timedelta(days=14)

print(
    start.strftime("%Y-%m-%dT%H:%M:%SZ"),
    end.strftime("%Y-%m-%dT%H:%M:%SZ"),
)
PY
)

cat > "$PUBLICATION_PAYLOAD" <<EOF
{
  "uuid": "$PUBLICATION_ID",
  "title": "Dummy EPUB Publication",
  "encryption_key": "$ENCRYPTION_KEY",
  "href": "$PUBLICATION_HREF",
  "content_type": "application/epub+zip",
  "size": $PUBLICATION_SIZE,
  "checksum": "$PUBLICATION_CHECKSUM"
}
EOF

cat > "$LICENSE_PAYLOAD" <<EOF
{
  "publication_id": "$PUBLICATION_ID",
  "user_id": "$USER_ID",
  "user_name": "$USER_NAME",
  "user_email": "$USER_EMAIL",
  "user_encrypted": ["name", "email"],
  "start": "$START",
  "end": "$END",
  "copy": 20000,
  "print": 100,
  "profile": "http://readium.org/lcp/basic-profile",
  "text_hint": "Passphrase for this demo loan: $PASSPHRASE",
  "pass_hash": "$PASS_HASH"
}
EOF

cat > "$FRESH_LICENSE_PAYLOAD" <<EOF
{
  "user_id": "$USER_ID",
  "user_name": "$USER_NAME",
  "user_email": "$USER_EMAIL",
  "user_encrypted": ["name", "email"],
  "profile": "http://readium.org/lcp/basic-profile",
  "text_hint": "Passphrase for this demo loan: $PASSPHRASE",
  "pass_hash": "$PASS_HASH"
}
EOF

echo "Adding publication: $PUBLICATION_ID"

curl -fsS \
  -u "$API_USER:$API_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST "$BASE_URL/publications/" \
  --data @"$PUBLICATION_PAYLOAD" \
  > "$OUT_DIR/publication-response.json"

echo "Generating loan/license..."

curl -fsS \
  -u "$API_USER:$API_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST "$BASE_URL/licenses/" \
  --data @"$LICENSE_PAYLOAD" \
  > "$LICENSE_FILE"

LICENSE_ID="$(python3 - "$LICENSE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

license_id = data.get("id") or data.get("uuid")

if not license_id:
    raise SystemExit("Could not find license id in generated license payload.")

print(license_id)
PY
)"

echo "Fetching fresh license: $LICENSE_ID"

curl -fsS \
  -u "$API_USER:$API_PASSWORD" \
  -H "Content-Type: application/json" \
  -X POST "$BASE_URL/licenses/$LICENSE_ID" \
  --data @"$FRESH_LICENSE_PAYLOAD" \
  > "$FRESH_LICENSE_FILE"

cat <<EOF

Done.

Publication EPUB:
  $PUBLICATION_FILE

Publication payload:
  $PUBLICATION_PAYLOAD

License request:
  $LICENSE_PAYLOAD

Generated license:
  $LICENSE_FILE

Fresh license:
  $FRESH_LICENSE_FILE

Publication ID:
  $PUBLICATION_ID

License ID:
  $LICENSE_ID

Passphrase:
  $PASSPHRASE

EOF
