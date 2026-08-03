# Production Deployment Guide

## Quick Start Checklist

- [ ] SSL certificates obtained (Let's Encrypt)
- [ ] Environment variables configured (.env file)
- [ ] Docker and Docker Compose installed
- [ ] Domain DNS configured
- [ ] Firewall rules allow 80, 443
- [ ] Stripe webhook secret obtained
- [ ] Application tested locally

## Pre-Deployment Steps

### 1. Obtain SSL Certificates

Using Let's Encrypt with Certbot:

```bash
# Install Certbot
sudo apt-get update
sudo apt-get install certbot

# Generate certificates
sudo certbot certonly --standalone \
  -d hacyberglobal.dgdns.org \
  --email your-email@example.com \
  --agree-tos \
  --non-interactive

# Certificates will be in /etc/letsencrypt/live/hacyberglobal.dgdns.org/
# - fullchain.pem (certificate)
# - privkey.pem (private key)
```

### 2. Create Directory Structure

```bash
cd /opt/stripe-webhook  # or your deployment directory
mkdir -p ssl/{certs,keys}
mkdir -p log
mkdir -p config

# Copy SSL certificates
sudo cp /etc/letsencrypt/live/hacyberglobal.dgdns.org/fullchain.pem ssl/certs/
sudo cp /etc/letsencrypt/live/hacyberglobal.dgdns.org/privkey.pem ssl/keys/

# Set permissions
sudo chown $USER:$USER ssl/keys/privkey.pem
sudo chmod 600 ssl/keys/privkey.pem
```

### 3. Configure Environment Variables

Create `.env` file:

```bash
cat > .env << EOF
# Stripe Configuration
STRIPE_API_KEY=sk_live_your_production_key_here
WEBHOOK_SECRET=whsec_live_your_webhook_secret_here

# Rails Configuration
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Server Configuration
PORT=3000
EOF

chmod 600 .env
```

### 4. Clone Repository

```bash
git clone https://github.com/hacyberglobal-dgdns-org/stripe-ruby.git
cd stripe-ruby
```

## Deployment

### Step 1: Build Docker Image

```bash
docker-compose build
```

### Step 2: Start Services

```bash
# Start in detached mode
docker-compose up -d

# Verify services are running
docker-compose ps

# Check logs
docker-compose logs -f app
docker-compose logs -f nginx
```

### Step 3: Verify Deployment

```bash
# Health check endpoint
curl -X GET https://hacyberglobal.dgdns.org/api/webhook

# Should return:
# {"status":"Webhook endpoint is ready","timestamp":"2026-08-03T..."}
```

### Step 4: Test Webhook

```bash
# From Stripe Dashboard:
# 1. Go to https://dashboard.stripe.com/webhooks
# 2. Click on your endpoint
# 3. Click "Send test webhook"
# 4. Select "payment_intent.succeeded"
# 5. Click "Send"

# Check logs for processing
docker-compose logs app | grep -i webhook
```

## Monitoring & Maintenance

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f app
docker-compose logs -f nginx

# Follow last 100 lines
docker-compose logs --tail=100 -f
```

### Check Service Health

```bash
# Container status
docker-compose ps

# App health
curl http://localhost:3000/api/webhook

# Nginx health
curl -I https://hacyberglobal.dgdns.org/api/webhook
```

### View Webhook Logs

```bash
# Inside container
docker-compose exec app tail -f log/stripe_webhooks.log

# Or from host
tail -f log/stripe_webhooks.log
```

## SSL Certificate Renewal

Let's Encrypt certificates expire after 90 days. Set up auto-renewal:

```bash
# Install renewal timer (if using systemd)
sudo systemctl enable certbot-renew.timer
sudo systemctl start certbot-renew.timer

# Manual renewal
sudo certbot renew

# After renewal, copy new certificates
sudo cp /etc/letsencrypt/live/hacyberglobal.dgdns.org/fullchain.pem \
  /opt/stripe-webhook/ssl/certs/
sudo cp /etc/letsencrypt/live/hacyberglobal.dgdns.org/privkey.pem \
  /opt/stripe-webhook/ssl/keys/

# Reload Nginx
docker-compose exec nginx nginx -s reload
```

## Updating Application

```bash
# Pull latest changes
git pull origin main

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Verify
docker-compose logs -f app
```

## Troubleshooting

### "Invalid URL" Error in Stripe Dashboard

**Symptoms:** Stripe shows "Invalid URL" for your webhook endpoint

**Solutions:**
```bash
# 1. Verify domain resolution
nslookup hacyberglobal.dgdns.org

# 2. Check SSL certificate
openssl s_client -connect hacyberglobal.dgdns.org:443 -servername hacyberglobal.dgdns.org

# 3. Test endpoint accessibility
curl -v https://hacyberglobal.dgdns.org/api/webhook

# 4. Check Nginx logs
docker-compose logs nginx

# 5. Verify app is responding
docker-compose exec app curl -v http://localhost:3000/api/webhook
```

### "Signature Verification Failed"

**Symptoms:** Events processed but signature verification fails

**Solutions:**
```bash
# 1. Verify webhook secret in .env matches Stripe Dashboard
cat .env | grep WEBHOOK_SECRET

# 2. Check Stripe Dashboard webhook secret
# https://dashboard.stripe.com/webhooks

# 3. Update .env if needed
nano .env

# 4. Restart container
docker-compose restart app

# 5. Check logs
docker-compose logs app | grep -i signature
```

### Events Not Being Received

**Symptoms:** No events appearing in application logs

**Solutions:**
```bash
# 1. Check delivery status in Stripe Dashboard
# https://dashboard.stripe.com/webhooks > Click endpoint > Event deliveries

# 2. Verify firewall allows HTTPS
sudo ufw allow 443/tcp

# 3. Check Nginx is forwarding requests
docker-compose logs nginx | tail -20

# 4. Verify app is running
docker-compose ps

# 5. Test event manually
docker-compose exec app bash
curl -X POST http://localhost:3000/api/webhook \
  -H "Content-Type: application/json" \
  -H "Stripe-Signature: test" \
  -d '{}'
```

### Container Won't Start

**Symptoms:** `docker-compose up` fails

**Solutions:**
```bash
# 1. Check logs
docker-compose logs

# 2. Verify .env file exists and is valid
cat .env

# 3. Rebuild image
docker-compose build --no-cache

# 4. Check disk space
df -h

# 5. Verify ports are available
sudo netstat -tlnp | grep 3000
sudo netstat -tlnp | grep 443
```

## Performance Optimization

### Nginx Tuning

Already configured in `nginx.conf`:
- Worker processes: `auto` (matches CPU cores)
- Connection limit: 1024 per worker
- Gzip compression: enabled
- Rate limiting: 100 req/s for webhooks, 10 req/s for API
- Connection pooling to upstream

### Rails Tuning

Update `config/puma.rb` (if using Rails):
```ruby
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count
workers ENV.fetch("WEB_CONCURRENCY") { 4 }
```

### Docker Resource Limits

Edit `docker-compose.yml`:
```yaml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1024M
        reservations:
          cpus: '1'
          memory: 512M
```

## Backup & Recovery

### Backup Logs

```bash
# Backup webhook logs
tar -czf stripe_webhooks_backup_$(date +%Y%m%d).tar.gz log/

# Archive to cloud storage
aws s3 cp stripe_webhooks_backup_*.tar.gz s3://your-bucket/backups/
```

### Recovery from Backup

```bash
# Extract logs
tar -xzf stripe_webhooks_backup_20260803.tar.gz

# Restore to container
docker-compose cp log/ app:/app/
```

## Security Best Practices

1. **API Key Security**
   - Never commit `.env` to git
   - Use production keys in production, test keys in staging
   - Rotate keys regularly

2. **Network Security**
   - Enable firewall
   - Only expose 80, 443
   - Use VPC/private networks when possible

3. **Application Security**
   - Keep dependencies updated: `bundle update`
   - Enable HTTPS only
   - Use strong SSL ciphers (configured in nginx.conf)

4. **Monitoring**
   - Monitor error logs daily
   - Set up alerts for failed events
   - Review webhook delivery status weekly

## Support & Resources

- **Stripe Documentation:** https://stripe.com/docs/webhooks
- **Stripe Ruby SDK:** https://github.com/stripe/stripe-ruby
- **Nginx Documentation:** https://nginx.org/en/docs/
- **Docker Documentation:** https://docs.docker.com/
- **Let's Encrypt:** https://letsencrypt.org/

## Common Commands Cheat Sheet

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Rebuild image
docker-compose build

# Execute command in container
docker-compose exec app bash

# Restart service
docker-compose restart app

# View running containers
docker-compose ps

# Remove unused resources
docker-compose down --volumes
docker system prune -a
```
