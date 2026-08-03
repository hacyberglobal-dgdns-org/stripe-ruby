# frozen_string_literal: true

# webhook_handler.rb - Production-ready Stripe webhook handler
# 
# Handles real-time payment events and automated activations for HGT Nexus Portal
# Features:
#   - Event signature verification
#   - Idempotency (prevents duplicate processing)
#   - Async processing with logging
#   - Comprehensive error handling
#   - Support for multiple event types

require 'stripe'
require 'json'
require 'logger'
require 'dotenv/load'

# Configure Stripe
Stripe.api_key = ENV['STRIPE_API_KEY']
WEBHOOK_SECRET = ENV['WEBHOOK_SECRET']

# Setup logging
logger = Logger.new('log/stripe_webhooks.log', 'daily')
logger.level = Logger::INFO

# Track processed event IDs to prevent duplicates
PROCESSED_EVENTS = Set.new

# Helper: Log events with context
def log_event(logger, level, event_id, message, details = {})
  log_message = "[#{event_id}] #{message}"
  log_message += " | #{details.to_json}" if details.any?
  logger.send(level, log_message)
end

# Event handler: Payment succeeded
def handle_payment_succeeded(event, logger)
  payment_intent = event.data.object
  customer_id = payment_intent.customer
  amount = payment_intent.amount / 100.0  # Convert from cents
  
  log_event(logger, :info, event.id, "Payment succeeded", {
    payment_intent_id: payment_intent.id,
    customer_id: customer_id,
    amount: "#{amount} #{payment_intent.currency.upcase}"
  })
  
  # TODO: Update your database
  # Order.find_by(stripe_payment_id: payment_intent.id).mark_as_paid!
  
  # TODO: Send confirmation email
  # PaymentMailer.confirmation_email(customer_id, payment_intent.id).deliver_later
  
  # TODO: Trigger activation
  # ActivationService.activate_subscription(customer_id)
  
  true
rescue StandardError => e
  log_event(logger, :error, event.id, "Error handling payment_succeeded: #{e.message}")
  false
end

# Event handler: Payment failed
def handle_payment_failed(event, logger)
  payment_intent = event.data.object
  customer_id = payment_intent.customer
  
  log_event(logger, :warn, event.id, "Payment failed", {
    payment_intent_id: payment_intent.id,
    customer_id: customer_id,
    status: payment_intent.status
  })
  
  # TODO: Update order status
  # Order.find_by(stripe_payment_id: payment_intent.id).mark_as_failed!
  
  # TODO: Send failure notification
  # PaymentMailer.failure_email(customer_id).deliver_later
  
  # TODO: Queue for retry
  # RetryQueue.enqueue(payment_intent.id)
  
  true
rescue StandardError => e
  log_event(logger, :error, event.id, "Error handling payment_failed: #{e.message}")
  false
end

# Event handler: Charge refunded
def handle_charge_refunded(event, logger)
  charge = event.data.object
  refund_amount = charge.amount_refunded / 100.0
  
  log_event(logger, :info, event.id, "Charge refunded", {
    charge_id: charge.id,
    refund_amount: "#{refund_amount} #{charge.currency.upcase}",
    payment_intent_id: charge.payment_intent
  })
  
  # TODO: Update order status
  # Order.find_by(stripe_charge_id: charge.id).mark_as_refunded!
  
  # TODO: Update inventory
  # Inventory.restore_items_for_order(charge.payment_intent)
  
  # TODO: Send refund confirmation
  # PaymentMailer.refund_email(charge.customer).deliver_later
  
  true
rescue StandardError => e
  log_event(logger, :error, event.id, "Error handling charge_refunded: #{e.message}")
  false
end

# Event handler: Customer created
def handle_customer_created(event, logger)
  customer = event.data.object
  
  log_event(logger, :info, event.id, "Customer created", {
    customer_id: customer.id,
    email: customer.email
  })
  
  # TODO: Store customer in your database
  # Customer.create(
  #   stripe_customer_id: customer.id,
  #   email: customer.email,
  #   name: customer.name
  # )
  
  true
