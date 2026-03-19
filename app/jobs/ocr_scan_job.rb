# 定时扫描 DSM 指定文件夹中的新截图，使用 AI 识别消费记录并自动记账。
# 通过 file_hash 防止重复处理，处理完的文件移动到 processed/ 子目录。
class OcrScanJob < ApplicationJob
  queue_as :low_priority

  SUPPORTED_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze
  MAX_FILES_PER_SCAN = 20

  def perform
    Family.where(ocr_scan_enabled: true).where.not(ocr_scan_folder: [ nil, "" ]).find_each do |family|
      process_family(family)
    rescue => e
      Rails.logger.error "[OcrScanJob] Failed for family #{family.id}: #{e.message}"
    end
  end

  private

    def process_family(family)
      folder = family.ocr_scan_folder
      unless Dir.exist?(folder)
        Rails.logger.warn "[OcrScanJob] Folder not found: #{folder}"
        return
      end

      account = family.accounts.find_by(id: family.ocr_scan_account_id) || family.accounts.visible.first
      return unless account

      FileUtils.mkdir_p(File.join(folder, "processed"))
      FileUtils.mkdir_p(File.join(folder, "failed"))

      new_files = scan_new_files(family, folder)
      return if new_files.empty?

      recognizer = OcrReceiptRecognizer.new(family)

      new_files.each do |file_path|
        process_file(family, account, recognizer, file_path, folder)
      end

      family.update!(ocr_scan_last_at: Time.current)
    end

    def scan_new_files(family, folder)
      existing_hashes = family.ocr_scan_records.pluck(:file_hash).to_set

      Dir.glob(File.join(folder, "*"))
        .select { |f| File.file?(f) && SUPPORTED_EXTENSIONS.include?(File.extname(f).downcase) }
        .reject { |f| existing_hashes.include?(file_hash(f)) }
        .sort_by { |f| File.mtime(f) }
        .first(MAX_FILES_PER_SCAN)
    end

    def process_file(family, account, recognizer, file_path, folder)
      hash = file_hash(file_path)

      record = family.ocr_scan_records.create!(
        file_name: File.basename(file_path),
        file_path: file_path,
        file_hash: hash,
        status: "processing"
      )

      result = recognizer.recognize(file_path)

      if result && result[:amount].to_f > 0
        entry = create_entry(family, account, result)
        record.update!(
          status: "success",
          ocr_result: result,
          entry: entry,
          processed_at: Time.current
        )
        FileUtils.mv(file_path, File.join(folder, "processed", File.basename(file_path)))

        log_action(family, "ocr_create_transaction", {
          file: record.file_name,
          amount: result[:amount],
          merchant: result[:merchant],
          category: result[:category]
        })
      else
        record.update!(
          status: result.nil? ? "failed" : "skipped",
          ocr_result: result || {},
          error_message: result.nil? ? "AI识别失败" : "非消费截图",
          processed_at: Time.current
        )
        FileUtils.mv(file_path, File.join(folder, "failed", File.basename(file_path)))
      end
    rescue => e
      record&.update(status: "failed", error_message: e.message, processed_at: Time.current)
      FileUtils.mv(file_path, File.join(folder, "failed", File.basename(file_path))) rescue nil
      Rails.logger.error "[OcrScanJob] #{file_path}: #{e.message}"
    end

    def create_entry(family, account, result)
      date = Date.parse(result[:date]) rescue Date.current

      category = if result[:category].present?
        family.categories.find_or_create_by!(name: result[:category]) do |c|
          c.color = Category::COLORS.sample
          c.lucide_icon = "circle-dashed"
        end
      end

      name = [ result[:merchant], result[:description] ].compact.reject(&:blank?).first || "OCR识别消费"

      account.entries.create!(
        date: date,
        name: name,
        amount: result[:amount].to_d,
        currency: account.currency,
        entryable: Transaction.new(category: category)
      )
    end

    def file_hash(path)
      Digest::SHA256.file(path).hexdigest
    end

    def log_action(family, tool_name, params)
      AgentAction.create!(
        family: family,
        tool_name: tool_name,
        params: params,
        status: "executed",
        permission_level: "auto",
        source: "ocr",
        executed_at: Time.current
      )
    end
end
