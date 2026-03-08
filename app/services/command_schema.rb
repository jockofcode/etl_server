# CommandSchema provides field metadata for each ETL command type.
# Used to display only valid fields in the UI and strip invalid fields on save.
module CommandSchema
  # Field descriptor keys:
  #   type        - "string" | "integer" | "object" | "array" | "boolean"
  #   required    - true | false
  #   description - human-readable explanation
  SCHEMAS = {
    "transform_data" => {
      description: "Applies a pipeline of transforms to an input value and stores the result",
      fields: {
        "input"      => { type: "string",     required: true,  description: "Value to transform (supports {{interpolation}})" },
        "transforms" => { type: "array",      required: false, description: "Array of transform configs ({type:, ...})" },
        "output"     => { type: "string",     required: false, description: "Context key to store the result" },
        "next"       => { type: "node_array", required: false, description: "Next node(s) to run after this step" }
      }
    },
    "check_data" => {
      description: "Evaluates a condition and branches to on_success or on_failure",
      fields: {
        "input"      => { type: "string",     required: true,  description: "Value to test (supports {{interpolation}})" },
        "check"      => { type: "object",     required: true,  description: "Transform config used as the condition ({type:, ...})" },
        "on_success" => { type: "node_array", required: true,  description: "Node(s) to run when condition is truthy" },
        "on_failure" => { type: "node_array", required: true,  description: "Node(s) to run when condition is falsy" }
      }
    },
    "for_each_item" => {
      description: "Iterates over a list, running a sub-flow for each item",
      fields: {
        "input"      => { type: "string",     required: true,  description: "The list to iterate (supports {{interpolation}})" },
        "item_key"   => { type: "string",     required: false, description: "Context key for the current item (default: 'item')" },
        "index_key"  => { type: "string",     required: false, description: "Context key for the current index (default: 'index')" },
        "iterator"   => { type: "string",     required: true,  description: "First node key of the per-item sub-flow" },
        "result_key" => { type: "string",     required: false, description: "Context key where collected results are stored" },
        "next"       => { type: "node_array", required: false, description: "Next node(s) after all iterations complete" }
      }
    },
    "respond_with_success" => {
      description: "Terminates the flow with a success response",
      fields: {
        "status"  => { type: "integer", required: false, description: "HTTP status code (default 200)" },
        "body"    => { type: "string",  required: false, description: "Response body (supports {{interpolation}})" },
        "headers" => { type: "object",  required: false, description: "Hash of response headers (e.g. Content-Type)" }
      }
    },
    "respond_with_error" => {
      description: "Terminates the flow with an error response",
      fields: {
        "status"  => { type: "integer", required: false, description: "HTTP status code (default 400)" },
        "body"    => { type: "string",  required: false, description: "Response body (supports {{interpolation}})" },
        "headers" => { type: "object",  required: false, description: "Hash of response headers (e.g. Content-Type)" }
      }
    },
    "send_to_url" => {
      description: "Makes an outbound HTTP request and optionally stores the response",
      fields: {
        "url"        => { type: "string",     required: true,  description: "Target URL (supports {{interpolation}})" },
        "method"     => { type: "string",     required: false, description: "HTTP method: GET, POST, PUT, PATCH, DELETE (default POST)" },
        "body"       => { type: "string",     required: false, description: "Request body (supports {{interpolation}})" },
        "headers"    => { type: "object",     required: false, description: "Hash of request headers" },
        "output"     => { type: "string",     required: false, description: "Context key to store the response body" },
        "status_key" => { type: "string",     required: false, description: "Context key to store the response HTTP status code" },
        "next"       => { type: "node_array", required: false, description: "Next node(s) to run after this step" }
      }
    },
    "log_data" => {
      description: "Logs a value to stderr without affecting flow execution",
      fields: {
        "input" => { type: "string",     required: true,  description: "Value to log (supports {{interpolation}})" },
        "next"  => { type: "node_array", required: false, description: "Next node(s) to run after logging" }
      }
    },
    "return_data_to_iterator" => {
      description: "Returns a value from an iterator sub-flow back to for_each_item",
      fields: {
        "data" => { type: "string", required: true, description: "Value to return (supports {{interpolation}})" }
      }
    },
    "return_error_to_iterator" => {
      description: "Signals an error from an iterator sub-flow back to for_each_item",
      fields: {
        "error" => { type: "string", required: true, description: "Error value to return (supports {{interpolation}})" }
      }
    }
  }.freeze

  module_function

  # All schemas keyed by command type string.
  def all
    SCHEMAS
  end

  # Schema for a specific command type; nil if unknown.
  def for_type(type)
    SCHEMAS[type.to_s]
  end

  # Returns the list of valid field names for a command type.
  # Always includes "type" (the node type discriminator).
  def valid_fields(type)
    schema = SCHEMAS[type.to_s]
    return [] unless schema
    schema[:fields].keys + [ "type" ]
  end

  # Removes any keys from `node_data` that are not valid for the given type.
  # Returns a new hash with only valid fields.
  def sanitize(type, node_data)
    allowed = valid_fields(type)
    node_data.select { |k, _| allowed.include?(k.to_s) }
  end

  # Returns true if the command type is known.
  def known?(type)
    SCHEMAS.key?(type.to_s)
  end
end

