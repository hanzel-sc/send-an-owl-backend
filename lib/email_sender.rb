# frozen_string_literal: true

require 'google/apis/gmail_v1'
require 'googleauth'
require 'mail'
require 'stringio'
require 'erb'
require 'securerandom'

module EmailSender
  class NotConfiguredError < StandardError; end

  SCOPES = ['https://www.googleapis.com/auth/gmail.send'].freeze

  def self.send_card(to:, recipient_name:, sender_name:, pdf_path:)
    unless configured?
      raise NotConfiguredError, 'Email delivery is not configured. Set GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, and GOOGLE_REFRESH_TOKEN.'
    end

    recipient_email = to.to_s.strip
    if recipient_email.empty?
      raise ArgumentError, "Recipient email address ('to') is required but was #{to.inspect}"
    end

    service = Google::Apis::GmailV1::GmailService.new
    service.authorization = build_credentials

    # Build the email with PDF attachment
    mail = Mail.new
    mail.to = recipient_email
    mail.message_id = "<#{SecureRandom.hex(16)}@mail.gmail.com>"

    from_address = ENV.fetch('GMAIL_FROM_ADDRESS', 'noreply@example.com').strip
    from_addr = Mail::Address.new(from_address)
    from_addr.display_name = "Send an Owl"
    mail.from = from_addr.format

    mail.subject = "A birthday card for you, #{recipient_name}!"

    # Plain-text version (clean, polite, no spam-trigger phrases)
    plain_text = <<~TEXT
      Hi #{recipient_name},

      #{sender_name} sent you a personalized birthday card via Send an Owl!

      Your card is attached to this email as a printable PDF (birthday-card.pdf). Open the attachment to view your card.

      Warmly,
      Send an Owl
    TEXT

    # HTML version (responsive max-width container avoids inconsistent line wrapping across clients)
    safe_recipient = ERB::Util.html_escape(recipient_name)
    safe_sender = ERB::Util.html_escape(sender_name)

    html_text = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>A birthday card for you!</title>
      </head>
      <body style="margin: 0; padding: 24px 0; background-color: #f7f5f0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; -webkit-font-smoothing: antialiased; color: #2d3748;">
        <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0">
          <tr>
            <td align="center" style="padding: 0 16px;">
              <table role="presentation" style="max-width: 560px; width: 100%; background-color: #ffffff; border-radius: 12px; border: 1px solid #e5dfd5; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.04);" border="0" cellpadding="0" cellspacing="0">
                <!-- Simple Header -->
                <tr>
                  <td style="background-color: #2c1810; padding: 18px 28px; text-align: center;">
                    <span style="font-size: 15px; font-weight: 600; color: #fbf7ee; letter-spacing: 0.5px;">🦉 Send an Owl</span>
                  </td>
                </tr>
                <!-- Body Content -->
                <tr>
                  <td style="padding: 32px 28px 24px 28px; text-align: center;">
                    <h1 style="margin: 0 0 10px 0; font-size: 22px; font-weight: 700; color: #1a202c; line-height: 1.3;">
                      A birthday card for you, #{safe_recipient}! 🎉
                    </h1>
                    <p style="margin: 0 0 22px 0; font-size: 15px; color: #4a5568; line-height: 1.6;">
                      <strong>#{safe_sender}</strong> sent you a personalized birthday card.
                    </p>
                    
                    <!-- Card Attachment Info Box -->
                    <table role="presentation" width="100%" border="0" cellpadding="0" cellspacing="0" style="background-color: #fbf9f5; border: 1px solid #ebd9c8; border-radius: 8px; margin: 0 auto 20px auto;">
                      <tr>
                        <td style="padding: 18px 20px; text-align: center;">
                          <div style="font-size: 14px; font-weight: 600; color: #3d3428; margin-bottom: 4px;">
                            Your card is attached below
                          </div>
                          <div style="font-size: 13px; color: #786b59; line-height: 1.5;">
                            Open <strong>birthday-card.pdf</strong> attached to this email to see your full card, photo, and message!
                          </div>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <!-- Simple Footer -->
                <tr>
                  <td style="background-color: #faf7f2; padding: 14px 28px; text-align: center; border-top: 1px solid #eee8df;">
                    <p style="margin: 0; font-size: 12px; color: #a0aec0;">
                      Sent via Send an Owl • Digital greeting cards delivered with care
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
      </html>
    HTML

    # Build multipart/alternative part for the text and HTML body
    alt_part = Mail::Part.new do
      content_type 'multipart/alternative'
    end

    alt_part.add_part(Mail::Part.new do
      content_type 'text/plain; charset=UTF-8'
      body plain_text
    end)

    alt_part.add_part(Mail::Part.new do
      content_type 'text/html; charset=UTF-8'
      body html_text
    end)

    # Add alternative body and PDF attachment to root message (multipart/mixed)
    mail.add_part(alt_part)
    mail.add_file filename: 'birthday-card.pdf', content: File.binread(pdf_path)

    $stderr.puts "[INFO] Dispatching email to: #{mail.to.inspect} from: #{mail.from.inspect}"

    # Use media upload path — sends the raw RFC 822 message directly as a
    # stream, which is more reliable than base64-encoding into the JSON body
    # (especially for messages with binary attachments).
    service.send_user_message(
      'me',
      Google::Apis::GmailV1::Message.new,
      upload_source: StringIO.new(mail.encoded),
      content_type: 'message/rfc822'
    )
  end

  def self.configured?
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN].all? do |key|
      ENV[key] && !ENV[key].strip.empty?
    end
  end

  private

  def self.build_credentials
    Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      refresh_token: ENV['GOOGLE_REFRESH_TOKEN'],
      scope: SCOPES
    )
  end
end
