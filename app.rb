# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'rack/cors'
require 'dotenv/load'
require 'json'
require 'erb'
require 'securerandom'
require 'fileutils'
require 'base64'

require_relative 'lib/validator'
require_relative 'lib/template_renderer'
require_relative 'lib/pdf_generator'
require_relative 'lib/email_sender'

class App < Sinatra::Base
  helpers Sinatra::JSON

  ALLOWED_TEMPLATES = %w[classic].freeze
  MAX_IMAGE_SIZE = 5 * 1024 * 1024 # 5 MB
  ALLOWED_MIME_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  TMP_DIR = File.join(__dir__, 'tmp')

  configure do
    FileUtils.mkdir_p(TMP_DIR)

    use Rack::Cors do
      allow do
        origins(ENV.fetch('CORS_ORIGIN', '*'))
        resource '/generate', methods: [:post, :options], headers: :any
        resource '/', methods: [:get], headers: :any
      end
    end
  end

  # Health check
  get '/' do
    json({
      status: 'ok',
      service: 'send-an-owl',
      message: 'Owl post is ready and listening!'
    })
  end

  # Generate and send card
  post '/generate' do
    # --- Validate ---
    errors = Validator.validate(
      params,
      allowed_templates: ALLOWED_TEMPLATES,
      max_image_size: MAX_IMAGE_SIZE,
      allowed_mime_types: ALLOWED_MIME_TYPES
    )

    unless errors.empty?
      halt 422, { 'Content-Type' => 'application/json' },
           JSON.generate({ error: errors.first })
    end

    request_id = SecureRandom.hex(8)
    tmp_image_path = nil
    tmp_pdf_path = nil

    begin
      # --- Save uploaded image temporarily ---
      photo = params[:photo]
      ext = File.extname(photo[:filename]).downcase
      ext = '.jpg' if ext.empty?
      tmp_image_path = File.join(TMP_DIR, "#{request_id}_photo#{ext}")
      File.open(tmp_image_path, 'wb') { |f| f.write(photo[:tempfile].read) }

      # --- Render HTML ---
      html = TemplateRenderer.render(
        template: params[:template],
        recipient_name: params[:recipientName],
        sender_name: params[:senderName],
        message: params[:message],
        photo_path: tmp_image_path
      )

      # --- Generate PDF ---
      tmp_pdf_path = File.join(TMP_DIR, "#{request_id}_card.pdf")
      PdfGenerator.generate(html: html, output_path: tmp_pdf_path)

      # --- Send email ---
      EmailSender.send_card(
        to: (params[:recipientEmail] || params['recipientEmail']),
        recipient_name: (params[:recipientName] || params['recipientName']),
        sender_name: (params[:senderName] || params['senderName']),
        pdf_path: tmp_pdf_path
      )

      json({ success: true, message: 'Card sent successfully.' })

    rescue EmailSender::NotConfiguredError => e
      halt 503, { 'Content-Type' => 'application/json' },
           JSON.generate({ error: e.message })

    rescue StandardError => e
      # Log internally but don't expose details
      $stderr.puts "[ERROR] #{e.class}: #{e.message}"
      halt 500, { 'Content-Type' => 'application/json' },
           JSON.generate({ error: 'An internal error occurred. Please try again.' })

    ensure
      # --- Cleanup temporary files ---
      [tmp_image_path, tmp_pdf_path].each do |path|
        File.delete(path) if path && File.exist?(path)
      end
    end
  end
end
