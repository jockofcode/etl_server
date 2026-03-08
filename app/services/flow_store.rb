require "yaml"
require "fileutils"

# FlowStore manages reading and writing ETL flow YAML files from the flows
# directory (configured via ETL_FLOWS_DIR env var, defaulting to storage/flows/).
module FlowStore
  FLOWS_DIR = ENV.fetch("ETL_FLOWS_DIR", Rails.root.join("storage", "flows").to_s)
  YAML_EXT = ".yml"

  class FlowNotFound < StandardError; end
  class FlowAlreadyExists < StandardError; end
  class InvalidFlowData < StandardError; end

  module_function

  # Returns an array of flow summary hashes: { id:, name:, description: }
  def all
    Dir.glob(File.join(FLOWS_DIR, "*#{YAML_EXT}")).sort.map do |path|
      id = File.basename(path, YAML_EXT)
      data = safe_load(path)
      meta = data["START_NODE"] || {}
      { id: id, name: meta["name"], description: meta["description"] }
    end
  end

  # Returns the parsed flow data hash for a given id.
  def find(id)
    path = flow_path(id)
    raise FlowNotFound, "Flow '#{id}' not found" unless File.exist?(path)
    safe_load(path)
  end

  # Creates a new flow file. Raises FlowAlreadyExists if id is taken.
  def create(id, flow_data)
    validate_id!(id)
    path = flow_path(id)
    raise FlowAlreadyExists, "Flow '#{id}' already exists" if File.exist?(path)
    validate_flow_data!(flow_data)
    write(path, flow_data)
    flow_data
  end

  # Overwrites an existing flow. Raises FlowNotFound if id is absent.
  def update(id, flow_data)
    path = flow_path(id)
    raise FlowNotFound, "Flow '#{id}' not found" unless File.exist?(path)
    validate_flow_data!(flow_data)
    write(path, flow_data)
    flow_data
  end

  # Deletes a flow file. Raises FlowNotFound if absent.
  def destroy(id)
    path = flow_path(id)
    raise FlowNotFound, "Flow '#{id}' not found" unless File.exist?(path)
    FileUtils.rm(path)
    true
  end

  # Copies an existing flow to a new id.
  def copy(source_id, dest_id)
    validate_id!(dest_id)
    source_data = find(source_id)  # raises FlowNotFound if missing
    dest_path = flow_path(dest_id)
    raise FlowAlreadyExists, "Flow '#{dest_id}' already exists" if File.exist?(dest_path)
    write(dest_path, source_data)
    source_data
  end

  # -- private helpers -------------------------------------------------------

  def flow_path(id)
    File.join(FLOWS_DIR, "#{id}#{YAML_EXT}")
  end

  def safe_load(path)
    YAML.safe_load_file(path, permitted_classes: [ Symbol, ActiveSupport::HashWithIndifferentAccess ]) || {}
  end

  def write(path, data)
    FileUtils.mkdir_p(File.dirname(path))
    # Convert to plain Ruby hashes/arrays before serializing to avoid class-specific
    # YAML tags (e.g. !ruby/hash:ActiveSupport::HashWithIndifferentAccess) that
    # safe_load_file would reject on the next read.
    File.write(path, JSON.parse(data.to_json).to_yaml)
  end

  def validate_id!(id)
    # DNS hostname label rules: lowercase letters, digits, and hyphens only.
    # Must start and end with a letter or digit (no leading/trailing hyphens).
    # Underscores are intentionally excluded — they are illegal in DNS names.
    unless id.is_a?(String) && id.match?(/\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/)
      raise InvalidFlowData, "Flow id must contain only lowercase letters, digits, and hyphens, and must not start or end with a hyphen"
    end
  end

  def validate_flow_data!(data)
    raise InvalidFlowData, "Flow data must be a Hash" unless data.is_a?(Hash)
    raise InvalidFlowData, "Flow must have a START_NODE key" unless data.key?("START_NODE")
    meta = data["START_NODE"]
    raise InvalidFlowData, "START_NODE must have a 'name' key" unless meta.is_a?(Hash) && meta.key?("name")
  end
end

