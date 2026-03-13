require_relative "../services/smb_client"
require "tmpdir"

class NasCopyJob < ApplicationJob
  queue_as :default

  NAS_COPY_TIMEOUT = 600 # 10 minutes — enough for large files over LAN

  def perform(transfer_id)
    transfer = NasCopyTransfer.find_by(id: transfer_id)
    return unless transfer

    destination_account = transfer.nas_account
    unless destination_account
      transfer.update!(status: "failed", error: "NAS account missing")
      return
    end

    result = if transfer.source_nas_account_id.present?
               copy_from_nas_source(transfer, destination_account)
             else
               upload_local_source(transfer, destination_account)
             end

    if result[:success]
      transfer.update!(status: "done")
    else
      raw = result[:error].to_s
      msg = if raw.include?("NT_STATUS_ACCESS_DENIED")
              "Access denied — check NAS share ACLs."
            else
              raw.lines.reject(&:blank?).last&.strip || "Copy failed"
            end
      transfer.update!(status: "failed", error: msg)
    end
  rescue => e
    transfer&.update(status: "failed", error: e.message)
  end

  private

  def upload_local_source(transfer, destination_account)
    SmbClient.put(
      share:        destination_account.username,
      local_path:   transfer.local_path,
      remote_path:  transfer.nas_path,
      nas_filename: transfer.nas_filename,
      username:     destination_account.username,
      password:     destination_account.password,
      timeout:      NAS_COPY_TIMEOUT
    )
  end

  def copy_from_nas_source(transfer, destination_account)
    source_account = transfer.source_nas_account
    return { success: false, error: "Source NAS account missing" } unless source_account

    source_nas_path = transfer.source_nas_path.to_s
    return { success: false, error: "Source NAS path missing" } if source_nas_path.blank?

    Dir.mktmpdir("nas_copy_job") do |dir|
      staged_path = File.join(dir, transfer.nas_filename.presence || File.basename(source_nas_path))

      download_result = SmbClient.get(
        share:       source_account.username,
        remote_path: source_nas_path,
        local_path:  staged_path,
        username:    source_account.username,
        password:    source_account.password,
        timeout:     NAS_COPY_TIMEOUT
      )

      if download_result[:success]
        SmbClient.put(
          share:        destination_account.username,
          local_path:   staged_path,
          remote_path:  transfer.nas_path,
          nas_filename: transfer.nas_filename,
          username:     destination_account.username,
          password:     destination_account.password,
          timeout:      NAS_COPY_TIMEOUT
        )
      else
        download_result
      end
    end
  end
end
