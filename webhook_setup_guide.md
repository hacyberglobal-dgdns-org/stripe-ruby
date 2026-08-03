# Stripe Webhook Setup Guide for HGT Nexus Portal

## Overview
This guide helps you set up a working Stripe webhook endpoint at `https://hacyberglobal.dgdns.org/api/webhook` to handle real-time payment events.

## Prerequisites
- Ruby 2.7+ installed
- Stripe account with API keys
- Rails or Sinatra application
- Valid SSL certificate (HTTPS required)
- Public domain accessible from the internet

## Step 1: Install Dependencies

Add to your `Gemfile`:
```ruby
gem 'stripe'
gem 'sinatra'  # if using Sinatra, or add to Rails
gem 'dotenv'   # for environment variables
```

Run:
```bash
bundle install
```

## Step 2: Set Environment Variables

Create a `.env` file in your project root:
```bash
STRIPE_API_KEY=sk_test_your_key_here
WEBHOOK_SECRET=whsec_test_your_webhook_secret_here
```

Get these from your Stripe Dashboard:
1. API Keys: https://dashboard.stripe.com/apikeys
2. Webhook Secret: https://dashboard.stripe.com/webhooks (after creating endpoint)

## Step 3: Create the Webhook Handler

### Option A: Using Rails

Create `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  post '/api/webhook', to: 'webhooks#stripe'
end
```

Create `app/controllers/webhooks_controller.rb`:
```ruby
require 'stripe'

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    webhook_secret = ENV['WEBHOOK_SECRET']
    
    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, webhook_secret
      )
    rescue JSON::ParserError => e
      return render json: { error: 'Invalid JSON' }, status: 400
    rescue Stripe::SignatureVerificationError => e
      return render json: { error: 'Invalid signature' }, status: 400
    end
    
    # Handle different event types
    case event.type
    when 'payment_intent.succeeded'
      handle_payment_succeeded(event)
    when 'payment_intent.payment_failed'
      handle_payment_failed(event)
    when 'charge.refunded'
      handle_charge_refunded(event)
    when 'customer.created'
      handle_customer_created(event)
    end
    
    render json: { received: true }, status: 200
  end
  
  private
  
  def handle_payment_succeeded(event)
    payment_intent = event.data.object
    puts "✅ Payment succeeded: #{payment_intent.id}"
    # TODO: Update your database, send confirmation email, etc.
  end
  
  def handle_payment_failed(event)
    payment_intent = event.data.object
    puts "❌ Payment failed: #{payment_intent.id}"
    # TODO: Notify user, retry logic, etc.
  end
  
  def handle_charge_refunded(event)
    charge = event.data.object
    puts "💰 Charge refunded: #{charge.id}"
    # TODO: Update order status, etc.
  end
  
  def handle_customer_created(event)
    customer = event.data.object
    puts "👤 Customer created: #{customer.id}"
    # TODO: Log customer creation, etc.
  end
end
```

### Option B: Using Sinatra

Create `app.rb`:
```ruby
require 'sinatra'
require 'stripe'
require 'dotenv/load'

Stripe.api_key = ENV['STRIPE_API_KEY']
WEBHOOK_SECRET = ENV['WEBHOOK_SECRET']

post '/api/webhook' do
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  
  begin
    event = Stripe::Webhook.construct_event(
      payload, sig_header, WEBHOOK_SECRET
    )
  rescue JSON::ParserError => e
    status 400
    return { error: 'Invalid JSON' }.to_json
  rescue Stripe::SignatureVerificationError => e
    status 400
    return { error: 'Invalid signature' }.to_json
  end
  
  # Process event
  case event.type
  when 'payment_intent.succeeded'
    puts "✅ Payment succeeded: #{event.data.object.id}"
  when 'payment_intent.payment_failed'
    puts "❌ Payment failed: #{event.data.object.id}"
  when 'charge.refunded'
    puts "💰 Charge refunded: #{event.data.object.id}"
  when 'customer.created'
    puts "👤 Customer created: #{event.data.object.id}"
  end
  
  status 200
  { received: true }.to_json
end

# Health check endpoint
get '/api/webhook' do
  { status: 'Webhook endpoint is ready' }.to_json
end
```

