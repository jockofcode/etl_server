# TransformSchema provides field metadata for every ETL transform type.
# Transforms are used inside transform_data nodes (the `transforms` array).
module TransformSchema
  # Shorthand constructor helpers
  def self.field(type, required: false, description: "")
    { type: type, required: required, description: description }
  end

  VALUE   = field("any",     description: "Operand value")
  PATTERN = field("string",  description: "Regex pattern string")
  START   = field("integer", description: "Zero-based start index")
  LENGTH  = field("integer", description: "Number of elements/chars")
  KEY     = field("string",  description: "Map key name")
  INDEX   = field("integer", description: "Zero-based index")
  SEARCH  = field("string",  description: "Search string")

  SCHEMAS = {
    # ── Math ──────────────────────────────────────────────────────────────────
    "add"                  => { category: "math", description: "Adds value to the input", fields: { "value" => VALUE } },
    "subtract"             => { category: "math", description: "Subtracts value from the input", fields: { "value" => VALUE } },
    "multiply"             => { category: "math", description: "Multiplies input by value", fields: { "value" => VALUE } },
    "divide"               => { category: "math", description: "Divides input by value (float)", fields: { "value" => VALUE } },
    "divide_whole"         => { category: "math", description: "Divides input by value (integer)", fields: { "value" => VALUE } },
    "absolute_value"       => { category: "math", description: "Returns the absolute value", fields: {} },
    "negate"               => { category: "math", description: "Negates the input", fields: {} },
    "remainder"            => { category: "math", description: "Input modulo value", fields: { "value" => VALUE } },
    "exponent"             => { category: "math", description: "Raises input to the power of value", fields: { "value" => VALUE } },
    "square_root"          => { category: "math", description: "Returns the square root", fields: {} },
    "cube_root"            => { category: "math", description: "Returns the cube root", fields: {} },
    "round_number"         => { category: "math", description: "Rounds to decimals decimal places", fields: { "decimals" => field("integer", description: "Decimal places (default 0)") } },
    "round_down"           => { category: "math", description: "Floors to nearest integer", fields: {} },
    "round_up"             => { category: "math", description: "Ceils to nearest integer", fields: {} },
    "round_towards_zero"   => { category: "math", description: "Truncates toward zero", fields: {} },
    "random_number"        => { category: "math", description: "Random float between min and max", fields: { "min" => VALUE, "max" => VALUE } },
    "random_whole_number"  => { category: "math", description: "Random integer between min and max", fields: { "min" => VALUE, "max" => VALUE } },

    # ── Logic ─────────────────────────────────────────────────────────────────
    "and"                  => { category: "logic", description: "True if both input and value are truthy", fields: { "value" => VALUE } },
    "or"                   => { category: "logic", description: "True if either input or value is truthy", fields: { "value" => VALUE } },
    "xor"                  => { category: "logic", description: "True if exactly one of input or value is truthy", fields: { "value" => VALUE } },
    "not"                  => { category: "logic", description: "Inverts the truthiness of the input", fields: {} },
    "exists"               => { category: "logic", description: "True if input is non-nil and non-empty", fields: {} },
    "equal_to"             => { category: "logic", description: "True if input equals value", fields: { "value" => VALUE } },
    "not_equal_to"         => { category: "logic", description: "True if input does not equal value", fields: { "value" => VALUE } },
    "greater_than"         => { category: "logic", description: "True if input is greater than value", fields: { "value" => VALUE } },
    "greater_than_or_equal" => { category: "logic", description: "True if input is >= value", fields: { "value" => VALUE } },
    "less_than"            => { category: "logic", description: "True if input is less than value", fields: { "value" => VALUE } },
    "less_than_or_equal"   => { category: "logic", description: "True if input is <= value", fields: { "value" => VALUE } },
    "match"                => { category: "logic", description: "True if input matches the regex pattern", fields: { "pattern" => PATTERN } },
    "if_else"              => { category: "logic", description: "Returns on_true if condition is met, otherwise on_false", fields: { "condition" => field("object", required: true, description: "Transform config evaluated as condition ({type:, ...})"), "on_true" => field("any", required: true, description: "Value returned when condition is truthy (supports {{interpolation}})"), "on_false" => field("any", description: "Value returned when condition is falsy (supports {{interpolation}})") } },

    # ── Text ──────────────────────────────────────────────────────────────────
    "concatenate"          => { category: "text", description: "Appends value to the input string", fields: { "value" => field("string") } },
    "append_text"          => { category: "text", description: "Appends value to the end of input", fields: { "value" => field("string") } },
    "prepend_text"         => { category: "text", description: "Prepends value to the start of input", fields: { "value" => field("string") } },
    "upper_case"           => { category: "text", description: "Converts input to uppercase", fields: {} },
    "lower_case"           => { category: "text", description: "Converts input to lowercase", fields: {} },
    "capitalize_words"     => { category: "text", description: "Capitalizes first letter of each word", fields: {} },
    "trim_text"            => { category: "text", description: "Strips leading and trailing whitespace", fields: {} },
    "left_trim"            => { category: "text", description: "Strips leading whitespace", fields: {} },
    "right_trim"           => { category: "text", description: "Strips trailing whitespace", fields: {} },
    "replace_text"         => { category: "text", description: "Replaces all occurrences of search with replace", fields: { "search" => SEARCH, "replace" => field("string", description: "Replacement string") } },
    "sub_text"             => { category: "text", description: "Extracts substring starting at start with optional length", fields: { "start" => START, "length" => LENGTH } },
    "text_length"          => { category: "text", description: "Returns the number of characters", fields: {} },
    "text_contains"        => { category: "text", description: "True if input contains the search string", fields: { "search" => SEARCH } },
    "search_text"          => { category: "text", description: "Returns index of search in input, or -1", fields: { "search" => SEARCH } },
    "match_text"           => { category: "text", description: "Returns first regex match (or capture group)", fields: { "pattern" => PATTERN, "group" => field("integer", description: "Capture group index") } },
    "split_text"           => { category: "text", description: "Splits input by delimiter into a list", fields: { "delimiter" => field("string", description: "Split delimiter") } },
    "split_into_lines"     => { category: "text", description: "Splits input into a list of lines", fields: {} },
    "split_into_words"     => { category: "text", description: "Splits input into a list of words", fields: {} },
    "create_hash"          => { category: "text", description: "Hashes the input using algorithm", fields: { "algorithm" => field("string", description: "md5, sha1, sha256, sha512") } },
    "create_hmac"          => { category: "text", description: "Creates an HMAC using algorithm and secret", fields: { "algorithm" => field("string"), "secret" => field("string", description: "HMAC secret key") } },
    "extract_html_text"    => { category: "text", description: "Extracts text content from HTML", fields: { "selector" => field("string", description: "CSS selector (optional)") } },
    "extract_html_attribute" => { category: "text", description: "Extracts an HTML attribute from a CSS selector", fields: { "selector" => field("string", required: true), "attribute" => field("string", required: true) } },
    "extract_html_inner"   => { category: "text", description: "Returns inner HTML of a CSS selector", fields: { "selector" => field("string", required: true) } },
    "extract_html_outer"   => { category: "text", description: "Returns outer HTML of a CSS selector", fields: { "selector" => field("string", required: true) } },

    # ── Lists ─────────────────────────────────────────────────────────────────
    "count"                    => { category: "lists", description: "Returns the number of items", fields: {} },
    "first_item"               => { category: "lists", description: "Returns the first item", fields: {} },
    "last_item"                => { category: "lists", description: "Returns the last item", fields: {} },
    "all_but_first"            => { category: "lists", description: "Returns all items except the first", fields: {} },
    "all_but_last"             => { category: "lists", description: "Returns all items except the last", fields: {} },
    "reverse_list"             => { category: "lists", description: "Reverses the list", fields: {} },
    "flatten_list"             => { category: "lists", description: "Flattens one level of nesting", fields: {} },
    "flatten_list_recursive"   => { category: "lists", description: "Flattens all levels of nesting", fields: {} },
    "randomize_list"           => { category: "lists", description: "Shuffles the list", fields: {} },
    "random_item"              => { category: "lists", description: "Returns a random item from the list", fields: {} },
    "sort_list"                => { category: "lists", description: "Sorts the list", fields: {} },
    "sort_by_key"              => { category: "lists", description: "Sorts a list of maps by key", fields: { "key" => KEY } },
    "list_append"              => { category: "lists", description: "Appends value to the list", fields: { "value" => VALUE } },
    "get_item_at_index"        => { category: "lists", description: "Returns the item at index", fields: { "index" => INDEX } },
    "set_item_at_index"        => { category: "lists", description: "Sets the item at index to value", fields: { "index" => INDEX, "value" => VALUE } },
    "remove_index"             => { category: "lists", description: "Removes the item at index", fields: { "index" => INDEX } },
    "extract_part"             => { category: "lists", description: "Returns a slice starting at start with optional length", fields: { "start" => START, "length" => LENGTH } },
    "list_contains"            => { category: "lists", description: "True if the list contains value", fields: { "value" => VALUE } },
    "list_get_index"           => { category: "lists", description: "Returns the index of value in the list, or -1", fields: { "value" => VALUE } },
    "filter_matches"           => { category: "lists", description: "Keeps items where key equals value", fields: { "key" => KEY, "value" => VALUE } },
    "filter_non_matches"       => { category: "lists", description: "Keeps items where key does not equal value", fields: { "key" => KEY, "value" => VALUE } },
    "compact"                  => { category: "lists", description: "Removes nil and empty-string items from the list", fields: {} },
    "filter_unique"            => { category: "lists", description: "Removes duplicate items", fields: {} },
    "filter_unique_by_key"     => { category: "lists", description: "Removes items with duplicate values at key", fields: { "key" => KEY } },
    "join_list"                => { category: "lists", description: "Joins list items into a string", fields: { "separator" => field("string", description: "Separator (default ', ')") } },
    "pluck_values"             => { category: "lists", description: "Extracts key value from each item", fields: { "key" => KEY } },
    "group_by_value"           => { category: "lists", description: "Groups list items into a map keyed by key value", fields: { "key" => KEY } },
    "aggregate_array"          => { category: "lists", description: "Aggregates numeric values: sum, avg, min, or max", fields: { "operation" => field("string", description: "sum, avg, min, or max") } },
    "aggregate_by_group"       => { category: "lists", description: "Groups by group_key then aggregates value_key", fields: { "group_key" => KEY, "value_key" => KEY, "operation" => field("string") } },
    "array_to_map"             => { category: "lists", description: "Converts a list of maps to a single map keyed by key_field", fields: { "key_field" => field("string", required: true) } },
    "combine_without_duplicates" => { category: "lists", description: "Union of input list and other, deduplicated", fields: { "other" => field("array") } },
    "get_common_items"         => { category: "lists", description: "Intersection of input list and other", fields: { "other" => field("array") } },
    "remove_items_in_other"    => { category: "lists", description: "Difference: input list minus items in other", fields: { "other" => field("array") } },
    "transpose"                => { category: "lists", description: "Transposes a 2D list", fields: {} },
    "each_as_list"             => { category: "lists", description: "Wraps each item in its own single-element list", fields: {} },

    # ── Maps ──────────────────────────────────────────────────────────────────
    "map_get"           => { category: "maps", description: "Returns the value at key", fields: { "key" => KEY } },
    "map_has_key"       => { category: "maps", description: "True if the map contains key", fields: { "key" => KEY } },
    "map_keys"          => { category: "maps", description: "Returns all keys as a list", fields: {} },
    "map_values"        => { category: "maps", description: "Returns all values as a list", fields: {} },
    "map_pairs"         => { category: "maps", description: "Returns key-value pairs as a list of {key, value} maps", fields: {} },
    "map_size"          => { category: "maps", description: "Returns the number of entries", fields: {} },
    "map_with_entry"    => { category: "maps", description: "Returns a copy of the map with key set to value", fields: { "key" => KEY, "value" => VALUE } },
    "map_without_entry" => { category: "maps", description: "Returns a copy of the map with key removed", fields: { "key" => KEY } },
    "merge_maps"        => { category: "maps", description: "Merges other map into the input map", fields: { "other" => field("object", description: "Map to merge in") } },

    # ── Type Conversions ──────────────────────────────────────────────────────
    "as_is"                    => { category: "type_conversions", description: "Returns the input unchanged", fields: {} },
    "copy"                     => { category: "type_conversions", description: "Returns a deep copy of the input", fields: {} },
    "boolean"                  => { category: "type_conversions", description: "Converts input to a boolean", fields: {} },
    "number"                   => { category: "type_conversions", description: "Converts input to an integer or float", fields: {} },
    "whole_number"             => { category: "type_conversions", description: "Converts input to an integer", fields: {} },
    "text"                     => { category: "type_conversions", description: "Converts input to a string", fields: {} },
    "number_to_fixed_decimal"  => { category: "type_conversions", description: "Formats a number as a fixed-decimal string", fields: { "decimals" => field("integer", required: true, description: "Number of decimal places") } },
    "list"                     => { category: "type_conversions", description: "Wraps non-arrays in a list; passes arrays through", fields: {} },
    "map"                      => { category: "type_conversions", description: "Returns the input if it is a Hash, otherwise raises", fields: {} },
    "date"                     => { category: "type_conversions", description: "Parses input to a Date", fields: { "format" => field("string", description: "strptime format string") } },
    "timestamp"                => { category: "type_conversions", description: "Parses input to a UTC Time", fields: { "format" => field("string", description: "strptime format string") } },
    "date_to_string"           => { category: "type_conversions", description: "Formats a date or timestamp as a string", fields: { "format" => field("string", description: "strftime format (default %Y-%m-%d)") } },

    # ── Dates ─────────────────────────────────────────────────────────────────
    "current_date"         => { category: "dates", description: "Returns today's date", fields: {} },
    "current_timestamp"    => { category: "dates", description: "Returns the current UTC timestamp", fields: {} },
    "day_of_month"         => { category: "dates", description: "Returns the day of the month (1-31)", fields: {} },
    "day_of_week_number"   => { category: "dates", description: "Returns the day of the week (0=Sunday … 6=Saturday)", fields: {} },
    "day_of_week_text"     => { category: "dates", description: "Returns the day name (e.g. Monday)", fields: {} },
    "month_number"         => { category: "dates", description: "Returns the month number (1-12)", fields: {} },
    "month_text"           => { category: "dates", description: "Returns the month name (e.g. January)", fields: {} },
    "year"                 => { category: "dates", description: "Returns the four-digit year", fields: {} },
    "years_ago"            => { category: "dates", description: "Returns the date value years in the past", fields: { "value" => VALUE } },
    "months_ago"           => { category: "dates", description: "Returns the date value months in the past", fields: { "value" => VALUE } },
    "adjust_by_timezone"   => { category: "dates", description: "Shifts a timestamp by offset hours", fields: { "offset" => field("integer", description: "Hour offset") } },
    "truncate_to_day"      => { category: "dates", description: "Returns the date with time set to midnight", fields: {} },
    "truncate_to_month"    => { category: "dates", description: "Returns the first day of the month", fields: {} },
    "truncate_to_year"     => { category: "dates", description: "Returns the first day of the year", fields: {} },
    "truncate_to_hour"     => { category: "dates", description: "Returns the timestamp truncated to the hour", fields: {} },
    "truncate_to_minute"   => { category: "dates", description: "Returns the timestamp truncated to the minute", fields: {} },

    # ── Encoding ──────────────────────────────────────────────────────────────
    "base64_encode"  => { category: "encoding", description: "Base64-encodes the input string", fields: {} },
    "base64_decode"  => { category: "encoding", description: "Decodes a Base64-encoded string", fields: {} },
    "json_encode"    => { category: "encoding", description: "Serializes input to a JSON string", fields: {} },
    "json_decode"    => { category: "encoding", description: "Parses a JSON string into a Ruby object", fields: {} },
    "uri_encode"     => { category: "encoding", description: "URL-encodes the input string", fields: {} },
    "uri_decode"     => { category: "encoding", description: "URL-decodes the input string", fields: {} },
    "csv_encode"     => { category: "encoding", description: "Serializes a 2D array to a CSV string", fields: {} },
    "csv_decode"     => { category: "encoding", description: "Parses a CSV string into a 2D array", fields: { "headers" => field("boolean", description: "Pass true to get a list of maps") } },
    "xml_decode"     => { category: "encoding", description: "Parses an XML string into a nested Hash", fields: {} },
    "x12_decode"     => { category: "encoding", description: "Parses an X12/EDI string into a list of segment arrays", fields: {} },
    "x12_decode_v2"  => { category: "encoding", description: "Alias for x12_decode", fields: {} },
    "x12_encode"     => { category: "encoding", description: "Encodes a list of segment arrays back to an X12 string", fields: {} },
  }.freeze

  module_function

  def all
    SCHEMAS
  end

  def for_type(type)
    SCHEMAS[type.to_s]
  end

  def valid_fields(type)
    schema = SCHEMAS[type.to_s]
    return [] unless schema
    schema[:fields].keys + [ "type" ]
  end

  def sanitize(type, transform_data)
    allowed = valid_fields(type)
    transform_data.select { |k, _| allowed.include?(k.to_s) }
  end

  def known?(type)
    SCHEMAS.key?(type.to_s)
  end

  def by_category
    SCHEMAS.group_by { |_, v| v[:category] }
           .transform_values { |pairs| pairs.to_h }
  end
end

