class FileTypeNormalizer
  def self.canonical(value)
    normalized = value.to_s.strip.downcase
    return if normalized.blank?

    normalized = normalized
      .split(";", 2)
      .first
      .to_s
      .strip
      .delete_prefix(".")

    return if normalized.blank?

    if normalized.include?("/")
      normalized = normalized.split("/", 2).last
    end

    return if normalized.blank?

    if normalized.length <= 4 || normalized == "pdfpage"
      normalized
    end
  end
end