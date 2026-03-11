require_relative "../services/smb_client"

class NasCopyJob < ApplicationJob
  queue_as :default

  NAS_COPY_TIMEOUT = 600 # 10 minutes — enough for large files over LAN

  def perform(transfer_id)
    transfer = NasCopyTransfer.find_by(id: transfer_id)
    return unless transfer

    user = transfer.user

    result = SmbClient.put(
      share:        user.smb_username,
      local_path:   transfer.local_path,
      remote_path:  transfer.nas_path,
      nas_filename: transfer.nas_filename,
      username:     user.smb_username,
      password:     user.smb_password,
      timeout:      NAS_COPY_TIMEOUT
    )

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
end
