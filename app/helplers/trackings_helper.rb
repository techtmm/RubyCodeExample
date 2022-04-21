module TrackingsHelper
  def label_or_name(po)
    po['label'].blank? ? ' ' : po['label']
  end

  # Helpers for DOCX export

  def extend_and_flush_table(xml, collection, columns, row_size, entire_page_width, i)
    space_left = 100 - row_size

    # add empty cell to the rest of row
    if space_left > 0
      collection["col#{i}".to_sym] = { }
      columns << { align: 'top', twips: entire_page_width * space_left / 100, cell_contents: "NDA_#{i}.xml" }
    end

    flush_table(xml, collection, columns)
  end

  def flush_table(xml, collection, columns)
    return if columns.empty?

    xml << table(
      :collection => [collection],
      :obj_name => :item,
      :header_row => nil,
      :row => {:height => {:twips => 432}, :hRule => 'auto'},
      :cols => columns
    )
    # add line after table
    xml.w :p do
      xml.w :r do
        xml.w :t, ''
      end
    end
  end

  def page_break(xml)
    xml.w :p do
      xml.w :r do
        xml.w :br, "w:type" => "page"
      end
    end
  end

  def item_font_size(size, field_type)
    case field_type
    when 'header_field'
      header_font_size(size)
    when 'header2_field'
      header2_font_size(size)
    else
      font_size(size)
    end
  end

  def font_size(size)
    sizes = { small: 18, medium: 22, large: 30 }
    sizes[size.to_sym] or sizes[:small]
  end

  def html_font_size(size)
    sizes = { small: 10, medium: 12, large: 16 }
    sizes[size.to_sym] or sizes[:small]
  end

  def header_font_size(size)
    sizes = { small: 24, medium: 28, large: 36 }
    sizes[size.to_sym] or sizes[:small]
  end

  def header2_font_size(size)
    sizes = { small: 20, medium: 24, large: 32 }
    sizes[size.to_sym] or sizes[:small]
  end

  def field_width(width)
    cols_widths = { small: 33, medium: 50, large: 66, x_large: 100 }
    cols_widths[width.to_sym] or cols_widths[:small]
  end

  def align(po)
    po['properties']['align'] or 'left'
  end

  def item_font_color(field_type)
    case field_type
    when 'header_field'
      header_color
    when 'header2_field'
      header2_color
    else
      primary_color
    end
  end

  def header_color
    @submission[:lead].header_1_color
  end

  def header2_color
    @submission[:lead].header_2_color
  end

  def primary_color
    @submission[:lead].primary_text_color
  end

  def secondary_color
    @submission[:lead].secondary_text_color
  end

  def image_scale_factor(field_size)
    field_width(field_size) > 50 ? 50 : 100
  end

  def cell_bg_color(index)
    index.odd? ? "EEEEF4" : "auto"
  end

  # Nokogiri unescapes more characters than default tool.
  def unescape_html(string)
    Nokogiri::HTML.fragment(string).to_xhtml
  end

  def header_or_footer_content(xml, header_or_footer, position)
    custom_export_texts = @submission[:lead].custom_export_texts.try(:to_hash)
    return '' unless custom_export_texts.is_a?(Hash)
    value = custom_export_texts.dig(header_or_footer, position)

    case value
    when nil
      xml.w :t, ''
    when 'page_number'
      xml.w :t, "#{I18n.t('NDA')} ", 'xml:space' => 'preserve'
      xml.w :pgNum
    when 'project_name'
      xml.w :t, @submission[:lead].name, 'xml:space' => 'preserve'
    else
      xml.w :t, localized_header_or_footer_value(value)
    end
  end

  # Localizes value defined in Lead#custom_export_texts options.
  def localized_header_or_footer_value(value)
    vars = { scope: 'NDA', default: value }
    date = case value
           when 'create_date'
             I18n.l(@submission[:tracking].created_at, format: :date_short) rescue ''
           when 'change_date'
             I18n.l(@submission[:tracking].changed_at, format: :date_short) rescue ''
           else
             ''
           end
    vars.merge!(date: date) unless date.blank?
    I18n.t(value.to_sym, vars)
  end

  def contact_picker_entry(xml, value, item)
    xml.w :r do
      xml.w :rPr do
        xml.w :color, 'w:val' => secondary_color
        xml.w :sz, 'w:val' => font_size(item['properties']['font_size'])
      end
      xml.w :t, value, 'xml:space' => 'preserve'
    end
    xml.w :r do
      xml.w :br
    end
  end
end
