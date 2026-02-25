#!/bin/bash
set -e  # Exit on any error

echo "🚀 Starting deployment of etl_server..."

# Navigate to project
cd ~/projects/etl_server

# Pull latest code
echo "📥 Pulling latest code..."
git pull origin main

# Install dependencies
echo "📦 Installing Ruby gems..."
source ~/.asdf/asdf.sh
bundle install

# Database migrations
echo "🗄️  Running database migrations..."
RAILS_ENV=production SECRET_KEY_BASE=b14b3c17fd037b6b9093dd87c4e24e699ce83176115b9f0736fdf5ceb93265affa0c8b7831fb9837d263c8fbb66abfe5b839ae9b554a540a329ee6d34d13d4aa bundle exec rails db:migrate

# Restart service
echo "♻️  Restarting application..."
sudo systemctl restart etl_server.service

# Wait for service to start
sleep 3

# Check status
echo "✅ Checking service status..."
sudo systemctl status etl_server.service --no-pager

echo ""
echo "✨ Deployment complete!"
echo "🌐 Visit: https://etl.cnxkit.com"
echo "📋 Logs: sudo journalctl -u etl_server.service -f"

