# frozen_string_literal: true

require 'erb'
require 'cgi'
require 'base64'

module TemplateRenderer
  TEMPLATES_DIR = File.join(__dir__, '..', 'templates')

  def self.render(template:, recipient_name:, sender_name:, message:, photo_path:)
    template_dir = File.join(TEMPLATES_DIR, template)
    erb_path = File.join(template_dir, 'template.html.erb')
    css_path = File.join(template_dir, 'template.css')
    bg_path = File.join(template_dir, 'template.png')

    unless File.exist?(erb_path)
      raise "Template not found: #{template}"
    end

    # Read template files
    erb_content = File.read(erb_path)
    css_content = File.exist?(css_path) ? File.read(css_path) : ''

    # Encode images as base64 data URIs for PDF rendering
    bg_data_uri = file_to_data_uri(bg_path, 'image/png')
    photo_data_uri = file_to_data_uri(photo_path, detect_mime(photo_path))

    # Escape user content for HTML safety
    safe_recipient = CGI.escapeHTML(recipient_name.to_s)
    safe_sender = CGI.escapeHTML(sender_name.to_s)
    safe_message = CGI.escapeHTML(message.to_s)

    # Render ERB
    b = binding
    b.local_variable_set(:css, css_content)
    b.local_variable_set(:bg_data_uri, bg_data_uri)
    b.local_variable_set(:photo_data_uri, photo_data_uri)
    b.local_variable_set(:recipient_name, safe_recipient)
    b.local_variable_set(:sender_name, safe_sender)
    b.local_variable_set(:message, safe_message)

    ERB.new(erb_content).result(b)
  end

  private

  def self.file_to_data_uri(path, mime_type)
    return '' unless path && File.exist?(path)

    data = Base64.strict_encode64(File.binread(path))
    "data:#{mime_type};base64,#{data}"
  end

  def self.detect_mime(path)
    case File.extname(path).downcase
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.png' then 'image/png'
    when '.webp' then 'image/webp'
    when '.gif' then 'image/gif'
    else 'application/octet-stream'
    end
  end
end
