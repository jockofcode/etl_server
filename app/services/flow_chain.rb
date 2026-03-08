# FlowChain builds a structured chain representation of a parsed ETL flow.
#
# The chain is an ordered array of step hashes. Each step is:
#   {
#     key:      <string>  — the YAML node key
#     node:     <hash>    — the raw node config
#     branches: <hash>    — fork branches keyed by symbol
#   }
#
# Branch values:
#   :on_success / :on_failure — array of chains (each chain is an array of steps).
#                               A single-target node produces a one-element outer array.
#                               A multi-target (fan-out) node produces N chains.
#   :iterator                 — a single chain (array of steps) for the sub-flow.
#   :next_branches            — array of chains when `next` is an array of 2+ keys (fan-out).
#
# - Linear flows produce a flat array.
# - check_data nodes produce :on_success and/or :on_failure branch arrays.
# - for_each_item nodes produce an :iterator branch array, then the main chain
#   continues via `next`.
# - Any node whose `next` is an array of 2+ keys produces :next_branches (fan-out).
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
    # Values may be a single key (string) or multiple keys (array) for fan-out.
    # The branch value is always an array of chains: [[...steps...], [...steps...]].
    if node["on_success"]
      targets = Array(node["on_success"])
      branches[:on_success] = targets.map { |t| chain_from(t, flow_data, visited) }
    end
    if node["on_failure"]
      targets = Array(node["on_failure"])
      branches[:on_failure] = targets.map { |t| chain_from(t, flow_data, visited) }
    end

    # Sub-flow branch for for_each_item iterator.
    if node["iterator"]
      branches[:iterator] = chain_from(node["iterator"], flow_data, visited)
    end

    # Fan-out via `next` when it is an array of 2+ targets.
    has_forks    = node.key?("on_success") || node.key?("on_failure")
    next_targets = Array(node["next"]).compact

    if next_targets.length > 1
      branches[:next_branches] = next_targets.map { |t| chain_from(t, flow_data, visited) }
    end

    step   = { key: key, node: node, branches: branches }
    result = [ step ]

    # Continue the main chain for a single `next` target unless the node forks.
    if next_targets.length == 1 && !has_forks
      result.concat(chain_from(next_targets.first, flow_data, visited))
    end

    result
  end
end
