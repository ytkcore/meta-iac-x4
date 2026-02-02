#!/bin/bash
set -e

# Configuration
HARBOR_HOST="my-harbor.local"
COMPOSE_FILE="docker-compose.yml"

echo ">>> Starting Step 1: Harbor Login Check"
# Docker login verification
if ! egrep -q "$HARBOR_HOST" ~/.docker/config.json; then
    echo "❌ Error: Not logged in to Harbor ($HARBOR_HOST)."
    echo "   Please run: docker login $HARBOR_HOST"
    exit 1
else
    echo "✅ Login credential found for $HARBOR_HOST"
fi

echo ">>> Step 2: Validating Config Files"
if [ ! -f config/postgres/pg_hba.conf ] || [ ! -f config/neo4j/neo4j.conf ]; then
    echo "❌ Error: Configuration templates not found in ./config/"
    exit 1
fi

echo ">>> Step 3: Pulling Images from Internal Registry"
docker-compose -f $COMPOSE_FILE pull

echo ">>> Step 4: Starting Database Containers"
docker-compose -f $COMPOSE_FILE up -d

echo ">>> Step 5: Waiting for services to initialize (10s)..."
bot_progress=0
while [ $bot_progress -lt 10 ]; do
    echo -n "."
    sleep 1
    bot_progress=$((bot_progress+1))
done
echo ""

echo ">>> Step 6: Verifying Ports"
FAILED=0

# Verify PostgreSQL
if docker-compose -f $COMPOSE_FILE ps postgres | grep -q "Up"; then
    if nc -z -v -w 5 localhost 5432 2>/dev/null; then
        echo "✅ PostgreSQL is listening on port 5432"
    else
        echo "⚠️  PostgreSQL container is Up, but port 5432 is not responding locally (Check Security Group if remote)"
    fi
else
    echo "❌ PostgreSQL container failed to start"
    FAILED=1
fi

# Verify Neo4j
if docker-compose -f $COMPOSE_FILE ps neo4j | grep -q "Up"; then
    if nc -z -v -w 5 localhost 7474 2>/dev/null; then
        echo "✅ Neo4j HTTP is listening on port 7474"
    else
        echo "⚠️  Neo4j container is Up, but port 7474 is not responding"
    fi
    if nc -z -v -w 5 localhost 7687 2>/dev/null; then
        echo "✅ Neo4j Bolt is listening on port 7687"
    else
        echo "⚠️  Neo4j Bolt is Up, but port 7687 is not responding"
    fi
else
    echo "❌ Neo4j container failed to start"
    FAILED=1
fi

if [ $FAILED -eq 0 ]; then
    echo ">>> 🎉 Database Setup Completed Successfully!"
    echo "    - PostgreSQL: localhost:5432 (User: admin / scarm-sha-256)"
    echo "    - Neo4j: localhost:7474 (Browser) / localhost:7687 (Bolt)"
else
    echo ">>> ❌ Setup completed with errors. Check 'docker-compose logs'."
    exit 1
fi
