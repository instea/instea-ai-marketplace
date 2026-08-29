#!/bin/bash
# Runs on EVERY container start, not just creation — this is the difference that
# matters for services. After a stop/start or a laptop reboot the project's
# containers are not running even though their data is intact, so bringing them
# up from postCreateCommand leaves a dead database on day two.
#
# Only needed under the docker-in-docker option. With services as compose
# siblings (step 3, option A) the outer daemon starts them and this file is
# unnecessary.
set -e

# The inner daemon needs a moment before it accepts connections. Wait for it
# rather than racing it, and fail loudly if it never arrives.
if ! timeout 60 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'; then
  echo "inner dockerd did not come up within 60s" >&2
  exit 1
fi

docker compose up -d

# Optional: block until the database is actually accepting queries, so the first
# command in a fresh shell doesn't fail on a connection refused.
# timeout 60 bash -c 'until docker compose exec -T postgres pg_isready -q; do sleep 1; done'
