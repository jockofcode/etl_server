# FlowChain builds a structured chain representation of a parsed ETL flow.
#
# The chain is an ordered array of step hashes. Each step is:
#   {
#     key:      <string>  — the YAML node key
#     node:     <hash>    — the raw node config
#     branches: <hash>    — fork branches keyed by :on_success/:on_failure/:iterator
#   }
#
# - Linear flows produce a flat array.
# - check_data nodes produce :on_success and :on_failure branch arrays.
# - for_each_item nodes produce an :iterator branch array, then the main chain
#   continues via `next`.
module FlowChain
  module_function

  # Build the full chain for a parsed flow data hash.
  # Returns { entry_node:, chain: } or raises if START_NODE is missing.
  def build(flow_data)
    start_meta = flow_data["START_NODE"] || {}
    entry_key = start_meta["next"]
    {
      entry_node: entry_key,
      chain: chain_from(entry_key, flow_data, Set.new)
    }
  end

  # Recursively build the chain starting from `key`.
  def chain_from(key, flow_data, visited)
    return [] if key.nil? || visited.include?(key)

    node = flow_data[key]
    return [] if node.nil?

    visited = visited.dup.add(key)

    branches = {}

    # Fork branches for check_data (on_success / on_failure).
    if node["on_success"]
      branches[:on_success] = chain_from(node["on_success"], flow_data, visited)
    end
    if node["on_failure"]
      branches[:on_failure] = chain_from(node["on_failure"], flow_data, visited)
    end

    # Sub-flow branch for for_each_item iterator.
    if node["iterator"]
      branches[:iterator] = chain_from(node["iterator"], flow_data, visited)
    end

    step = { key: key, node: node, branches: branches }
    result = [ step ]

    # Continue main chain via `next`, but only if this node is not a pure fork
    # (check_data terminates into its branches and has no `next`).
    has_forks = node.key?("on_success") || node.key?("on_failure")
    next_key = node["next"]

    if next_key && !has_forks
      result.concat(chain_from(next_key, flow_data, visited))
    end

    result
  end
end

