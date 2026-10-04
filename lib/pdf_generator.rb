# frozen_string_literal: true

require 'grover'

module PdfGenerator
  # Card dimensions: 3:4 aspect ratio at 300 DPI equivalent
  # Using 600x800 px for the PDF viewport
  CARD_WIDTH = 600
  CARD_HEIGHT = 800

  def self.generate(html:, output_path:)
    options = {
      format: 'A5',
      print_background: true,
      prefer_css_page_size: true,
      launch_args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu'
      ],
      viewport: {
        width: CARD_WIDTH,
        height: CARD_HEIGHT
      }
    }
    options[:executable_path] = ENV['PUPPETEER_EXECUTABLE_PATH'] if ENV['PUPPETEER_EXECUTABLE_PATH']

    grover = Grover.new(html, **options)
    pdf_content = grover.to_pdf
    File.open(output_path, 'wb') { |f| f.write(pdf_content) }
    output_path
  end
end
