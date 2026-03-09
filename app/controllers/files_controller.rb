require "fileutils"
require "find"
require "cgi"
require_relative "../services/smb_client"

class FilesController < ApplicationController
  before_action :require_browser_auth

  # GET /?path=
  def index
    dir_param  = params[:path].to_s.strip.delete_prefix("/").delete_suffix("/")
    browse_dir = resolve_dir(dir_param)
    items      = browse_dir.exist? ? list_dir(browse_dir) : []
    render html: render_html_page(items, dir_param).html_safe, content_type: "text/html"
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
    send_file path.to_s, disposition: "attachment"
  end

  # DELETE /delete/*path
  def destroy
    path = safe_user_path(params[:path].to_s)
    return render json: { error: "Not found" }, status: :not_found unless path&.exist?
    path.directory? ? FileUtils.rm_rf(path.to_s) : File.delete(path.to_s)
    render json: { ok: true }
  end

  # ── NAS (SMB) actions ──────────────────────────────────────────────────────

  # GET /nas/status
  def nas_status
    render json: { connected: @current_user.smb_connected?,
                   username:  @current_user.smb_username }
  end

  # PUT /nas/credentials  body: { username:, password: }
  def nas_credentials
    username = params[:username].to_s.strip.downcase
    password = params[:password].to_s
    return render json: { error: "Username required" }, status: :bad_request if username.blank?
    return render json: { error: "Password required" }, status: :bad_request if password.blank?

    result = SmbClient.test(share: username, username: username, password: password)
    unless result[:success]
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Connection failed"
      return render json: { error: "Could not connect: #{msg}" }, status: :unprocessable_entity
    end

    @current_user.smb_username = username
    @current_user.smb_password = password
    @current_user.save!
    render json: { ok: true, username: username }
  end

  # GET /nas/browse?path=
  def nas_browse
    return render json: { error: "NAS not configured" }, status: :unauthorized unless @current_user.smb_connected?

    path   = params[:path].to_s.strip
    result = SmbClient.list(
      share:    @current_user.smb_username,
      path:     path,
      username: @current_user.smb_username,
      password: @current_user.smb_password
    )

    if result[:success]
      render json: { items: result[:items], path: path }
    else
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Browse failed"
      render json: { error: msg }, status: :unprocessable_entity
    end
  end

  # GET /nas/download/*path — proxy a NAS file to the browser
  def nas_download
    return head(:unauthorized) unless @current_user.smb_connected?

    nas_path = params[:path].to_s.strip
    return head(:bad_request) if nas_path.blank? || nas_path =~ /["\\\x00]/

    filename = File.basename(nas_path)
    tf = Tempfile.new(["nas_dl", File.extname(filename)])
    tf.close

    result = SmbClient.get(
      share:       @current_user.smb_username,
      remote_path: nas_path,
      local_path:  tf.path,
      username:    @current_user.smb_username,
      password:    @current_user.smb_password
    )

    unless result[:success]
      tf.unlink
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Download failed"
      return render json: { error: msg }, status: :unprocessable_entity
    end

    data = File.binread(tf.path)
    tf.unlink
    send_data data, filename: filename, disposition: "attachment"
  end

  # POST /nas/copy-from-nas  body: { nas_path:, local_path: (dest dir, optional) }
  def nas_copy_from_nas
    return render json: { error: "NAS not configured" }, status: :unauthorized unless @current_user.smb_connected?

    nas_path = params[:nas_path].to_s.strip
    return render json: { error: "Invalid NAS path" }, status: :bad_request if nas_path.blank? || nas_path =~ /["\\\x00]/

    filename = File.basename(nas_path)
    return render json: { error: "Invalid filename" }, status: :bad_request if filename.blank? || filename =~ /["\\\x00]/

    dest_dir = resolve_dir(params[:local_path].to_s)
    FileUtils.mkdir_p(dest_dir)
    local_path = dest_dir.join(filename)

    result = SmbClient.get(
      share:       @current_user.smb_username,
      remote_path: nas_path,
      local_path:  local_path.to_s,
      username:    @current_user.smb_username,
      password:    @current_user.smb_password
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
    return render json: { error: "NAS not configured" }, status: :unauthorized unless @current_user.smb_connected?

    path = params[:path].to_s.strip
    return render json: { error: "Path required" }, status: :bad_request if path.blank?
    return render json: { error: "Invalid path" }, status: :bad_request if path =~ /["\\\x00]/

    result = SmbClient.mkdir(
      share:    @current_user.smb_username,
      path:     path,
      username: @current_user.smb_username,
      password: @current_user.smb_password
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
    return render json: { error: "NAS not configured" }, status: :unauthorized unless @current_user.smb_connected?

    local  = safe_user_path(params[:local_path].to_s)
    return render json: { error: "Invalid local path" }, status: :bad_request unless local&.file?

    nas_path = params[:nas_path].to_s.strip
    if local.basename.to_s =~ /["\\\x00]/ || nas_path =~ /["\\\x00]/
      return render json: { error: "Path contains unsupported characters" }, status: :bad_request
    end

    result = SmbClient.put(
      share:       @current_user.smb_username,
      local_path:  local.to_s,
      remote_path: nas_path,
      username:    @current_user.smb_username,
      password:    @current_user.smb_password
    )

    if result[:success]
      render json: { ok: true }
    else
      msg = result[:error].to_s.lines.grep_v(/^$/).last&.strip || "Copy failed"
      render json: { error: msg }, status: :unprocessable_entity
    end
  end

  private

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

  def build_breadcrumb(parts)
    crumbs = [%(<a href="/" class="crumb">Home</a>)]
    parts.each_with_index do |part, i|
      path = parts[0..i].join("/")
      crumbs << '<span class="crumb-sep">›</span>'
      crumbs << %(<a href="/?path=#{ERB::Util.url_encode(path)}" class="crumb">#{CGI.escapeHTML(part)}</a>)
    end
    crumbs.join
  end

  def render_html_page(items, current_path)
    username   = CGI.escapeHTML(@current_user.username.to_s)
    path_parts = current_path.blank? ? [] : current_path.split("/").reject(&:blank?)
    breadcrumb = build_breadcrumb(path_parts)

    n_files = items.count { |i| i[:type] == "file" }
    n_dirs  = items.count { |i| i[:type] == "dir" }
    count_parts = []
    count_parts << "#{n_dirs} #{n_dirs == 1 ? 'folder' : 'folders'}"   if n_dirs  > 0
    count_parts << "#{n_files} #{n_files == 1 ? 'file' : 'files'}" if n_files > 0
    count_str = count_parts.any? ? count_parts.join(", ") : "Empty"

    tiles = items.map.with_index do |item, idx|
      name      = item[:name]
      disp      = CGI.escapeHTML(name)
      rel_path  = current_path.blank? ? name : "#{current_path}/#{name}"
      data_path = CGI.escapeHTML(rel_path)
      type_str  = item[:type]
      size_str  = humanize_bytes(item[:size])
      mtime_str = item[:mtime]&.iso8601 || ""

      preview = if type_str == "dir"
        '<span class="folder-icon">&#128193;</span>'
      elsif image_file?(name)
        %(<img src="/download/#{ERB::Util.url_encode(rel_path)}" alt="#{disp}" loading="lazy">)
      else
        color, label = file_type_badge(name)
        %(<span class="file-badge" style="background:#{color}">#{label}</span>)
      end

      <<~TILE
        <div class="tile" data-name="#{disp}" data-path="#{data_path}" data-type="#{type_str}" data-size="#{size_str}" data-mtime="#{mtime_str}" data-idx="#{idx}" onclick="handleTileClick(event,this)" ondblclick="handleTileDblClick(this)">
          <div class="tile-preview">#{preview}</div>
          <div class="tile-info">
            <div class="tile-name" title="#{disp}">#{disp}</div>
            <div class="tile-size">#{size_str}</div>
          </div>
        </div>
      TILE
    end.join

    grid_or_empty = items.any? ?
      %(<div class="file-grid" id="fileGrid">#{tiles}</div>) :
      '<div class="empty" id="fileGrid"><div class="empty-icon">&#128194;</div><p>This folder is empty</p></div>'

    current_path_json = current_path.to_json

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Files &mdash; #{username}</title>
        <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>&#x1F4C1;</text></svg>">
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f0f2f5; min-height: 100vh; }

          /* Header */
          header { background: #fff; border-bottom: 1px solid #e5e7eb; padding: 0.75rem 1.25rem; display: flex; align-items: center; gap: 0.75rem; position: sticky; top: 0; z-index: 10; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
          header h1 { font-size: 1rem; font-weight: 600; flex: 1; }
          header .meta { font-size: 0.75rem; color: #9ca3af; white-space: nowrap; }
          .nas-btn { background: #f3f4f6; border: 1px solid #e5e7eb; border-radius: 6px; padding: 0.35rem 0.75rem; font-size: 0.78rem; color: #374151; cursor: pointer; display: flex; align-items: center; gap: 0.3rem; white-space: nowrap; }
          .nas-btn:hover { background: #e5e7eb; }
          .nas-btn.connected { border-color: #86efac; background: #f0fdf4; color: #166534; }

          /* NAS modals */
          .nas-breadcrumb { font-size: 0.78rem; color: #6b7280; padding: 0.3rem 0 0.6rem; }
          .nas-crumb { color: #2563eb; cursor: pointer; }
          .nas-crumb:hover { text-decoration: underline; }
          .nas-row { display: flex; align-items: center; gap: 0.5rem; padding: 0.45rem 0.75rem; border-bottom: 1px solid #f3f4f6; font-size: 0.82rem; color: #374151; }
          .nas-row:last-child { border-bottom: none; }
          .nas-row.nas-dir { cursor: pointer; }
          .nas-row.nas-dir:hover { background: #f9fafb; }
          .nas-row-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .nas-row-size { font-size: 0.7rem; color: #9ca3af; white-space: nowrap; min-width: 52px; text-align: right; }
          .nas-row-actions { display: flex; gap: 0.3rem; flex-shrink: 0; }
          .nas-action-btn { font-size: 0.7rem; padding: 0.18rem 0.45rem; border-radius: 4px; border: 1px solid #d1d5db; background: #f9fafb; color: #374151; cursor: pointer; white-space: nowrap; }
          .nas-action-btn:hover { background: #e5e7eb; }
          .modal label { font-size: 0.82rem; color: #374151; display: block; margin-top: 0.75rem; margin-bottom: 0.25rem; }
          .modal label:first-of-type { margin-top: 0; }
          .modal input[type=password] { width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.875rem; outline: none; }
          .modal input[type=password]:focus { border-color: #3b82f6; box-shadow: 0 0 0 3px rgba(59,130,246,0.15); }
          .field-error { color: #dc2626; font-size: 0.78rem; margin-top: 0.4rem; }
          .modal-wide { max-width: 500px; }

          /* Breadcrumb */
          .breadcrumb { display: flex; align-items: center; gap: 0.25rem; flex-wrap: wrap; padding: 0.6rem 1.25rem; background: #fff; border-bottom: 1px solid #f3f4f6; font-size: 0.8rem; }
          .crumb { color: #2563eb; text-decoration: none; }
          .crumb:hover { text-decoration: underline; }
          .crumb-sep { color: #9ca3af; }

          main { padding: 1.25rem; max-width: 1600px; margin: 0 auto; }

          /* Drop zone */
          .drop-zone { background: #fff; border: 2px dashed #d1d5db; border-radius: 10px; padding: 1rem 1.25rem; display: flex; align-items: center; gap: 0.875rem; cursor: pointer; transition: border-color 0.15s, background 0.15s; margin-bottom: 1.25rem; }
          .drop-zone:hover, .drop-zone.active { border-color: #3b82f6; background: #eff6ff; }
          .drop-zone .dz-icon { font-size: 1.4rem; flex-shrink: 0; }
          .drop-zone .dz-label strong { display: block; font-size: 0.85rem; color: #374151; }
          .drop-zone .dz-label span { font-size: 0.75rem; color: #9ca3af; }
          .drop-zone input[type=file] { display: none; }

          /* Drag overlay */
          .drag-overlay { position: fixed; inset: 0; background: rgba(59,130,246,0.08); border: 4px dashed #3b82f6; z-index: 100; display: none; align-items: center; justify-content: center; pointer-events: none; }
          .drag-overlay.active { display: flex; }
          .drag-card { background: #fff; border-radius: 14px; padding: 2.5rem 3.5rem; text-align: center; box-shadow: 0 20px 60px rgba(0,0,0,0.12); }
          .drag-card .icon { font-size: 2.25rem; margin-bottom: 0.625rem; }
          .drag-card p { font-size: 1.1rem; font-weight: 600; color: #1d4ed8; }

          /* Upload toast */
          .toast { position: fixed; bottom: 1.5rem; right: 1.5rem; background: #fff; border-radius: 10px; box-shadow: 0 4px 24px rgba(0,0,0,0.12); padding: 0.875rem 1.125rem; min-width: 260px; max-width: 320px; display: none; border-left: 4px solid #3b82f6; z-index: 200; }
          .toast.visible { display: block; }
          .toast p { font-size: 0.8rem; color: #374151; margin-bottom: 0.4rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .toast-bar { height: 4px; background: #e5e7eb; border-radius: 2px; overflow: hidden; }
          .toast-fill { height: 100%; background: #3b82f6; border-radius: 2px; transition: width 0.1s linear; width: 0%; }

          /* File grid */
          .file-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 0.875rem; }

          /* Tile */
          .tile { background: #fff; border-radius: 10px; border: 2px solid transparent; cursor: pointer; overflow: hidden; transition: border-color 0.12s, box-shadow 0.12s; user-select: none; }
          .tile:hover { border-color: #bfdbfe; box-shadow: 0 2px 10px rgba(59,130,246,0.1); }
          .tile.selected { border-color: #3b82f6; box-shadow: 0 0 0 3px rgba(59,130,246,0.15); }
          .tile-preview { width: 100%; aspect-ratio: 1; display: flex; align-items: center; justify-content: center; overflow: hidden; background: #f9fafb; }
          .tile-preview img { width: 100%; height: 100%; object-fit: cover; }
          .folder-icon { font-size: 3.25rem; line-height: 1; }
          .file-badge { width: 62px; height: 62px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 0.62rem; font-weight: 800; letter-spacing: 0.08em; color: #fff; }
          .tile-info { padding: 0.4rem 0.5rem 0.35rem; border-top: 1px solid #f3f4f6; }
          .tile-name { font-size: 0.69rem; color: #1f2937; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .tile-size { font-size: 0.6rem; color: #9ca3af; margin-top: 0.1rem; }

          /* Empty */
          .empty { text-align: center; padding: 4rem 2rem; color: #9ca3af; }
          .empty-icon { font-size: 3rem; margin-bottom: 0.75rem; opacity: 0.45; }
          .empty p { font-size: 0.875rem; }

          /* Context menus */
          .ctx { position: fixed; background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.1); padding: 0.3rem 0; min-width: 160px; z-index: 500; display: none; }
          .ctx.visible { display: block; }
          .ctx button { display: flex; align-items: center; gap: 0.5rem; width: 100%; background: none; border: none; padding: 0.44rem 0.875rem; cursor: pointer; font-size: 0.81rem; color: #374151; text-align: left; }
          .ctx button:hover { background: #f9fafb; }
          .ctx hr { border: none; border-top: 1px solid #f3f4f6; margin: 0.2rem 0; }
          .ctx button.danger { color: #dc2626; }
          .ctx button.danger:hover { background: #fef2f2; }

          /* Modals */
          .overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.35); display: flex; align-items: center; justify-content: center; z-index: 800; }
          .overlay[hidden] { display: none; }
          .modal { background: #fff; border-radius: 12px; padding: 1.5rem; width: 90%; max-width: 420px; box-shadow: 0 20px 60px rgba(0,0,0,0.15); }
          .modal h3 { font-size: 1rem; font-weight: 600; margin-bottom: 1rem; color: #111827; }
          .modal input[type=text] { width: 100%; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.875rem; outline: none; }
          .modal input[type=text]:focus { border-color: #3b82f6; box-shadow: 0 0 0 3px rgba(59,130,246,0.15); }
          .modal-actions { display: flex; justify-content: flex-end; gap: 0.5rem; margin-top: 1.25rem; }
          .btn { border: none; padding: 0.45rem 1rem; border-radius: 6px; cursor: pointer; font-size: 0.82rem; font-weight: 500; }
          .btn-secondary { background: #f3f4f6; color: #374151; }
          .btn-primary { background: #2563eb; color: #fff; }
          .btn-primary:hover { background: #1d4ed8; }
          .btn-danger { background: #dc2626; color: #fff; }

          /* Info modal table */
          .info-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.25rem; }
          .info-table td { padding: 0.375rem 0; color: #374151; }
          .info-table td:first-child { color: #6b7280; width: 45%; }

          /* Move modal dir list */
          .dir-list { max-height: 260px; overflow-y: auto; border: 1px solid #e5e7eb; border-radius: 6px; margin-top: 0.5rem; }
          .dir-item { display: flex; align-items: center; gap: 0.375rem; padding: 0.5rem 0.75rem; cursor: pointer; font-size: 0.83rem; color: #374151; border-bottom: 1px solid #f9fafb; }
          .dir-item:last-child { border-bottom: none; }
          .dir-item:hover { background: #f9fafb; }
          .dir-item.selected-dest { background: #eff6ff; color: #1d4ed8; font-weight: 600; }
          .dir-list-loading { padding: 1rem; text-align: center; color: #9ca3af; font-size: 0.82rem; }
        </style>
      </head>
      <body>

        <header>
          <h1>&#128193; Files</h1>
          <span class="meta">#{count_str} &nbsp;&middot;&nbsp; #{username}</span>
          <button class="nas-btn" id="nasHeaderBtn" onclick="openNas()">&#128427; NAS</button>
        </header>

        <nav class="breadcrumb">#{breadcrumb}</nav>

        <main>
          <div class="drop-zone" id="dropZone">
            <div class="dz-icon">&#8679;</div>
            <div class="dz-label">
              <strong>Upload files</strong>
              <span>Drag &amp; drop anywhere, or click to browse</span>
            </div>
            <input type="file" id="fileInput" multiple>
          </div>
          #{grid_or_empty}
        </main>

        <!-- Full-page drag overlay -->
        <div class="drag-overlay" id="dragOverlay">
          <div class="drag-card">
            <div class="icon">&#128194;</div>
            <p>Drop to upload</p>
          </div>
        </div>

        <!-- Upload toast -->
        <div class="toast" id="toast">
          <p id="toastText">Uploading&hellip;</p>
          <div class="toast-bar"><div class="toast-fill" id="toastFill"></div></div>
        </div>

        <!-- Background context menu -->
        <div class="ctx" id="bgCtx">
          <button onclick="openCreateDir()">&#128193;&ensp;New Folder</button>
          <hr>
          <button onclick="openInfo(null)">&#8505;&ensp;Get Info</button>
        </div>

        <!-- Item context menu -->
        <div class="ctx" id="itemCtx">
          <button id="ctxDownloadBtn" onclick="ctxDownload()">&#8659;&ensp;Download</button>
          <button onclick="openMoveModal()">&#8680;&ensp;Move&hellip;</button>
          <button id="ctxNasCopyBtn" onclick="ctxNasCopy()">&#128427;&ensp;Copy to NAS&hellip;</button>
          <hr>
          <button id="ctxInfoBtn" onclick="ctxInfo()">&#8505;&ensp;Get Info</button>
          <hr>
          <button class="danger" onclick="ctxDelete()">&#128465;&ensp;Delete</button>
        </div>

        <!-- Get Info modal -->
        <div class="overlay" id="infoModal" hidden>
          <div class="modal">
            <h3 id="infoTitle">Info</h3>
            <div id="infoContent"></div>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('infoModal')">Close</button>
            </div>
          </div>
        </div>

        <!-- Create Folder modal -->
        <div class="overlay" id="createDirModal" hidden>
          <div class="modal">
            <h3>New Folder</h3>
            <input type="text" id="newDirName" placeholder="Folder name" maxlength="128">
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('createDirModal')">Cancel</button>
              <button class="btn btn-primary"   onclick="confirmCreateDir()">Create</button>
            </div>
          </div>
        </div>

        <!-- Move modal -->
        <div class="overlay" id="moveModal" hidden>
          <div class="modal">
            <h3 id="moveTitle">Move to&hellip;</h3>
            <div class="dir-list" id="dirList"><div class="dir-list-loading">Loading&hellip;</div></div>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('moveModal')">Cancel</button>
              <button class="btn btn-primary"   id="confirmMoveBtn" onclick="confirmMove()" disabled>Move Here</button>
            </div>
          </div>
        </div>

        <!-- NAS credentials modal -->
        <div class="overlay" id="nasCredModal" hidden>
          <div class="modal">
            <h3>&#128427; Connect to NAS</h3>
            <p style="font-size:.82rem;color:#6b7280;margin-bottom:.75rem">
              Enter your TrueNAS username (your first name) and password to link your NAS share.
            </p>
            <label>Username</label>
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

        <!-- NAS browser modal -->
        <div class="overlay" id="nasBrowserModal" hidden>
          <div class="modal" style="max-width:660px;width:96vw">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:.75rem">
              <h3 style="margin:0">&#128427; NAS &mdash; <span id="nasShareLabel"></span></h3>
              <button class="btn btn-secondary" style="font-size:.72rem" onclick="openNasCredentials()">&#9881; Credentials</button>
            </div>
            <div class="nas-breadcrumb" id="nasBreadcrumb"></div>
            <div id="nasList" style="min-height:120px;max-height:55vh;overflow-y:auto;border:1px solid #e5e7eb;border-radius:6px">
              <div class="dir-list-loading">Loading&hellip;</div>
            </div>
            <div class="modal-actions">
              <button class="btn btn-secondary" onclick="closeModal('nasBrowserModal')">Close</button>
            </div>
          </div>
        </div>

        <!-- NAS copy-destination modal -->
        <div class="overlay" id="nasCopyModal" hidden>
          <div class="modal modal-wide">
            <h3 id="nasCopyTitle">Copy to NAS</h3>
            <p style="font-size:.8rem;color:#6b7280;margin-bottom:.4rem">Choose a destination folder on the NAS:</p>
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

        <!-- NAS browser context menu -->
        <div class="ctx" id="nasCtx">
          <button onclick="openNasNewFolderPrompt()">&#128193;&ensp;New Folder</button>
        </div>

        <script>
          // ── State ──────────────────────────────────────────────────────────
          const currentPath = #{current_path_json};
          const isMac       = /Mac|iPhone|iPad|iPod/.test(navigator.platform);
          const selectedPaths = new Set();
          let lastSelected  = null;    // tile element for shift-range
          let ctxTargetTile = null;    // tile under cursor when item ctx opened
          let selectedDest  = null;    // chosen destination in move modal

          // ── Tile selection ─────────────────────────────────────────────────
          function handleTileClick(e, tile) {
            if (e.detail === 2) return; // handled by dblclick
            const useMeta = isMac ? e.metaKey : e.ctrlKey;
            if (e.shiftKey && lastSelected) {
              const all = tiles();
              const a = parseInt(lastSelected.dataset.idx), b = parseInt(tile.dataset.idx);
              const [lo, hi] = a <= b ? [a, b] : [b, a];
              if (!useMeta) clearSel();
              all.filter(t => {
                const i = parseInt(t.dataset.idx);
                return i >= lo && i <= hi;
              }).forEach(t => { t.classList.add('selected'); selectedPaths.add(t.dataset.path); });
            } else if (useMeta) {
              tile.classList.toggle('selected');
              tile.classList.contains('selected') ? selectedPaths.add(tile.dataset.path) : selectedPaths.delete(tile.dataset.path);
              lastSelected = tile;
            } else {
              clearSel();
              tile.classList.add('selected');
              selectedPaths.add(tile.dataset.path);
              lastSelected = tile;
            }
          }

          function handleTileDblClick(tile) {
            if (tile.dataset.type === 'dir')
              window.location.href = '/?path=' + encodeURIComponent(tile.dataset.path);
          }

          function tiles() { return Array.from(document.querySelectorAll('.tile')); }
          function clearSel() {
            tiles().forEach(t => t.classList.remove('selected'));
            selectedPaths.clear();
          }

          document.addEventListener('click', e => {
            if (!e.target.closest('.tile') && !e.target.closest('.ctx') && !e.target.closest('.overlay')) clearSel();
            if (!e.target.closest('.ctx')) hideCtx();
          });

          // ── Context menus ──────────────────────────────────────────────────
          const bgCtx   = document.getElementById('bgCtx');
          const itemCtx = document.getElementById('itemCtx');

          function hideCtx() { bgCtx.classList.remove('visible'); itemCtx.classList.remove('visible'); }

          function positionCtx(menu, e) {
            menu.style.left = Math.min(e.clientX, window.innerWidth  - menu.offsetWidth  - 8) + 'px';
            menu.style.top  = Math.min(e.clientY, window.innerHeight - menu.offsetHeight - 8) + 'px';
          }

          document.addEventListener('contextmenu', e => {
            const tile = e.target.closest('.tile');
            const inMain = e.target.closest('main') || e.target.closest('.breadcrumb');
            if (!inMain) return;
            e.preventDefault();
            hideCtx();

            if (tile) {
              // If tile not already selected, replace selection with just this tile
              if (!tile.classList.contains('selected')) {
                clearSel();
                tile.classList.add('selected');
                selectedPaths.add(tile.dataset.path);
                lastSelected = tile;
              }
              ctxTargetTile = tile;
              const multi    = selectedPaths.size > 1;
              const isFile   = tile.dataset.type === 'file';
              document.getElementById('ctxDownloadBtn').style.display = (!multi && isFile) ? '' : 'none';
              document.getElementById('ctxInfoBtn').style.display     = !multi ? '' : 'none';
              document.getElementById('ctxNasCopyBtn').style.display  = isFile ? '' : 'none';
              itemCtx.style.left = '-9999px'; itemCtx.style.top = '-9999px';
              itemCtx.classList.add('visible');
              positionCtx(itemCtx, e);
            } else {
              bgCtx.style.left = '-9999px'; bgCtx.style.top = '-9999px';
              bgCtx.classList.add('visible');
              positionCtx(bgCtx, e);
            }
          });

          // ── Background ctx actions ─────────────────────────────────────────
          function openCreateDir() {
            hideCtx();
            document.getElementById('newDirName').value = '';
            document.getElementById('createDirModal').removeAttribute('hidden');
            setTimeout(() => document.getElementById('newDirName').focus(), 50);
          }

          function confirmCreateDir() {
            const name = document.getElementById('newDirName').value.trim();
            if (!name || /[\\/]/.test(name) || name.startsWith('.')) {
              alert('Invalid folder name'); return;
            }
            const fullPath = currentPath ? currentPath + '/' + name : name;
            fetch('/mkdir', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ path: fullPath })
            }).then(r => {
              if (r.ok) { closeModal('createDirModal'); location.reload(); }
              else r.json().then(d => alert(d.error || 'Error creating folder'));
            });
          }

          function openInfo(tile) {
            hideCtx();
            const path  = tile ? tile.dataset.path : currentPath;
            const title = tile ? tile.dataset.name  : (currentPath || 'Home');
            const type  = tile?.dataset.type;
            document.getElementById('infoTitle').textContent = title;
            document.getElementById('infoContent').innerHTML = '<p style="color:#9ca3af;font-size:.8rem">Loading&hellip;</p>';
            document.getElementById('infoModal').removeAttribute('hidden');

            if (type === 'file') {
              const mtime = tile.dataset.mtime ? new Date(tile.dataset.mtime).toLocaleString() : '&mdash;';
              document.getElementById('infoContent').innerHTML =
                '<table class="info-table">' +
                '<tr><td>Kind</td><td>File</td></tr>' +
                '<tr><td>Size</td><td>' + esc(tile.dataset.size) + '</td></tr>' +
                '<tr><td>Modified</td><td>' + mtime + '</td></tr>' +
                '</table>';
            } else {
              fetch('/info?path=' + encodeURIComponent(path))
                .then(r => r.json())
                .then(d => {
                  document.getElementById('infoContent').innerHTML =
                    '<table class="info-table">' +
                    '<tr><td>Kind</td><td>Folder</td></tr>' +
                    '<tr><td>Files</td><td>' + d.files + '</td></tr>' +
                    '<tr><td>Subfolders</td><td>' + d.dirs + '</td></tr>' +
                    '<tr><td>Total size</td><td>' + humanizeBytes(d.size) + '</td></tr>' +
                    '</table>';
                });
            }
          }

          // ── Item ctx actions ───────────────────────────────────────────────
          function ctxDownload() {
            hideCtx();
            if (!ctxTargetTile) return;
            const a = document.createElement('a');
            a.href = '/download/' + encodeURIComponent(ctxTargetTile.dataset.path);
            a.download = ctxTargetTile.dataset.name;
            document.body.appendChild(a); a.click(); a.remove();
          }

          function ctxInfo() { openInfo(ctxTargetTile); }

          function ctxDelete() {
            hideCtx();
            const items = Array.from(selectedPaths);
            if (!items.length) return;
            const label = items.length === 1 ? '"' + items[0].split('/').pop() + '"' : items.length + ' items';
            if (!confirm('Delete ' + label + '?')) return;
            Promise.all(items.map(p =>
              fetch('/delete/' + encodeURIComponent(p), { method: 'DELETE' })
            )).then(() => location.reload());
          }

          function openMoveModal() {
            hideCtx();
            const count = selectedPaths.size;
            document.getElementById('moveTitle').textContent =
              'Move ' + (count === 1 ? '"' + Array.from(selectedPaths)[0].split('/').pop() + '"' : count + ' items') + ' to\u2026';
            document.getElementById('dirList').innerHTML = '<div class="dir-list-loading">Loading\u2026</div>';
            document.getElementById('confirmMoveBtn').disabled = true;
            selectedDest = null;
            document.getElementById('moveModal').removeAttribute('hidden');

            fetch('/dirs').then(r => r.json()).then(dirs => {
              const html = dirs.map(d => {
                const pad  = 0.75 + d.depth * 1.1;
                const icon = d.depth === 0 ? '&#127968;' : '&#128193;';
                const isCurrent = d.path === currentPath;
                return '<div class="dir-item' + (isCurrent ? ' selected-dest' : '') + '"' +
                  ' data-path="' + esc(d.path) + '"' +
                  ' style="padding-left:' + pad + 'rem"' +
                  ' onclick="pickDestDir(this)">' +
                  icon + ' ' + esc(d.name) +
                  (isCurrent ? ' <span style="font-size:.7rem;color:#6b7280">(current)</span>' : '') +
                  '</div>';
              }).join('');
              document.getElementById('dirList').innerHTML = html || '<div class="dir-list-loading">No folders yet</div>';
              // Pre-select current dir
              const pre = document.querySelector('.dir-item.selected-dest');
              if (pre) { selectedDest = pre.dataset.path; document.getElementById('confirmMoveBtn').disabled = false; }
            });
          }

          function pickDestDir(el) {
            document.querySelectorAll('.dir-item').forEach(d => d.classList.remove('selected-dest'));
            el.classList.add('selected-dest');
            selectedDest = el.dataset.path;
            document.getElementById('confirmMoveBtn').disabled = false;
          }

          function confirmMove() {
            if (selectedDest === null) return;
            const items = Array.from(selectedPaths);
            fetch('/move', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ items, destination: selectedDest })
            }).then(() => { closeModal('moveModal'); location.reload(); });
          }

          // ── Modals ─────────────────────────────────────────────────────────
          function closeModal(id) { document.getElementById(id).setAttribute('hidden', ''); }

          // Close modal on overlay click
          document.querySelectorAll('.overlay').forEach(o => {
            o.addEventListener('click', e => { if (e.target === o) o.setAttribute('hidden', ''); });
          });

          // Enter key in folder name input
          document.getElementById('newDirName').addEventListener('keydown', e => {
            if (e.key === 'Enter') confirmCreateDir();
            if (e.key === 'Escape') closeModal('createDirModal');
          });

          // ── Drag & drop ────────────────────────────────────────────────────
          const dropZone    = document.getElementById('dropZone');
          const dragOverlay = document.getElementById('dragOverlay');
          const fileInput   = document.getElementById('fileInput');
          let dragDepth = 0;

          dropZone.addEventListener('click', () => fileInput.click());
          fileInput.addEventListener('change', () => {
            if (fileInput.files.length) uploadFiles(Array.from(fileInput.files));
          });

          document.addEventListener('dragover',  e => e.preventDefault());
          document.addEventListener('dragenter', e => {
            if (!e.dataTransfer?.types.includes('Files')) return;
            if (++dragDepth === 1) { dragOverlay.classList.add('active'); dropZone.classList.add('active'); }
          });
          document.addEventListener('dragleave', () => {
            if (--dragDepth <= 0) { dragDepth = 0; hideDrag(); }
          });
          document.addEventListener('drop', e => {
            e.preventDefault(); dragDepth = 0; hideDrag();
            if (e.dataTransfer.files.length) uploadFiles(Array.from(e.dataTransfer.files));
          });

          function hideDrag() { dragOverlay.classList.remove('active'); dropZone.classList.remove('active'); }

          // ── Upload ─────────────────────────────────────────────────────────
          const toast     = document.getElementById('toast');
          const toastText = document.getElementById('toastText');
          const toastFill = document.getElementById('toastFill');

          function uploadFiles(files) {
            let i = 0;
            toast.classList.add('visible');
            function next() {
              if (i >= files.length) { toast.classList.remove('visible'); location.reload(); return; }
              const file = files[i];
              toastText.textContent = file.name + ' (' + (i + 1) + '\u202f/\u202f' + files.length + ')';
              toastFill.style.width = '0%';
              const form = new FormData();
              form.append('file', file);
              const xhr = new XMLHttpRequest();
              xhr.open('POST', '/upload?path=' + encodeURIComponent(currentPath));
              xhr.upload.onprogress = ev => {
                if (ev.lengthComputable) toastFill.style.width = (ev.loaded / ev.total * 100) + '%';
              };
              xhr.onloadend = () => { i++; next(); };
              xhr.send(form);
            }
            next();
          }

          // ── Utilities ──────────────────────────────────────────────────────
          function esc(s) {
            return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
          }

          function humanizeBytes(b) {
            if (!b) return '0 B';
            const u = ['B','KB','MB','GB','TB'];
            const e = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
            return (b / Math.pow(1024, e)).toFixed(1) + ' ' + u[e];
          }

          // Keyboard shortcuts
          document.addEventListener('keydown', e => {
            if (e.key === 'Escape') {
              hideCtx(); hideNasCtx();
              closeModal('infoModal'); closeModal('createDirModal'); closeModal('moveModal');
              closeModal('nasCredModal'); closeModal('nasBrowserModal'); closeModal('nasCopyModal');
            }
            if ((e.key === 'Delete' || e.key === 'Backspace') && selectedPaths.size && !e.target.matches('input,textarea')) {
              e.preventDefault(); ctxDelete();
            }
            if (e.key === 'a' && (isMac ? e.metaKey : e.ctrlKey) && !e.target.matches('input,textarea')) {
              e.preventDefault();
              tiles().forEach(t => { t.classList.add('selected'); selectedPaths.add(t.dataset.path); });
            }
          });

          // ── NAS ──────────────────────────────────────────────────────────

          let nasConnected  = false;
          let nasCopySource = null;   // local relative path being copied to NAS
          let nasCopyDest   = '';     // current directory selected in NAS copy modal
          let nasBrowsePath = '';     // current path shown in NAS browser

          // Initialise NAS button state on page load
          fetch('/nas/status').then(r => r.json()).then(d => {
            nasConnected = d.connected;
            const btn = document.getElementById('nasHeaderBtn');
            if (d.connected) {
              btn.classList.add('connected');
              btn.innerHTML = '&#128427; NAS &mdash; ' + esc(d.username);
            }
          }).catch(() => {});

          async function openNas() {
            try {
              const d = await fetch('/nas/status').then(r => r.json());
              nasConnected = d.connected;
              if (nasConnected) {
                document.getElementById('nasShareLabel').textContent = d.username;
                openNasBrowser('');
              } else {
                openNasCredentials();
              }
            } catch (e) {
              openNasCredentials();
            }
          }

          function openNasCredentials() {
            closeModal('nasBrowserModal');
            document.getElementById('nasUsernameInput').value = '';
            document.getElementById('nasPasswordInput').value = '';
            document.getElementById('nasCredError').hidden = true;
            document.getElementById('nasCredModal').removeAttribute('hidden');
            setTimeout(() => document.getElementById('nasUsernameInput').focus(), 50);
          }

          async function saveNasCredentials() {
            const username = document.getElementById('nasUsernameInput').value.trim();
            const password = document.getElementById('nasPasswordInput').value;
            const errEl    = document.getElementById('nasCredError');
            const btn      = document.getElementById('nasCredSaveBtn');
            if (!username || !password) {
              errEl.textContent = 'Username and password are required';
              errEl.hidden = false; return;
            }
            btn.textContent = 'Connecting\u2026'; btn.disabled = true;
            try {
              const r = await fetch('/nas/credentials', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, password })
              });
              const d = await r.json();
              if (r.ok) {
                nasConnected = true;
                const hBtn = document.getElementById('nasHeaderBtn');
                hBtn.classList.add('connected');
                hBtn.innerHTML = '&#128427; NAS &mdash; ' + esc(username);
                closeModal('nasCredModal');
                document.getElementById('nasShareLabel').textContent = username;
                openNasBrowser('');
              } else {
                errEl.textContent = d.error || 'Connection failed';
                errEl.hidden = false;
              }
            } finally {
              btn.textContent = 'Connect'; btn.disabled = false;
            }
          }

          async function openNasBrowser(path = '') {
            nasBrowsePath = path;
            document.getElementById('nasBrowserModal').removeAttribute('hidden');
            document.getElementById('nasList').innerHTML = '<div class="dir-list-loading">Loading\u2026</div>';

            const r = await fetch('/nas/browse?path=' + encodeURIComponent(path));
            const d = await r.json();
            if (!r.ok) {
              document.getElementById('nasList').innerHTML =
                '<div class="dir-list-loading" style="color:#dc2626">' + esc(d.error || 'Error') + '</div>';
              return;
            }

            // Breadcrumb
            const parts = path.split('/').filter(Boolean);
            let crumbs = `<span class="nas-crumb" onclick="openNasBrowser()">NAS root</span>`;
            parts.forEach((p, i) => {
              const sub = parts.slice(0, i + 1).join('/');
              crumbs += ` \u203a <span class="nas-crumb" onclick="openNasBrowser('${esc(sub)}')">${esc(p)}</span>`;
            });
            document.getElementById('nasBreadcrumb').innerHTML = crumbs;

            // Items
            const items = d.items || [];
            if (!items.length) {
              document.getElementById('nasList').innerHTML = '<div class="dir-list-loading">Empty folder</div>';
              return;
            }

            // "Up" row when inside a subdirectory
            const parts2 = path.split('/').filter(Boolean);
            const parentPath = parts2.slice(0, -1).join('/');
            let html = path
              ? `<div class="nas-row nas-dir" onclick="openNasBrowser('${esc(parentPath)}')"><span style="font-size:1rem">&#8617;</span><span class="nas-row-name" style="color:#2563eb">Up</span></div>`
              : '';

            html += items.map(item => {
              const itemPath = path ? path + '/' + item.name : item.name;
              const icon = item.type === 'dir' ? '&#128193;' : '&#128196;';
              const iPath = esc(itemPath);
              const iName = esc(item.name);

              if (item.type === 'dir') {
                return `<div class="nas-row nas-dir" onclick="openNasBrowser('${iPath}')"><span style="font-size:1rem">${icon}</span><span class="nas-row-name">${iName}</span><span class="nas-row-size">&mdash;</span></div>`;
              } else {
                return `<div class="nas-row"><span style="font-size:1rem">${icon}</span><span class="nas-row-name" title="${iName}">${iName}</span><span class="nas-row-size">${humanizeBytes(item.size)}</span><div class="nas-row-actions"><button class="nas-action-btn" onclick="nasDownload('${iPath}','${iName}')">&#8659; Download</button><button class="nas-action-btn" onclick="nasCopyToLocal('${iPath}',this)">&#8594; Local</button></div></div>`;
              }
            }).join('');

            document.getElementById('nasList').innerHTML = html;
          }

          function nasDownload(nasPath, filename) {
            const a = document.createElement('a');
            a.href     = '/nas/download/' + encodeURIComponent(nasPath);
            a.download = filename;
            document.body.appendChild(a); a.click(); a.remove();
          }

          async function nasCopyToLocal(nasPath, btn) {
            const orig = btn.textContent;
            btn.textContent = 'Copying\u2026'; btn.disabled = true;
            try {
              const r = await fetch('/nas/copy-from-nas', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ nas_path: nasPath, local_path: currentPath })
              });
              const d = await r.json();
              if (r.ok) {
                btn.textContent = '\u2713 Done';
                setTimeout(() => { btn.textContent = orig; btn.disabled = false; }, 2000);
              } else {
                alert('Error: ' + (d.error || 'Copy failed'));
                btn.textContent = orig; btn.disabled = false;
              }
            } catch (e) {
              btn.textContent = orig; btn.disabled = false;
            }
          }

          // ── NAS browser context menu ──────────────────────────────────────

          const nasCtx = document.getElementById('nasCtx');

          document.getElementById('nasList').addEventListener('contextmenu', e => {
            e.preventDefault();
            e.stopPropagation();
            document.addEventListener('click', hideNasCtx, { once: true });
            nasCtx.style.left = '-9999px'; nasCtx.style.top = '-9999px';
            nasCtx.classList.add('visible');
            nasCtx.style.left = Math.min(e.clientX, window.innerWidth  - nasCtx.offsetWidth  - 8) + 'px';
            nasCtx.style.top  = Math.min(e.clientY, window.innerHeight - nasCtx.offsetHeight - 8) + 'px';
          });

          function hideNasCtx() { nasCtx.classList.remove('visible'); }

          async function openNasNewFolderPrompt() {
            hideNasCtx();
            const name = prompt('New folder name:');
            if (!name) return;
            if (/["\\\/\x00]/.test(name)) { alert('Invalid folder name'); return; }
            const fullPath = nasBrowsePath ? nasBrowsePath + '/' + name : name;
            const r = await fetch('/nas/mkdir', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ path: fullPath })
            });
            const d = await r.json();
            if (d.ok) {
              openNasBrowser(nasBrowsePath); // refresh current view
            } else {
              alert('Error: ' + (d.error || 'Failed to create folder'));
            }
          }

          // ── NAS copy-folder creation ───────────────────────────────────────

          async function createNasCopyFolder() {
            const input = document.getElementById('nasCopyNewFolder');
            const name  = input.value.trim();
            if (!name) return;
            if (/["\\\/\x00]/.test(name)) { alert('Invalid folder name'); return; }
            const fullPath = nasCopyDest ? nasCopyDest + '/' + name : name;
            const r = await fetch('/nas/mkdir', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ path: fullPath })
            });
            const d = await r.json();
            if (d.ok) {
              input.value = '';
              loadNasCopyDirs(fullPath); // navigate into newly created folder
            } else {
              alert('Error: ' + (d.error || 'Failed to create folder'));
            }
          }

          // ── Copy to NAS ───────────────────────────────────────────────────

          function ctxNasCopy() {
            hideCtx();
            const filePaths = Array.from(selectedPaths).filter(p => {
              const t = document.querySelector('.tile[data-path="' + p.replace(/"/g, '\\"') + '"]');
              return t && t.dataset.type === 'file';
            });
            if (!filePaths.length) return;
            nasCopySource = filePaths[0];
            const name = nasCopySource.split('/').pop();
            document.getElementById('nasCopyTitle').textContent = 'Copy \u201c' + name + '\u201d to NAS';

            if (!nasConnected) {
              alert('Connect to NAS first \u2014 click the NAS button in the header.');
              return;
            }
            loadNasCopyDirs('');
            document.getElementById('nasCopyModal').removeAttribute('hidden');
          }

          async function loadNasCopyDirs(path) {
            nasCopyDest = path;
            document.getElementById('nasCopyDirList').innerHTML = '<div class="dir-list-loading">Loading\u2026</div>';
            const r = await fetch('/nas/browse?path=' + encodeURIComponent(path));
            const d = await r.json();
            if (!r.ok) {
              document.getElementById('nasCopyDirList').innerHTML =
                '<div class="dir-list-loading" style="color:#dc2626">' + esc(d.error || 'Error') + '</div>';
              return;
            }
            const dirs  = (d.items || []).filter(i => i.type === 'dir');
            const parts = path.split('/').filter(Boolean);
            const parent = parts.slice(0, -1).join('/');
            let html = '';
            if (path) {
              html += `<div class="dir-item" onclick="loadNasCopyDirs('${esc(parent)}')" style="cursor:pointer">&#8617; Up</div>`;
            }
            const currentLabel = path || 'NAS root';
            html += `<div class="dir-item selected-dest" style="cursor:default">&#128194; ${esc(currentLabel)} <span style="font-size:.7rem">(copy here)</span></div>`;
            html += dirs.map(dir => {
              const dirPath = path ? path + '/' + dir.name : dir.name;
              return `<div class="dir-item" onclick="loadNasCopyDirs('${esc(dirPath)}')" style="cursor:pointer">&#128193; ${esc(dir.name)}</div>`;
            }).join('');
            document.getElementById('nasCopyDirList').innerHTML = html || '<div class="dir-list-loading">No subfolders</div>';
          }

          async function confirmNasCopy() {
            if (!nasCopySource) return;
            const btn = document.getElementById('nasCopyConfirmBtn');
            btn.textContent = 'Copying\u2026'; btn.disabled = true;
            try {
              const r = await fetch('/nas/copy', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ local_path: nasCopySource, nas_path: nasCopyDest })
              });
              const d = await r.json();
              if (r.ok) {
                closeModal('nasCopyModal');
                alert('\u2705 "' + nasCopySource.split('/').pop() + '" copied to NAS successfully.');
              } else {
                alert('Error: ' + (d.error || 'Copy failed'));
              }
            } finally {
              btn.textContent = 'Copy Here'; btn.disabled = false;
            }
          }

          // Enter key for NAS credentials form
          document.getElementById('nasPasswordInput').addEventListener('keydown', e => {
            if (e.key === 'Enter') saveNasCredentials();
          });
        </script>
      </body>
      </html>
    HTML
  end
end
