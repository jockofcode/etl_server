require "fileutils"
require "find"
require "cgi"
require "open3"
require "digest"
require_relative "../services/smb_client"

class FilesController < ApplicationController
  TEXT_PREVIEW_EXTS = %w[
    txt md log csv
    rb py js ts jsx tsx html css json yml yaml sh go rs swift
    java c cpp h cs php erb haml slim
  ].freeze

  before_action :require_browser_auth
  skip_before_action :require_browser_auth, only: [:logout]

  # GET /
  def index
    render html: render_desktop_page.html_safe, content_type: "text/html"
  end

  # GET /list?path=
  def list
    dir_param  = params[:path].to_s.strip.delete_prefix("/").delete_suffix("/")
    browse_dir = resolve_dir(dir_param)
    items      = browse_dir.exist? ? list_dir(browse_dir) : []
    render json: {
      items: items.map { |i| i.merge(mtime: i[:mtime]&.iso8601) },
      path:  dir_param
    }
  end

  # POST /upload?path=
  def upload
    uploaded = params[:file]
    unless uploaded.is_a?(ActionDispatch::Http::UploadedFile)
      render json: { error: "No file" }, status: :bad_request and return
    end

    safe_name = File.basename(uploaded.original_filename)
    if safe_name.blank? || safe_name.start_with?(".")
      render json: { error: "Invalid filename" }, status: :bad_request and return
    end

    dest_dir = resolve_dir(params[:path])
    FileUtils.mkdir_p(dest_dir)
    FileUtils.cp(uploaded.tempfile.path, dest_dir.join(safe_name))
    render json: { ok: true, name: safe_name }
  end

  # POST /mkdir  body: { path: "relative/from/root/newdir" }
  def mkdir
    path = params[:path].to_s.strip
    return render json: { error: "Path required" }, status: :bad_request if path.blank?

    dir_path = safe_sub_path(path)
    return render json: { error: "Invalid path" }, status: :bad_request  unless dir_path
    return render json: { error: "Already exists" }, status: :conflict   if dir_path.exist?

    FileUtils.mkdir_p(dir_path)
    render json: { ok: true }
  end

  # POST /move  body: { items: [...], destination: "path" }
  def move
    items       = Array(params[:items]).map(&:to_s).reject(&:blank?)
    destination = params[:destination].to_s.strip
    dest        = destination.blank? ? current_user_dir : safe_sub_path(destination)
    return render json: { error: "Invalid destination" }, status: :bad_request unless dest&.directory?

    moved = 0
    items.each do |item_rel|
      src = safe_user_path(item_rel)
      next unless src&.exist?
      target = dest.join(src.basename)
      next if target == src
      FileUtils.mv(src.to_s, target.to_s)
      moved += 1
    end
    render json: { ok: true, moved: moved }
  end

  # GET /info?path=
  def info
    path_param = params[:path].to_s
    target     = path_param.blank? ? current_user_dir : safe_sub_path(path_param)
    return render json: { error: "Not found" }, status: :not_found unless target&.exist?

    file_count = dir_count = total_size = 0
    Find.find(target.to_s) do |p|
      next if p == target.to_s
      if File.directory?(p)
        dir_count  += 1
      else
        file_count += 1
        total_size += (File.size(p) rescue 0)
      end
    end
    render json: { files: file_count, dirs: dir_count, size: total_size }
  end

  # GET /dirs  — full directory tree for the move modal
  def dirs
    FileUtils.mkdir_p(current_user_dir)
    render json: collect_dirs(current_user_dir, current_user_dir)
  end

  # GET /download/*path
  def download
    path = safe_user_path(params[:path].to_s)
    return head(:not_found) unless path&.exist? && path.file?
    send_file path.to_s, disposition: download_disposition
  end

  # DELETE /delete/*path
  def destroy
    path = safe_user_path(params[:path].to_s)
    return render json: { error: "Not found" }, status: :not_found unless path&.exist?
    path.directory? ? FileUtils.rm_rf(path.to_s) : File.delete(path.to_s)
    render json: { ok: true }
  end

  # GET /thumb/*path — first-page JPEG thumbnail for a PDF (cached on disk)
  def thumb
    path = safe_user_path(params[:path].to_s)
    return head(:not_found) unless path&.exist? && path.file?

    ext    = path.extname.delete_prefix(".").downcase
    is_pdf  = ext == "pdf"
    is_text = TEXT_PREVIEW_EXTS.include?(ext)
    return head(:unsupported_media_type) unless is_pdf || is_text

    cache_dir = Rails.root.join("storage", "thumbs", @current_user.username.to_s)
    FileUtils.mkdir_p(cache_dir)
    cache_key  = Digest::SHA256.hexdigest(path.to_s)
    cache_path = cache_dir.join("#{cache_key}.jpg")

    unless cache_path.exist?
      if is_pdf
        prefix = cache_dir.join(cache_key).to_s
        _, _, status = Open3.capture3(
          "pdftoppm", "-r", "108", "-f", "1", "-l", "1", "-jpeg", "-jpegopt", "quality=82",
          path.to_s, prefix
        )
        generated = Dir["#{prefix}*.jpg"].min
        return head(:unprocessable_entity) unless status.success? && generated && File.exist?(generated)
        FileUtils.mv(generated, cache_path.to_s)
      else
        return head(:unprocessable_entity) unless generate_text_thumb(path.to_s, cache_path.to_s)
      end
    end

    send_file cache_path.to_s, type: "image/jpeg", disposition: "inline"
  end

  # ── Settings actions ───────────────────────────────────────────────────────

  # PATCH /settings/password
  def settings_password
    current_password = params[:current_password].to_s
    new_password     = params[:new_password].to_s

    if current_password.blank? || new_password.blank?
      return render json: { error: "Current and new passwords are required" }, status: :unprocessable_entity
    end

    unless @current_user.authenticate(current_password)
      return render json: { error: "Current password is incorrect" }, status: :unprocessable_entity
    end

    if new_password.length < 8
      return render json: { error: "New password must be at least 8 characters" }, status: :unprocessable_entity
    end

    if @current_user.update(password: new_password)
      render json: { ok: true }
    else
      render json: { error: @current_user.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  # ── NAS (SMB) actions ──────────────────────────────────────────────────────

  # GET /logout
  def logout
    cookies.delete(:_etl_browser_uid, domain: ".cnxkit.com")
    redirect_to "https://etl.cnxkit.com/", allow_other_host: true
  end

  # GET /nas/status
  def nas_status
    sync_legacy_nas_account!
    render json: serialized_nas_status
  end

  # PUT /nas/credentials  body: { username:, password: }
  def nas_credentials
    sync_legacy_nas_account!
    username = normalized_nas_username
    password = nas_password
    return render json: { error: "Username required" }, status: :bad_request if username.blank?
    return render json: { error: "Password required" }, status: :bad_request if password.blank?
    return unless test_nas_credentials(username, password)

    account = @current_user.nas_accounts.find_or_initialize_by(username: username)
    account.password = password
    return render_nas_account_validation_error(account) unless account.save

    render json: { ok: true, account: serialize_nas_account(account) }.merge(serialized_nas_status)
  end

  # POST /nas/accounts  body: { username:, password: }
  def nas_account_create
    sync_legacy_nas_account!
    username = normalized_nas_username
    password = nas_password

    return render json: { error: "Username required" }, status: :bad_request if username.blank?
    return render json: { error: "Password required" }, status: :bad_request if password.blank?
    return render json: { error: "NAS account already linked" }, status: :conflict if @current_user.nas_accounts.exists?(username: username)
    return unless test_nas_credentials(username, password)

    account = @current_user.nas_accounts.new(username: username, password: password)
    return render_nas_account_validation_error(account) unless account.save

    render json: { ok: true, account: serialize_nas_account(account) }.merge(serialized_nas_status), status: :created
  end

  # PATCH /nas/accounts/:id  body: { password: }
  def nas_account_update
    account = find_managed_nas_account
    return if performed?

    password = nas_password
    return render json: { error: "Password required" }, status: :bad_request if password.blank?
    return unless test_nas_credentials(account.username, password)

    account.password = password
    return render_nas_account_validation_error(account) unless account.save

    render json: { ok: true, account: serialize_nas_account(account) }.merge(serialized_nas_status)
  end

  # DELETE /nas/accounts/:id
  def nas_account_destroy
    account = find_managed_nas_account
    return if performed?

    account.destroy!
    render json: { ok: true }.merge(serialized_nas_status)
  end

  # GET /nas/browse?path=
  def nas_browse
    account = selected_nas_account
    return if performed?

    path   = params[:path].to_s.strip
    result = SmbClient.list(
      share:    account.username,
      path:     path,
      username: account.username,
      password: account.password
    )

    if result[:success]
      render json: { items: result[:items], path: path, account: serialize_nas_account(account) }
    else
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Browse failed"
      render json: { error: msg }, status: :unprocessable_entity
    end
  end

  # GET /nas/download/*path — proxy a NAS file to the browser
  def nas_download
    account = selected_nas_account
    return if performed?

    nas_path = params[:path].to_s.strip
    return head(:bad_request) if nas_path.blank? || nas_path =~ /["\\\x00]/

    filename = File.basename(nas_path)
    tf = Tempfile.new(["nas_dl", File.extname(filename)])
    tf.close

    result = SmbClient.get(
      share:       account.username,
      remote_path: nas_path,
      local_path:  tf.path,
      username:    account.username,
      password:    account.password
    )

    unless result[:success]
      tf.unlink
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Download failed"
      return render json: { error: msg }, status: :unprocessable_entity
    end

    data = File.binread(tf.path)
    mime_type = Marcel::MimeType.for(Pathname.new(tf.path), name: filename)
    tf.unlink
    send_data data, filename: filename, disposition: download_disposition, type: mime_type
  end

  # GET /nas/thumb/*path?account_id= — first-page JPEG thumbnail for a NAS PDF (cached)
  def nas_thumb
    account = selected_nas_account
    return if performed?

    nas_path = params[:path].to_s.strip
    return head(:bad_request) if nas_path.blank? || nas_path =~ /["\\\x00]/

    ext     = File.extname(nas_path).delete_prefix(".").downcase
    is_pdf  = ext == "pdf"
    is_text = TEXT_PREVIEW_EXTS.include?(ext)
    return head(:unsupported_media_type) unless is_pdf || is_text

    cache_dir = Rails.root.join("storage", "thumbs", "nas", @current_user.username.to_s)
    FileUtils.mkdir_p(cache_dir)
    cache_key  = Digest::SHA256.hexdigest("#{account.id}:#{nas_path}")
    cache_path = cache_dir.join("#{cache_key}.jpg")

    unless cache_path.exist?
      tf = Tempfile.new(["nas_dl", ".#{ext}"])
      tf.close

      result = SmbClient.get(
        share:       account.username,
        remote_path: nas_path,
        local_path:  tf.path,
        username:    account.username,
        password:    account.password
      )

      unless result[:success]
        tf.unlink
        return head(:unprocessable_entity)
      end

      if is_pdf
        prefix = cache_dir.join(cache_key).to_s
        _, _, status = Open3.capture3(
          "pdftoppm", "-r", "108", "-f", "1", "-l", "1", "-jpeg", "-jpegopt", "quality=82",
          tf.path, prefix
        )
        tf.unlink
        generated = Dir["#{prefix}*.jpg"].min
        return head(:unprocessable_entity) unless status.success? && generated && File.exist?(generated)
        FileUtils.mv(generated, cache_path.to_s)
      else
        ok = generate_text_thumb(tf.path, cache_path.to_s)
        tf.unlink
        return head(:unprocessable_entity) unless ok
      end
    end

    send_file cache_path.to_s, type: "image/jpeg", disposition: "inline"
  end

  # POST /nas/copy-from-nas  body: { nas_path:, local_path: (dest dir, optional) }
  def nas_copy_from_nas
    account = selected_nas_account
    return if performed?

    nas_path = params[:nas_path].to_s.strip
    return render json: { error: "Invalid NAS path" }, status: :bad_request if nas_path.blank? || nas_path =~ /["\\\x00]/

    filename = File.basename(nas_path)
    return render json: { error: "Invalid filename" }, status: :bad_request if filename.blank? || filename =~ /["\\\x00]/

    dest_dir = resolve_dir(params[:local_path].to_s)
    FileUtils.mkdir_p(dest_dir)
    local_path = dest_dir.join(filename)

    result = SmbClient.get(
      share:       account.username,
      remote_path: nas_path,
      local_path:  local_path.to_s,
      username:    account.username,
      password:    account.password
    )

    if result[:success]
      render json: { ok: true, saved_to: local_path.relative_path_from(current_user_dir).to_s }
    else
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Copy failed"
      render json: { error: msg }, status: :unprocessable_entity
    end
  end

  # POST /nas/mkdir  body: { path: "folder/sub" }
  def nas_mkdir
    account = selected_nas_account
    return if performed?

    path = params[:path].to_s.strip
    return render json: { error: "Path required" }, status: :bad_request if path.blank?
    return render json: { error: "Invalid path" }, status: :bad_request if path =~ /["\\\x00]/

    result = SmbClient.mkdir(
      share:    account.username,
      path:     path,
      username: account.username,
      password: account.password
    )

    if result[:success]
      render json: { ok: true }
    else
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Failed to create folder"
      render json: { error: msg }, status: :unprocessable_entity
    end
  end

  # POST /nas/copy  body: { local_path:, nas_path: }
  def nas_copy
    account = selected_nas_account
    return if performed?

    source_nas_account = nil
    source_nas_path = nil

    if params[:source_account_id].present? || params[:source_nas_path].present?
      source_nas_account = selected_source_nas_account
      return if performed?

      source_nas_path = params[:source_nas_path].to_s.strip
      return render json: { error: "Invalid source NAS path" }, status: :bad_request if source_nas_path.blank? || source_nas_path =~ /["\\\x00]/

      source_path = source_nas_path
      source_filename = File.basename(source_nas_path)
    else
      local = safe_user_path(params[:local_path].to_s)
      return render json: { error: "Invalid local path" }, status: :bad_request unless local&.file?

      source_path = local.to_s
      source_filename = local.basename.to_s
    end

    nas_path = params[:nas_path].to_s.strip
    return render json: { error: "Invalid NAS path" }, status: :bad_request if nas_path =~ /["\\\x00]/

    # Windows/NTFS forbids: \ / : * ? " < > | — replace with underscores so the
    # upload doesn't get NT_STATUS_ACCESS_DENIED for characters like ':' in timestamps.
    nas_filename = source_filename.gsub(/[\\\/:\*\?"<>|]/, "_")

    transfer = NasCopyTransfer.create!(
      user:               @current_user,
      nas_account:        account,
      source_nas_account: source_nas_account,
      source_nas_path:    source_nas_path,
      local_path:         source_path,
      nas_path:           nas_path,
      nas_filename:       nas_filename,
      status:             "queued"
    )
    NasCopyJob.perform_later(transfer.id)

    render json: { queued: true, transfer_id: transfer.id, nas_filename: nas_filename,
                   renamed: nas_filename != source_filename,
                   account: serialize_nas_account(account) }
  end

  # GET /nas/transfers
  def nas_transfers
    sync_legacy_nas_account!
    transfers = @current_user.nas_copy_transfers.recent.map do |t|
      {
        id:           t.id,
        account_id:   t.nas_account_id,
        account_username: t.nas_account&.username,
        filename:     File.basename(t.source_path),
        nas_filename: t.nas_filename,
        nas_path:     t.nas_path,
        status:       t.status,
        error:        t.error,
        created_at:   t.created_at.iso8601
      }
    end
    render json: { transfers: transfers }
  end

  private

  def generate_text_thumb(source_path, dest_path)
    lines = File.readlines(source_path, encoding: "utf-8:binary", invalid: :replace, undef: :replace)
                .first(60)
                .map { |l| l.rstrip[0, 95] }
                .join("\n")
    Tempfile.create(["thumb_text", ".txt"]) do |tf|
      tf.write(lines)
      tf.flush
      _, _, status = Open3.capture3(
        "convert", "-background", "white", "-fill", "#374151",
        "-font", "Courier", "-pointsize", "8", "-size", "360x460",
        "caption:@#{tf.path}", dest_path
      )
      status.success?
    end
  end

  def normalized_nas_username
    params[:username].to_s.strip.downcase
  end

  def nas_password
    params[:password].to_s
  end

  def test_nas_credentials(username, password)
    result = SmbClient.test(share: username, username: username, password: password)
    return true if result[:success]

    msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Connection failed"
    render json: { error: "Could not connect: #{msg}" }, status: :unprocessable_entity
    false
  end

  def sync_legacy_nas_account!
    return unless @current_user.smb_connected?

    username = @current_user.smb_username.to_s.strip.downcase
    return if username.blank? || @current_user.nas_accounts.exists?(username: username)

    @current_user.nas_accounts.create(
      username: username,
      password_ciphertext: @current_user.smb_password_ciphertext
    )
  end

  def render_nas_account_validation_error(account)
    render json: {
      error: account.errors.full_messages.to_sentence.presence || "Invalid NAS account"
    }, status: :unprocessable_entity
  end

  def serialized_nas_status
    accounts = @current_user.nas_accounts.order(:username).to_a
    {
      connected: accounts.any?,
      username: accounts.first&.username,
      accounts: accounts.map { |account| serialize_nas_account(account) }
    }
  end

  def serialize_nas_account(account)
    { id: account.id, username: account.username }
  end

  def find_managed_nas_account
    sync_legacy_nas_account!
    account = @current_user.nas_accounts.find_by(id: params[:id])
    return account if account

    render json: { error: "NAS account not found" }, status: :not_found
    nil
  end

  def selected_nas_account
    sync_legacy_nas_account!
    accounts = @current_user.nas_accounts.order(:username)
    account_id = params[:account_id].presence

    if account_id.blank?
      return accounts.first if accounts.one?
      return render(json: { error: "NAS not configured" }, status: :unauthorized) if accounts.none?
      return render(json: { error: "NAS account required" }, status: :bad_request)
    end

    account = accounts.find_by(id: account_id)
    return account if account

    render json: { error: "NAS account not found" }, status: :not_found
    nil
  end

  def selected_source_nas_account
    sync_legacy_nas_account!
    source_account_id = params[:source_account_id].presence
    return render(json: { error: "Source NAS account required" }, status: :bad_request) if source_account_id.blank?

    account = @current_user.nas_accounts.find_by(id: source_account_id)
    return account if account

    render json: { error: "Source NAS account not found" }, status: :not_found
    nil
  end

  def download_disposition
    params[:inline].present? ? "inline" : "attachment"
  end

  # ── Auth ────────────────────────────────────────────────────────────────────

  def require_browser_auth
    uid = cookies.signed[:_etl_browser_uid]
    @current_user = User.find_by(id: uid) if uid.present?
    return if @current_user

    return_url = "https://files.cnxkit.com/"
    redirect_to "https://etl.cnxkit.com/?redirect=#{CGI.escape(return_url)}#/login",
                allow_other_host: true, status: :found
  end

  # ── Path helpers ─────────────────────────────────────────────────────────────

  def current_user_dir
    Rails.root.join("storage", "files", @current_user.username.to_s)
  end

  # Any relative path within the user's root (may be the root itself).
  def safe_sub_path(rel_path)
    return current_user_dir if rel_path.blank?
    clean = Pathname.new(rel_path).cleanpath
    return nil if clean.absolute? || clean.each_filename.first == ".."
    path = current_user_dir.join(clean)
    return nil unless path.to_s.start_with?(current_user_dir.to_s + "/")
    path
  end

  # Same as safe_sub_path but refuses the user root (prevents operating on root itself).
  def safe_user_path(rel_path)
    return nil if rel_path.blank?
    path = safe_sub_path(rel_path)
    path unless path == current_user_dir
  end

  # Returns the directory for a path param, falling back to user root.
  def resolve_dir(path_param)
    dir = safe_sub_path(path_param.to_s.strip)
    (dir&.directory? ? dir : nil) || current_user_dir
  end

  # ── Directory listing ────────────────────────────────────────────────────────

  def list_dir(dir)
    dir.children
       .reject  { |c| c.basename.to_s.start_with?(".") }
       .map     { |e|
                   size = if e.file?
                            e.size
                          else
                            total = 0
                            Find.find(e.to_s) { |p| total += File.size(p) rescue 0 unless File.directory?(p) }
                            total
                          end
                   { name: e.basename.to_s, type: e.directory? ? "dir" : "file",
                     size: size, mtime: e.mtime }
                 }
       .sort_by { |e| [e[:type] == "dir" ? 0 : 1, e[:name].downcase] }
  end

  def collect_dirs(dir, root, depth = 0, result = [])
    result << { name: depth == 0 ? "Home" : dir.basename.to_s,
                path: depth == 0 ? "" : dir.relative_path_from(root).to_s,
                depth: depth }
    return result if depth >= 6
    dir.children.select(&:directory?)
       .sort_by { |d| d.basename.to_s.downcase }
       .each    { |d| collect_dirs(d, root, depth + 1, result) }
    result
  rescue
    result
  end

  # ── File type helpers ────────────────────────────────────────────────────────

  IMAGE_EXTS = %w[jpg jpeg png gif webp svg bmp ico avif].freeze

  def image_file?(name)
    IMAGE_EXTS.include?(File.extname(name).delete_prefix(".").downcase)
  end

  def file_type_badge(name)
    ext = File.extname(name).delete_prefix(".").downcase
    case ext
    when "pdf"                                               then ["#dc2626", "PDF"]
    when "doc", "docx"                                       then ["#2563eb", "DOC"]
    when "xls", "xlsx", "csv"                                then ["#16a34a", "XLS"]
    when "ppt", "pptx"                                       then ["#ea580c", "PPT"]
    when "zip", "tar", "gz", "rar", "7z", "bz2", "xz"       then ["#7c3aed", "ZIP"]
    when "mp4", "mov", "avi", "mkv", "webm", "m4v"          then ["#0891b2", "VID"]
    when "mp3", "wav", "ogg", "flac", "m4a", "aac"          then ["#db2777", "AUD"]
    when "rb", "py", "js", "ts", "jsx", "tsx", "html", "css",
         "json", "yml", "yaml", "sh", "bash", "php", "go",
         "rs", "swift", "kt", "java", "c", "cpp", "h"       then ["#1e293b", "CODE"]
    when "txt", "md", "log", "rtf"                          then ["#6b7280", "TXT"]
    else
      ["#9ca3af", ext.upcase.first(4).presence || "FILE"]
    end
  end

  def humanize_bytes(bytes)
    return "0 B" if bytes.nil? || bytes == 0
    units = %w[B KB MB GB TB]
    exp   = [(Math.log(bytes) / Math.log(1024)).floor, units.length - 1].min
    "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
  end

  # ── HTML rendering ───────────────────────────────────────────────────────────

  def render_desktop_page
    username = CGI.escapeHTML(@current_user.username.to_s)
    css = File.read(Rails.root.join("public", "files.css")).gsub("</style", "<\\/style")
    js  = File.read(Rails.root.join("public", "files.js")).gsub("</script", "<\\/script")
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Files &mdash; #{username}</title>
        <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>&#x1F4C1;</text></svg>">
        <style>
#{css}
        </style>
      </head>
      <body>
        <aside id="sidebar">
          <div class="sb-header">&#128193; Files</div>
          <div class="sb-section-label">Locations</div>
          <div id="sidebarLocations">
            <button class="sidebar-item" id="homeBtn" onclick="openOrFocusWindow('local','','Home')">
              <span class="sb-icon">&#127968;</span><span>Home</span>
            </button>
            <div id="homeSidebarWindows" class="sidebar-sublist"></div>
          </div>
          <div class="sb-spacer"></div>
          <div class="sb-section-label">NAS</div>
          <button class="sidebar-item" id="nasManageBtn" onclick="openNasManager()">
            <span class="sb-icon">&#9881;</span><span>Manage NAS Accounts</span>
          </button>
          <div id="nasSidebarAccounts" class="sidebar-sublist"></div>
          <button class="sidebar-item" onclick="openPasswordModal()">
            <span class="sb-icon">&#128274;</span><span>Change Password</span>
          </button>
          <a href="/logout" class="sidebar-item" style="color:#f87171;text-decoration:none">
            <span class="sb-icon">&#10148;</span><span>Logout</span>
          </a>
          <div class="sb-username">#{username}</div>
        </aside>
        <div id="desktop"></div>

        <!-- Context menus -->
        <div class="ctx" id="bgCtx">
          <button onclick="bgCtxNewFolder()">&#128193;&ensp;New Folder</button>
          <hr>
          <button id="bgCtxInfo" onclick="openInfo(null,ctxWinId)">&#8505;&ensp;Get Info</button>
        </div>
        <div class="ctx" id="itemCtx">
          <button id="ctxDownloadBtn"  onclick="ctxDownload()">&#8659;&ensp;Download</button>
          <button id="ctxNasDlBtn"     onclick="ctxDownload()">&#8659;&ensp;Download from NAS</button>
          <button id="ctxMoveBtn"      onclick="ctxMove()">&#8680;&ensp;Move&hellip;</button>
          <button id="ctxNasCopyBtn"   onclick="ctxNasCopy()">&#128421;&ensp;Copy to NAS&hellip;</button>
          <hr>
          <button id="ctxInfoBtn"      onclick="ctxInfo()">&#8505;&ensp;Get Info</button>
          <hr>
          <button id="ctxDeleteBtn"    class="danger" onclick="ctxDelete()">&#128465;&ensp;Delete</button>
        </div>

        <!-- Info modal -->
        <div class="overlay" id="infoModal" hidden>
          <div class="modal"><h3 id="infoTitle">Info</h3><div id="infoContent"></div>
            <div class="modal-actions"><button class="btn btn-secondary" onclick="closeModal('infoModal')">Close</button></div>
          </div>
        </div>
        <!-- Create Folder modal -->
        <div class="overlay" id="createDirModal" hidden>
          <div class="modal"><h3>New Folder</h3>
            <input type="text" id="newDirName" placeholder="Folder name" maxlength="128">
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('createDirModal')">Cancel</button>
              <button class="btn btn-primary"   onclick="confirmCreateDir()">Create</button>
            </div>
          </div>
        </div>
        <!-- Move modal -->
        <div class="overlay" id="moveModal" hidden>
          <div class="modal"><h3 id="moveTitle">Move to&hellip;</h3>
            <div class="dir-list" id="dirList"><div class="dir-list-loading">Loading&hellip;</div></div>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('moveModal')">Cancel</button>
              <button class="btn btn-primary" id="confirmMoveBtn" onclick="confirmMove()" disabled>Move Here</button>
            </div>
          </div>
        </div>
        <!-- NAS accounts manager modal -->
        <div class="overlay" id="nasManageModal" hidden>
          <div class="modal" style="max-width:560px">
            <h3>&#128421; Manage NAS Accounts</h3>
            <p style="font-size:.82rem;color:#6b7280;margin-bottom:.75rem">
              Link multiple NAS shares, update passwords for existing accounts, or remove linked accounts.
            </p>
            <div class="account-list" id="nasAccountsList"></div>
            <p class="field-error" id="nasManageError" hidden></p>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('nasManageModal')">Close</button>
              <button class="btn btn-primary" onclick="openNasCredentials()">Add Account</button>
            </div>
          </div>
        </div>
        <!-- NAS credentials modal -->
        <div class="overlay" id="nasCredModal" hidden>
          <div class="modal">
            <h3 id="nasCredTitle">&#128427; Link NAS Account</h3>
            <p id="nasCredDesc" style="font-size:.82rem;color:#6b7280;margin-bottom:.75rem">
              Enter a TrueNAS username and password to link an additional NAS account.
            </p>
            <label id="nasUsernameLabel">Username</label>
            <input type="text" id="nasUsernameInput" placeholder="e.g. kalob" autocomplete="off" spellcheck="false">
            <label>Password</label>
            <input type="password" id="nasPasswordInput" placeholder="NAS password" autocomplete="new-password">
            <p class="field-error" id="nasCredError" hidden></p>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('nasCredModal')">Cancel</button>
              <button class="btn btn-primary" id="nasCredSaveBtn" onclick="saveNasCredentials()">Connect</button>
            </div>
          </div>
        </div>
        <!-- NAS copy-destination modal -->
        <div class="overlay" id="nasCopyModal" hidden>
          <div class="modal" style="max-width:500px">
            <h3 id="nasCopyTitle">Copy to NAS</h3>
            <p style="font-size:.8rem;color:#6b7280;margin-bottom:.4rem">Choose a destination folder on the NAS:</p>
            <label for="nasCopyAccountSelect">NAS account</label>
            <select id="nasCopyAccountSelect" onchange="changeNasCopyAccount(this.value)"></select>
            <div class="dir-list" id="nasCopyDirList"><div class="dir-list-loading">Loading&hellip;</div></div>
            <div style="display:flex;align-items:center;gap:.4rem;padding:.4rem .1rem 0">
              <input type="text" id="nasCopyNewFolder" placeholder="New folder name&hellip;" style="flex:1;font-size:.78rem;padding:.28rem .55rem;border:1px solid #d1d5db;border-radius:5px;outline:none">
              <button class="btn btn-secondary" style="font-size:.75rem;white-space:nowrap" onclick="createNasCopyFolder()">&#128193; Create</button>
            </div>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('nasCopyModal')">Cancel</button>
              <button class="btn btn-primary" id="nasCopyConfirmBtn" onclick="confirmNasCopy()">Copy Here</button>
            </div>
          </div>
        </div>

        <!-- Change password modal -->
        <div class="overlay" id="changePasswordModal" hidden>
          <div class="modal">
            <h3>&#128274; Change Password</h3>
            <label>Current Password</label>
            <input type="password" id="currentPasswordInput" placeholder="Current password" autocomplete="current-password">
            <label>New Password</label>
            <input type="password" id="newPasswordInput" placeholder="New password (min 8 characters)" autocomplete="new-password">
            <label>Confirm New Password</label>
            <input type="password" id="confirmPasswordInput" placeholder="Confirm new password" autocomplete="new-password">
            <p class="field-error" id="passwordChangeError" hidden></p>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('changePasswordModal')">Cancel</button>
              <button class="btn btn-primary" id="changePasswordBtn" onclick="savePasswordChange()">Update Password</button>
            </div>
          </div>
        </div>

        <!-- Upload toast -->
        <div class="toast" id="toast">
          <p id="toastText">Uploading&hellip;</p>
          <div class="toast-bar"><div class="toast-fill" id="toastFill"></div></div>
        </div>
        <!-- NAS Transfers panel -->
        <div class="transfers-panel" id="transfersPanel" hidden>
          <div class="transfers-header">
            <span>&#128421; NAS Transfers</span>
            <button class="transfers-close" onclick="dismissTransfers()">&#10005;</button>
          </div>
          <div id="transfersList"></div>
        </div>

        <script>
#{js}
        </script>
      </body>
      </html>
    HTML
  end
end