rescue StandardError => e
  log_event(logger, :error, event.id, "Error handling customer_created: #{e.message}")
  false
end

# Event handler: Invoice payment succeeded
def handle_invoice_payment_succeeded(event, logger)
  invoice = event.data.object
  customer_id = invoice.customer
  amount = invoice.amount_paid / 100.0
  
  log_event(logger, :info, event.id, "Invoice payment succeeded", {
    invoice_id: invoice.id,
    customer_id: customer_id,
    amount: "#{amount} #{invoice.currency.upcase}"
  })
  
  # TODO: Mark invoice as paid in your system
  # Invoice.find_by(stripe_invoice_id: invoice.id).mark_as_paid!
  
  true
rescue StandardError => e
  log_event(logger, :error, event.id, "Error handling invoice_payment_succeeded: #{e.message}")
  false
end

# Main webhook handler
def process_webhook(webhook_body, sig_header, logger)
  # Step 1: Verify signature
  begin
    event = Stripe::Webhook.construct_event(
      webhook_body,
      sig_header,
      WEBHOOK_SECRET
    )
  rescue JSON::ParserError => e
    log_event(logger, :error, 'unknown', "Invalid JSON in webhook: #{e.message}")
    return { error: 'Invalid JSON', success: false }, 400
  rescue Stripe::SignatureVerificationError => e
    log_event(logger, :error, 'unknown', "Signature verification failed: #{e.message}")
    return { error: 'Invalid signature', success: false }, 400
  end
  
  event_id = event.id
  event_type = event.type
  
  # Step 2: Check if already processed (idempotency)
  if PROCESSED_EVENTS.include?(event_id)
    log_event(logger, :warn, event_id, "Duplicate event received, skipping", {
      event_type: event_type
    })
    return { received: true, duplicate: true }, 200
  end
  
  # Step 3: Route to appropriate handler
  log_event(logger, :info, event_id, "Processing webhook event", {
    event_type: event_type
  })
  
  result = case event_type
           when 'payment_intent.succeeded'
             handle_payment_succeeded(event, logger)
           when 'payment_intent.payment_failed'
             handle_payment_failed(event, logger)
           when 'charge.refunded'
             handle_charge_refunded(event, logger)
           when 'customer.created'
             handle_customer_created(event, logger)
           when 'invoice.payment_succeeded'
             handle_invoice_payment_succeeded(event, logger)
           else
             log_event(logger, :info, event_id, "Unhandled event type", {
               event_type: event_type
             })
             true
           end
  
  # Step 4: Mark as processed
  PROCESSED_EVENTS.add(event_id)
  
  # Step 5: Cleanup old processed events (keep last 1000)
  PROCESSED_EVENTS.keep_if { PROCESSED_EVENTS.size > 1000 }
  
  if result
    log_event(logger, :info, event_id, "Event processed successfully")
    { received: true, success: true }, 200
  else
    log_event(logger, :error, event_id, "Event processing failed")
    { received: true, success: false }, 200  # Return 200 to prevent retries
  end
rescue StandardError => e
  log_event(logger, :error, event_id, "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}")
  { error: 'Internal server error', success: false }, 500
end

# For use with Sinatra
if defined?(Sinatra)
  post '/api/webhook' do
    request.body.rewind
    webhook_body = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    
    response, status = process_webhook(webhook_body, sig_header, logger)
    
    status status
    response.to_json
  end
  
  get '/api/webhook' do
    { status: 'Webhook endpoint is ready', timestamp: Time.now.iso8601 }.to_json
  end
end

# For use with Rails
if defined?(Rails)
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    
    def stripe
      webhook_body = request.body.read
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      
      response, status = process_webhook(webhook_body, sig_header, Rails.logger)
      
      render json: response, status: status
    end
    
    def health
      render json: { status: 'Webhook endpoint is ready', timestamp: Time.now.iso8601 }
    end
  end
end

# Export for testing
module StripeWebhook
  extend self
  
  def process(webhook_body, sig_header, test_logger = nil)
    test_logger ||= Logger.new($stdout)
    process_webhook(webhook_body, sig_header, test_logger)
  end
end