Run with:
```bash
ruby app.rb
```

## Step 4: Test Locally with Stripe CLI

1. Install Stripe CLI: https://stripe.com/docs/stripe-cli
2. Login:
   ```bash
   stripe login
   ```
3. Forward webhooks:
   ```bash
   stripe listen --forward-to localhost:3000/api/webhook
   ```
4. Get the webhook signing secret and add to `.env`
5. Trigger test events:
   ```bash
   stripe trigger payment_intent.succeeded
   ```

## Step 5: Deploy to Production

### Setup HTTPS
Your domain must have a valid SSL certificate:
```bash
# Using Let's Encrypt with Certbot
sudo certbot certonly -d hacyberglobal.dgdns.org
```

### Configure Your Server (Nginx example)
```nginx
server {
    listen 443 ssl http2;
    server_name hacyberglobal.dgdns.org;
    
    ssl_certificate /etc/letsencrypt/live/hacyberglobal.dgdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hacyberglobal.dgdns.org/privkey.pem;
    
    location /api/webhook {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Restart Your Application
```bash
# If using systemd
sudo systemctl restart your-app

# If using Docker
docker-compose restart
```

## Step 6: Register Webhook in Stripe Dashboard

1. Go to https://dashboard.stripe.com/webhooks
2. Click "Add Endpoint"
3. Enter URL: `https://hacyberglobal.dgdns.org/api/webhook`
4. Select events to listen to:
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
   - `customer.created`
5. Click "Add Endpoint"
6. Copy the signing secret and add to `.env`

## Step 7: Verify Your Setup

### Health Check
```bash
curl -X GET https://hacyberglobal.dgdns.org/api/webhook
```

Should return:
```json
{
  "status": "Webhook endpoint is ready"
}
```

### Send Test Event from Stripe Dashboard
1. Go to your webhook in https://dashboard.stripe.com/webhooks
2. Click "Send test webhook"
3. Select event type
4. Click "Send"
5. Check your application logs for the processed event

## Troubleshooting

### Invalid URL Error
- ✅ Verify domain resolves: `nslookup hacyberglobal.dgdns.org`
- ✅ Check SSL certificate: `openssl s_client -connect hacyberglobal.dgdns.org:443`
- ✅ Ensure endpoint is accessible: `curl -v https://hacyberglobal.dgdns.org/api/webhook`

### Signature Verification Failed
- ✅ Ensure `WEBHOOK_SECRET` env variable is correct
- ✅ Check that you're using the correct signing secret from the webhook settings
- ✅ Verify the webhook secret hasn't been rotated

### Events Not Being Received
- ✅ Check webhook delivery status in Stripe Dashboard
- ✅ Verify firewall rules allow inbound HTTPS traffic
- ✅ Check application logs for errors
- ✅ Ensure endpoint responds with HTTP 200

### Common Issues
```ruby
# Error: "No route to /api/webhook"
# Solution: Ensure route is properly registered

# Error: "Signature verification failed"
# Solution: Verify webhook secret matches in Stripe Dashboard

# Error: "Connection refused"
# Solution: Ensure your app is running and listening on the correct port
```

## Best Practices

1. **Always verify signatures** - Don't process unsigned webhooks
2. **Idempotency** - Handle duplicate events gracefully (same event_id)
3. **Async processing** - Don't do heavy lifting in webhook handler
4. **Logging** - Log all events for debugging
5. **Timeouts** - Return 200 quickly, process async
6. **Error handling** - Retry failed operations

## Testing in Production

```ruby
# Create a test payment
customer = Stripe::Customer.create
card_token = Stripe::Token.create(
  card: {
    number: "4242424242424242",
    exp_month: 12,
    exp_year: 2025,
    cvc: "123"
  }
)
payment_intent = Stripe::PaymentIntent.create(
  amount: 1000,
  currency: 'usd',
  customer: customer.id
)
```

## Support

- Stripe Documentation: https://stripe.com/docs/webhooks
- Stripe Ruby SDK: https://github.com/stripe/stripe-ruby
- API Reference: https://stripe.com/docs/api
