require "tempfile"
require "open3"
require "timeout"

# Wraps the system `smbclient` binary to talk to the TrueNAS SMB server.
# All public class methods return { success: bool, output: str, error: str }.
# list() additionally returns { items: [...] }.
module SmbClient
  SMB_HOST    = "truenas.local"
  SMB_TIMEOUT = 15 # seconds

  # List a directory on the share.
  # path is a slash-separated relative path within the share (empty = root).
  def self.list(share:, path:, username:, password:)
    smb_path = path.blank? ? "*" : "\"#{smb_path(path)}\\*\""
    result = run(share: share, username: username, password: password,
                 command: "ls #{smb_path}")
    return result unless result[:success]
    result.merge(items: parse_ls(result[:output]))
  end

  # Copy a local file to the share. remote_path is the destination directory
  # within the share (slash-separated, empty = root). nas_filename overrides
  # the remote filename (use to sanitize Windows-invalid characters).
  def self.put(share:, local_path:, remote_path:, username:, password:, nas_filename: nil, timeout: SMB_TIMEOUT)
    remote_file = nas_filename || File.basename(local_path)
    cd_part     = remote_path.blank? ? "" : "cd \"#{smb_path(remote_path)}\"; "
    run(share: share, username: username, password: password, timeout: timeout,
        command: "#{cd_part}put \"#{local_path}\" \"#{remote_file}\"")
  end

  # Download a file from the share to a local path.
  # remote_path is slash-separated relative path to the file within the share.
  def self.get(share:, remote_path:, local_path:, username:, password:, timeout: SMB_TIMEOUT)
    remote_dir  = File.dirname(remote_path).gsub("/", "\\")
    remote_file = File.basename(remote_path)
    local_dir   = File.dirname(local_path)
    local_file  = File.basename(local_path)

    cd_part = (remote_dir == "." || remote_dir.empty?) ? "" : "cd \"#{remote_dir}\"; "
    run(share: share, username: username, password: password, timeout: timeout,
        command: "#{cd_part}lcd \"#{local_dir}\"; get \"#{remote_file}\" \"#{local_file}\"")
  end

  # Create a directory on the share. path is slash-separated.
  def self.mkdir(share:, path:, username:, password:)
    run(share: share, username: username, password: password,
        command: "mkdir \"#{smb_path(path)}\"")
  end

  # Quick connectivity check — just lists the root of the share.
  def self.test(share:, username:, password:)
    run(share: share, username: username, password: password, command: "ls *")
  end

  def self.run(share:, username:, password:, command:, timeout: SMB_TIMEOUT)
    stdout = stderr = ""
    exit_status = nil

    with_auth_file(username, password) do |auth_file|
      Timeout.timeout(timeout) do
        stdout, stderr, exit_status = Open3.capture3(
          "smbclient", "//#{SMB_HOST}/#{share}", "-A", auth_file,
          "--option=client min protocol=SMB2",
          "-c", command
        )
      end
    end

    # smbclient often writes NT_STATUS errors to stdout, not stderr.
    # Merge both so callers always see the real error message.
    combined_error = [ stderr, stdout ].map(&:strip).reject(&:empty?).join("\n")
    { success: exit_status&.success?, output: stdout, error: combined_error }
  rescue Timeout::Error
    { success: false, output: "", error: "Connection timed out after #{timeout}s" }
  rescue => e
    { success: false, output: "", error: e.message }
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  # Write credentials to a temp file (mode 0600) and yield its path.
  def self.with_auth_file(username, password)
    tf = Tempfile.new(["smb_auth", ".conf"])
    tf.chmod(0o600)
    tf.write("username=#{username}\npassword=#{password}\ndomain=WORKGROUP\n")
    tf.flush
    tf.close
    yield tf.path
  ensure
    tf&.unlink
  end

  # Convert slash-separated path to backslash-separated SMB path.
  def self.smb_path(path)
    path.to_s.gsub("/", "\\")
  end

  # LS_ENTRY matches smbclient directory listing lines:
  #   "  filename                       DAHRS   12345  Day Mon  d hh:mm:ss yyyy"
  LS_ENTRY = /^  (.+?)\s{2,}([DAHRSN]+)\s+(\d+)\s+/

  def self.parse_ls(output)
    output.lines.filter_map do |line|
      m = line.match(LS_ENTRY)
      next unless m
      name = m[1].strip
      next if name == "." || name == ".."
      is_dir = m[2].include?("D")
      { name: name, type: is_dir ? "dir" : "file", size: m[3].to_i }
    end.sort_by { |e| [e[:type] == "dir" ? 0 : 1, e[:name].downcase] }
  end
end
