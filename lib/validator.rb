# frozen_string_literal: true

module Validator
  EMAIL_REGEX = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
  MAX_MESSAGE_WORDS = 50
  MAX_NAME_LENGTH = 60

  def self.validate(params, allowed_templates:, max_image_size:, allowed_mime_types:)
    errors = []

    # Template
    template = params[:template].to_s.strip
    unless allowed_templates.include?(template)
      errors << 'Invalid or missing template.'
    end

    # Recipient name
    name = params[:recipientName].to_s.strip
    if name.empty?
      errors << 'Recipient name is required.'
    elsif name.length > MAX_NAME_LENGTH
      errors << 'Recipient name is too long.'
    end

    # Recipient email
    email = params[:recipientEmail].to_s.strip
    if email.empty?
      errors << 'Recipient email is required.'
    elsif !EMAIL_REGEX.match?(email)
      errors << 'Invalid email address.'
    end

    # Sender name
    sender = params[:senderName].to_s.strip
    if sender.empty?
      errors << 'Your name is required.'
    elsif sender.length > MAX_NAME_LENGTH
      errors << 'Your name is too long.'
    end

    # Message
    message = params[:message].to_s.strip
    if message.empty?
      errors << 'Message is required.'
    else
      word_count = message.split(/\s+/).length
      if word_count > MAX_MESSAGE_WORDS
        errors << "Message must be #{MAX_MESSAGE_WORDS} words or fewer."
      end
    end

    # Photo
    photo = params[:photo]
    if photo.nil? || !photo.is_a?(Hash) || photo[:tempfile].nil?
      errors << 'Photo is required.'
    else
      # Check MIME type
      content_type = photo[:type].to_s.downcase
      unless allowed_mime_types.include?(content_type)
        errors << 'Unsupported image format. Use JPEG, PNG, WebP, or GIF.'
      end

      # Check file size
      photo[:tempfile].rewind
      size = photo[:tempfile].size
      if size > max_image_size
        errors << 'Image is too large. Maximum size is 5 MB.'
      end
    end

    errors
  end
end
